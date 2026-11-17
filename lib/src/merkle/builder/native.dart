import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/builder/types.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/provider.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';
import 'merkle.dart';

/// Pure-Rust [MerkleController].
///
/// Every note-commitment operation (leaf appends, subtree absorbs,
/// checkpoints, witness creation) runs in the Rust backend
/// (`blockchainUtils.api.merkle`). No Dart shard trees are kept: the wallet
/// persists [NativeMerkleState] bytes only (an exact tip-leaf journal plus
/// absorbed-subtree indices), and restore rebuilds the mirror from that
/// journal plus completed subtree roots fetched from lightwalletd.
///
/// Contiguity is fail-closed: a scanned batch must continue exactly where
/// the mirror left off (per pool). Re-feeding the exact same leaves is a
/// no-op (byte-identical overlap is skipped); any gap or divergent leaf
/// throws [BuError] instead of silently falling back.
class NativeMerkleController implements MerkleController {
  final ZcashCryptoContext context;
  final IGrpcProvider<
    IServiceProvider,
    IServiceRequestParams,
    BaseGRPCServiceRequestParams
  >
  provider;
  final TreeLevel shardHeight = TreeLevel(NoteEncryptionConst.shardHeight);

  int? _contextId;
  final _lock = SafeAtomicLock();
  final Set<int> _nativeCheckpoints = {};

  /// Native tip size per pool kind. Initialized exactly on restore (journal
  /// tip) or fresh start (zero); every live feed asserts contiguity
  /// against it, so mirror/feed divergence fails loudly, never silently.
  final Map<int, int> _nativeSizes = {};

  /// Tip journal, per native pool kind. Maintained live from scanned
  /// bundles (exact leaf data, pre-pruning); truncated on subtree absorb.
  final Map<int, _PoolJournal> _journal = {};

  /// True once the native mirror reflects persisted + live state.
  bool _mirrorReady = false;

  int _saplingSubtreeIndex = 0;
  int _orchardSubtreeIndex = 0;
  int _ironwoodSubtreeIndex = 0;
  int get saplingSubtreeIndex => _saplingSubtreeIndex;
  int get orchardSubtreeIndex => _orchardSubtreeIndex;
  int get ironwoodSubtreeIndex => _ironwoodSubtreeIndex;

  MerkleApi get _merkle => blockchainUtils.api.merkle;

  NativeMerkleController._({
    required this.context,
    required this.provider,
    MirrorTipJournal? journal,
    int? saplingSubtreeIndex,
    int? orchardSubtreeIndex,
    int? ironwoodSubtreeIndex,
  }) : _saplingSubtreeIndex = saplingSubtreeIndex ?? 0,
       _orchardSubtreeIndex = orchardSubtreeIndex ?? 0,
       _ironwoodSubtreeIndex = ironwoodSubtreeIndex ?? 0 {
    _loadJournal(journal);
  }

  factory NativeMerkleController({
    required ZcashCryptoContext context,
    required IGrpcProvider<
      IServiceProvider,
      IServiceRequestParams,
      BaseGRPCServiceRequestParams
    >
    provider,
  }) {
    return NativeMerkleController._(context: context, provider: provider);
  }

  factory NativeMerkleController.fromState({
    required ZcashCryptoContext context,
    required IGrpcProvider<
      IServiceProvider,
      IServiceRequestParams,
      BaseGRPCServiceRequestParams
    >
    provider,
    required NativeMerkleState state,
  }) {
    return NativeMerkleController._(
      context: context,
      provider: provider,
      journal: state.journal,
      orchardSubtreeIndex: state.orchardSubtreeIndex,
      saplingSubtreeIndex: state.saplingSubtreeIndex,
      ironwoodSubtreeIndex: state.ironwoodSubtreeIndex,
    );
  }

  factory NativeMerkleController.deserialize({
    List<int>? bytes,
    CborObject? obj,
    required ZcashCryptoContext context,
    required ZcashWalletdProvider provider,
  }) {
    final state = NativeMerkleState.deserialize(bytes: bytes, object: obj);
    return NativeMerkleController.fromState(
      context: context,
      provider: provider,
      state: state,
    );
  }

  static T _call<T>(String op, T Function() run) {
    try {
      return run();
    } on BuError catch (e) {
      throw ZcashErrors.merkleBuilderFailed(op, reason: e.message);
    }
  }

  static int _buKind(ZcashProtocol protocol) {
    return switch (protocol) {
      ZcashProtocol.sapling => MerkleApi.sapling,
      ZcashProtocol.orchard => MerkleApi.orchard,
      _ =>
        throw ZcashErrors.merkleBuilderFailed(
          "merkle",
          reason: "Unsupported protocol ${protocol.name} for native mirror.",
        ),
    };
  }

  /// Latest block id covered by the journal (every fed block is
  /// checkpointed), or null when nothing was ever fed.
  int? get _lastFedBlock {
    int? max;
    for (final j in _journal.values) {
      for (final id in j.checkpoints.keys) {
        if (max == null || id > max) max = id;
      }
    }
    return max;
  }

  _PoolJournal _poolJournal(int kind) =>
      _journal.putIfAbsent(kind, () => _PoolJournal());

  void _loadJournal(MirrorTipJournal? journal) {
    if (journal == null) return;
    _poolJournal(MerkleApi.sapling).restore(
      base: journal.sapling.base,
      leaves: journal.sapling.leaves,
      checkpoints: journal.sapling.checkpoints,
    );
    _poolJournal(MerkleApi.orchard).restore(
      base: journal.orchard.base,
      leaves: journal.orchard.leaves,
      checkpoints: journal.orchard.checkpoints,
    );
    _poolJournal(MerkleApi.ironwood).restore(
      base: journal.ironwood.base,
      leaves: journal.ironwood.leaves,
      checkpoints: journal.ironwood.checkpoints,
    );
  }

  MirrorTipJournal _exportJournal() {
    PoolTipJournal pack(int kind) {
      final j = _journal[kind];
      if (j == null) return const PoolTipJournal();
      return PoolTipJournal(
        base: j.base,
        leaves: List<int>.from(j.leaves),
        checkpoints: Map<int, int>.from(j.checkpoints),
      );
    }

    return MirrorTipJournal(
      sapling: pack(MerkleApi.sapling),
      orchard: pack(MerkleApi.orchard),
      ironwood: pack(MerkleApi.ironwood),
    );
  }

  Future<int> _getOrCreateContext() async {
    return _lock.run(() async {
      int? id = _contextId;
      if (id != null) return id;
      final newId = _call<int>('createContext', () => _merkle.createContext());
      _contextId = newId;
      return newId;
    }, lockId: LockId.two);
  }

  /// should not used controlle after close context.
  Future<void> closeContext() async {
    return _lock.run(() async {
      int? id = _contextId;
      if (id == null) return;
      _call('closeContext', () => _merkle.closeContext(id));
      _contextId = null;
      _nativeCheckpoints.clear();
      _nativeSizes.clear();
      // Journal survives (it describes persisted + live tip); the next
      // use rebuilds the mirror from it.
      _mirrorReady = false;
    }, lockId: LockId.two);
  }

  /// Ensure the native mirror reflects persisted + live state. Restores
  /// from the journal on first use (fetching completed subtree roots from
  /// lightwalletd); fresh wallets start from exact zero. Any failure
  /// throws fail-closed: there is no Dart-tree fallback.
  Future<void> _ensureReady() async {
    if (_mirrorReady) return;
    final hasWork = _journal.values.any((j) => !j.isEmpty);
    if (!hasWork) {
      // Fresh wallet: empty mirror is exact. Every pool starts at zero so
      // the contiguity gate below is strict from the first leaf.
      _nativeSizes[MerkleApi.sapling] = 0;
      _nativeSizes[MerkleApi.orchard] = 0;
      _nativeSizes[MerkleApi.ironwood] = 0;
      _mirrorReady = true;
      return;
    }
    try {
      final contextId = await _getOrCreateContext();
      for (final kind in const [
        MerkleApi.sapling,
        MerkleApi.orchard,
        MerkleApi.ironwood,
      ]) {
        await _restorePool(contextId, kind);
      }
      await _replayJournal(contextId);
      // Align live-fetch indices with replayed absorbs (journal base is
      // authoritative for what the mirror now holds). Indices never move
      // backwards.
      _saplingSubtreeIndex = _maxIndex(
        _saplingSubtreeIndex,
        _journal[MerkleApi.sapling]?.base ?? 0,
      );
      _orchardSubtreeIndex = _maxIndex(
        _orchardSubtreeIndex,
        _journal[MerkleApi.orchard]?.base ?? 0,
      );
      _ironwoodSubtreeIndex = _maxIndex(
        _ironwoodSubtreeIndex,
        _journal[MerkleApi.ironwood]?.base ?? 0,
      );
      // Strict sizes for every pool: unrestored pools sit at zero, so a
      // first feed with a non-zero start fails loudly instead of
      // appending at the wrong absolute position.
      for (final kind in const [
        MerkleApi.sapling,
        MerkleApi.orchard,
        MerkleApi.ironwood,
      ]) {
        _nativeSizes.putIfAbsent(kind, () => _journal[kind]?.tipSize ?? 0);
      }
      _mirrorReady = true;
    } catch (_) {
      await _closeContextSilent();
      rethrow;
    }
  }

  Future<void> _closeContextSilent() async {
    final id = _contextId;
    _contextId = null;
    _nativeCheckpoints.clear();
    _nativeSizes.clear();
    if (id != null) {
      try {
        _call('closeContext', () => _merkle.closeContext(id));
      } catch (_) {}
    }
  }

  Future<void> _restorePool(int contextId, int kind) async {
    final j = _journal[kind];
    if (j == null || (j.isEmpty && j.base == 0)) return;
    if (j.base % _subtreeSpan != 0) {
      throw ZcashErrors.merkleBuilderFailed(
        "restoreMirror",
        reason: "Journal base ${j.base} is not subtree-aligned.",
      );
    }
    if (j.leaves.length % 32 != 0) {
      throw ZcashErrors.merkleBuilderFailed(
        "restoreMirror",
        reason: "Journal leaves are not 32-byte aligned.",
      );
    }
    final completed = j.base ~/ _subtreeSpan;
    // No network when nothing was ever absorbed (fresh wallets restore
    // fully offline).
    final roots =
        completed == 0
            ? <List<int>>[]
            : (await _fetchSubtreeRoots(
              kind: kind,
              startIndex: 0,
            )).take(completed).toList();
    if (roots.length != completed) {
      throw ZcashErrors.merkleBuilderFailed(
        "restoreMirror",
        reason:
            "Subtree history incomplete (want $completed, got ${roots.length}).",
      );
    }
    for (var i = 0; i < roots.length; i++) {
      _call(
        'restoreAbsorb',
        () => _merkle.updateSubtree(
          contextId,
          kind: kind,
          start: i * _subtreeSpan,
          root32: BuBytes(roots[i]),
        ),
      );
    }
    _nativeSizes[kind] = j.base;
  }

  Future<void> _replayJournal(int contextId) async {
    const kinds = [MerkleApi.sapling, MerkleApi.orchard, MerkleApi.ironwood];
    // Union of checkpoint ids usable by at least one pool.
    final ids = <int>{};
    for (final kind in kinds) {
      final j = _journal[kind];
      if (j == null) continue;
      final tip = j.base + j.leaves.length ~/ 32;
      for (final e in j.checkpoints.entries) {
        if (e.value > j.base && e.value <= tip) ids.add(e.key);
      }
    }
    final ordered = ids.toList()..sort();
    // Absolute positions appended so far, per pool (start at absorb base).
    final done = <int, int>{
      for (final kind in kinds) kind: _journal[kind]?.base ?? 0,
    };
    for (final id in ordered) {
      for (final kind in kinds) {
        final j = _journal[kind];
        if (j == null) continue;
        final size = j.checkpoints[id];
        if (size == null) continue;
        final tip = j.base + j.leaves.length ~/ 32;
        if (size <= j.base || size > tip) continue;
        final want = size - done[kind]!;
        if (want > 0) {
          final from = done[kind]! - j.base;
          _call(
            'restoreAppend',
            () => _merkle.updateState(
              contextId,
              kind: kind,
              leaves: j.leaves.sublist(from * 32, (from + want) * 32),
            ),
          );
          done[kind] = done[kind]! + want;
        }
      }
      _call('restoreCheckpoint', () => _merkle.checkpoint(contextId, id));
      _nativeCheckpoints.add(id);
    }
    for (final kind in kinds) {
      // Native sizes match journal tips exactly (last checkpoint per pool
      // sits at its tip: every fed block is journaled).
      final j = _journal[kind];
      _nativeSizes[kind] = j == null ? 0 : j.base + j.leaves.length ~/ 32;
    }
  }

  static const int _subtreeSpan = 65536;

  /// Last absorbed subtree index covered by [absorbBase], or -1 when none.
  /// Live-fetch indices never move backwards.
  static int _maxIndex(int stored, int absorbBase) {
    if (absorbBase <= 0) return stored;
    final covered = absorbBase ~/ _subtreeSpan - 1;
    return covered > stored ? covered : stored;
  }

  @override
  Future<void> initSubtreeRoot({
    required int finalSaplingTree,
    required int finalOrchardTree,
    int? finalIronwoodTree,
  }) async {
    await _lock.run(() async {
      await _ensureReady();
      await _initSubtreeRootsLocked(
        finalSaplingTree: finalSaplingTree,
        finalOrchardTree: finalOrchardTree,
        finalIronwoodTree: finalIronwoodTree,
      );
    });
  }

  /// Absorb newly completed subtrees. Caller must hold [_lock] on a ready
  /// mirror.
  Future<void> _initSubtreeRootsLocked({
    required int finalSaplingTree,
    required int finalOrchardTree,
    int? finalIronwoodTree,
  }) async {
    final cSapIndex = _saplingSubtreeIndex;
    final cOrchardIndex = _orchardSubtreeIndex;
    int index = finalSaplingTree ~/ BinaryOps.mask16;
    if (index > cSapIndex) {
      _saplingSubtreeIndex = await _updateSubtreeRootes(
        startIndex: cSapIndex + 1,
        protocol: ZcashProtocol.sapling,
      );
    }
    index = finalOrchardTree ~/ BinaryOps.mask16;
    if (index > cOrchardIndex) {
      _orchardSubtreeIndex = await _updateSubtreeRootes(
        startIndex: cOrchardIndex + 1,
        protocol: ZcashProtocol.orchard,
      );
    }
    if (finalIronwoodTree != null) {
      index = finalIronwoodTree ~/ BinaryOps.mask16;
      if (index > _ironwoodSubtreeIndex) {
        _ironwoodSubtreeIndex = await _updateIronwoodSubtreeRoots(
          startIndex: _ironwoodSubtreeIndex + 1,
        );
      }
    }
  }

  Future<int> _currentHeight() async {
    final blockId = await provider.request(
      ZcashGrpcRequestMessage(request: ZWalletdGetLatestBlock()),
    );
    return blockId.getHeight();
  }

  @override
  FutureOr<BuildMerleOutput> buildMerkle({
    int? targetHeight,
    List<SaplingScannedOutput> saplingOutputs = const [],
    List<OrchardScannedOutput> orchardOutputs = const [],
    List<OrchardScannedOutput> ironwoodOutputs = const [],
  }) async {
    if (saplingOutputs.isEmpty &&
        orchardOutputs.isEmpty &&
        ironwoodOutputs.isEmpty) {
      return BuildMerleOutput.empty();
    }
    final ready = await _lock.run(() async {
      await _ensureReady();
      return _contextId ?? await _getOrCreateContext();
    });
    final contextId = ready;
    bool hasSapling = saplingOutputs.isNotEmpty;
    bool hasOrchard = orchardOutputs.isNotEmpty;
    bool hasIronwood = ironwoodOutputs.isNotEmpty;

    saplingOutputs =
        saplingOutputs.clone()..sort(
          (a, b) => a.noteCommitmentTreePosition.position.compareTo(
            b.noteCommitmentTreePosition.position,
          ),
        );
    orchardOutputs =
        orchardOutputs.clone()..sort(
          (a, b) => a.noteCommitmentTreePosition.position.compareTo(
            b.noteCommitmentTreePosition.position,
          ),
        );
    ironwoodOutputs =
        ironwoodOutputs.clone()..sort(
          (a, b) => a.noteCommitmentTreePosition.position.compareTo(
            b.noteCommitmentTreePosition.position,
          ),
        );
    final height = targetHeight ?? await _currentHeight();
    final anchorHeight = _anchorHeight(height);
    ({
      OrchardMerkleHash? root,
      List<OrchardMerklePath> paths,
      OrchardAnchor anchor,
    })
    orchardWitnesses = await switch (hasOrchard) {
      true => () async {
        final result =
            await _buildWitnessPaths<OrchardMerkleHash, OrchardMerklePath>(
              fromBytes: OrchardMerkleHash.fromBytes,
              createPath:
                  (paths, position) =>
                      OrchardMerklePath(position: position, authPath: paths),
              kind: MerkleApi.orchard,
              contextId: contextId,
              anchorHeight: anchorHeight,
              possitions:
                  orchardOutputs
                      .map((e) => e.noteCommitmentTreePosition.position)
                      .toList(),
            );
        return (
          anchor: result.root.toAnchor(),
          root: result.root,
          paths: result.paths,
        );
      }(),
      _ => (
        anchor: OrchardAnchor.emptyTree(),
        root: null,
        paths: <OrchardMerklePath>[],
      ),
    };
    ({SaplingNode? root, List<SaplingMerklePath> paths, SaplingAnchor anchor})
    saplingWitnesses = await switch (hasSapling) {
      true => () async {
        final result = await _buildWitnessPaths<SaplingNode, SaplingMerklePath>(
          fromBytes: SaplingNode.fromBytes,
          createPath:
              (paths, position) =>
                  SaplingMerklePath(position: position, authPath: paths),
          kind: MerkleApi.sapling,
          contextId: contextId,
          anchorHeight: anchorHeight,
          possitions:
              saplingOutputs
                  .map((e) => e.noteCommitmentTreePosition.position)
                  .toList(),
        );
        return (
          anchor: result.root.toAnchor(),
          root: result.root,
          paths: result.paths,
        );
      }(),
      _ => (
        anchor: SaplingAnchor.emptyTree(),
        root: null,
        paths: <SaplingMerklePath>[],
      ),
    };
    ({
      OrchardMerkleHash? root,
      List<OrchardMerklePath> paths,
      OrchardAnchor anchor,
    })
    ironwoodWitnesses = await switch (hasIronwood) {
      true => () async {
        final result =
            await _buildWitnessPaths<OrchardMerkleHash, OrchardMerklePath>(
              fromBytes: OrchardMerkleHash.fromBytes,
              createPath:
                  (paths, position) =>
                      OrchardMerklePath(position: position, authPath: paths),
              kind: MerkleApi.ironwood,
              contextId: contextId,
              anchorHeight: anchorHeight,
              possitions:
                  ironwoodOutputs
                      .map((e) => e.noteCommitmentTreePosition.position)
                      .toList(),
            );
        return (
          anchor: result.root.toAnchor(),
          root: result.root,
          paths: result.paths,
        );
      }(),
      _ => (
        anchor: OrchardAnchor.emptyTree(),
        root: null,
        paths: <OrchardMerklePath>[],
      ),
    };
    final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
    oNotes = [];
    final List<ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
    sNotes = [];
    final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
    iNotes = [];
    for (final oIndexed in saplingOutputs.indexed) {
      final output = oIndexed.$2;
      final witness = saplingWitnesses.paths.elementAt(oIndexed.$1);
      final root = saplingWitnesses.root;
      if (root == null) {
        throw ZcashErrors.merkleBuilderFailed(
          "buildMerkle",
          reason: "Missing sapling witness.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
      if (root.inner !=
          witness
              .root(
                SaplingNode.fromCmu(output.note.cmu(context)),
                context.saplingHashable(),
              )
              .inner) {
        throw ZcashErrors.merkleBuilderFailed(
          "buildMerkle",
          reason: "Sapling anchor mismatch.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
      sNotes.add(ScannedOutputWithMerkle(output: output, merklePath: witness));
    }

    for (final oIndexed in orchardOutputs.indexed) {
      final output = oIndexed.$2;
      final witness = orchardWitnesses.paths.elementAt(oIndexed.$1);
      final root = orchardWitnesses.root;
      if (root == null) {
        throw ZcashErrors.merkleBuilderFailed(
          "buildMerkle",
          reason: "Missing Orchard witness.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
      if (root.inner !=
          witness
              .root(
                cmx:
                    output.note.commitment(context).toExtractedNoteCommitment(),
                hashContext: context.orchardHashable(),
              )
              .inner) {
        throw ZcashErrors.merkleBuilderFailed(
          "buildMerkle",
          reason: "Orchard anchor mismatch.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
      oNotes.add(ScannedOutputWithMerkle(output: output, merklePath: witness));
    }

    for (final oIndexed in ironwoodOutputs.indexed) {
      final output = oIndexed.$2;
      final witness = ironwoodWitnesses.paths.elementAt(oIndexed.$1);
      final root = ironwoodWitnesses.root;
      if (root == null) {
        throw ZcashErrors.merkleBuilderFailed(
          "buildMerkle",
          reason: "Missing Ironwood witness.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
      if (root.inner !=
          witness
              .root(
                cmx:
                    output.note.commitment(context).toExtractedNoteCommitment(),
                hashContext: context.orchardHashable(),
              )
              .inner) {
        throw ZcashErrors.merkleBuilderFailed(
          "buildMerkle",
          reason: "Ironwood anchor mismatch.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
      iNotes.add(ScannedOutputWithMerkle(output: output, merklePath: witness));
    }

    return BuildMerleOutput(
      orchardNotes: oNotes,
      saplingNotes: sNotes,
      ironwoodNotes: iNotes,
      orchardAnchor: orchardWitnesses.anchor,
      saplingAnchor: saplingWitnesses.anchor,
      ironwoodAnchor: ironwoodWitnesses.anchor,
    );
  }

  /// Newest checkpoint at or below [height] across all pools. Checkpoint
  /// ids are block heights, recorded for every pool on every fed block.
  int _anchorHeight(int height) {
    int? anchor;
    for (final j in _journal.values) {
      for (final id in j.checkpoints.keys) {
        if (id <= height && (anchor == null || id > anchor)) anchor = id;
      }
    }
    if (anchor == null) {
      throw ZcashErrors.merkleBuilderFailed(
        "buildMerkle",
        reason: "No valid checkpoint was found.",
      );
    }
    if (!_nativeCheckpoints.contains(anchor)) {
      throw ZcashErrors.merkleBuilderFailed(
        "buildMerkle",
        reason:
            "Checkpoint $anchor is not available in the native mirror "
            "(evicted or never snapshotted).",
      );
    }
    return anchor;
  }

  Future<({List<E> paths, H root})>
  _buildWitnessPaths<H extends MerkleNodeValue, E extends MerklePath<H>>({
    required H Function(List<int> bytes) fromBytes,
    required E Function(List<H> paths, LeafPosition position) createPath,
    required int kind,
    required int contextId,
    required int anchorHeight,
    required List<int> possitions,
  }) async {
    final witness = _call(
      'createWitness',
      () => _merkle.createWitness(
        contextId,
        kind: kind,
        checkpointId: anchorHeight,
        positions: possitions,
      ),
    );
    final root = fromBytes(witness.anchor);
    if (witness.paths.length != possitions.length) {
      throw ZcashErrors.merkleBuilderFailed(
        "buildMerkle",
        reason:
            "Mismatch between requested positions and returned merkle paths.",
      );
    }
    final merkles =
        witness.paths
            .map(
              (e) => createPath(
                _chunks32(e.limbs).map(fromBytes).toList(),
                LeafPosition(e.position),
              ),
            )
            .toList();
    return (root: root, paths: merkles);
  }

  static List<List<int>> _chunks32(List<int> bytes) {
    if (bytes.length % 32 != 0) {
      throw ZcashErrors.merkleBuilderFailed(
        "buildMerkle",
        reason: "Bad witness blob length ${bytes.length}.",
      );
    }
    return [
      for (var i = 0; i < bytes.length; i += 32) bytes.sublist(i, i + 32),
    ];
  }

  @override
  Future<List<int>> serialize() async {
    return _lock.run(() async {
      final journal = _exportJournal();
      return NativeMerkleState(
        journal: journal,
        saplingSubtreeIndex: _saplingSubtreeIndex,
        orchardSubtreeIndex: _orchardSubtreeIndex,
        ironwoodSubtreeIndex: _ironwoodSubtreeIndex,
      ).toCbor().encode();
    });
  }

  @override
  Future<NativeMerkleInsertReport?> updateState(
    List<ScannedBlock> scannedBlocks, {
    bool continually = false,
  }) async {
    if (scannedBlocks.isEmpty) return null;
    final blocks = switch (continually) {
      true => scannedBlocks,
      false =>
        scannedBlocks.clone()..sort((a, b) => a.blockId.compareTo(b.blockId)),
    };
    return _lock.run(() async {
      await _ensureReady();
      await _initSubtreeRootsLocked(
        finalSaplingTree: blocks.last.bundles.sapling.finalTreeSize,
        finalOrchardTree: blocks.last.bundles.orchard.finalTreeSize,
        finalIronwoodTree: blocks.last.bundles.ironwood.finalTreeSize,
      );
      try {
        for (final block in blocks) {
          await _feedBlock(block);
        }
      } catch (_) {
        // Fail-closed on any feed error: the journal and the native
        // mirror stay consistent at the last fully applied block (both
        // advance in lockstep per block), and the error propagates. The
        // caller retries with the same batch; the already-applied prefix
        // is skipped as byte-identical overlap.
        await _closeContextSilent();
        _mirrorReady = false;
        rethrow;
      }
      return NativeMerkleInsertReport(
        height: blocks.first.blockId,
        lastHeight: blocks.last.blockId,
        finalSaplingTree: blocks.last.bundles.sapling.finalTreeSize,
        finalOrchardTree: blocks.last.bundles.orchard.finalTreeSize,
        finalIronwoodTree: blocks.last.bundles.ironwood.finalTreeSize,
      );
    });
  }

  /// Feed one scanned block: per-pool contiguity gate (fail-closed, with
  /// byte-identical overlap skipped), native append, then checkpoint.
  /// Caller must hold [_lock] on a ready mirror.
  Future<void> _feedBlock(ScannedBlock block) async {
    final lastFed = _lastFedBlock;
    if (lastFed != null) {
      if (block.blockId > lastFed + 1) {
        throw ZcashErrors.merkleBuilderFailed(
          "updateState",
          reason:
              "Non-contiguous scan: block ${block.blockId} follows "
              "fed block $lastFed (missing blocks in between).",
          details: {"diverged": "true"},
        );
      }
    }
    var contextId = _contextId ?? await _getOrCreateContext();
    _feedPool(contextId, MerkleApi.sapling, block.bundles.sapling, 'sapling');
    _feedPool(contextId, MerkleApi.orchard, block.bundles.orchard, 'orchard');
    _feedPool(
      contextId,
      MerkleApi.ironwood,
      block.bundles.ironwood,
      'ironwood',
    );
    // Checkpoint every scanned block under its height, mirroring the
    // per-block checkpoint model (all pools share checkpoint ids).
    _call('checkpoint', () => _merkle.checkpoint(contextId, block.blockId));
    _nativeCheckpoints.add(block.blockId);
    _journalRecordCheckpoint(block.blockId);
  }

  /// Append one pool's bundle commitments, preserving order. Byte-identical
  /// overlap with already-fed leaves is skipped; anything else that is not
  /// exactly contiguous throws fail-closed.
  void _feedPool<N extends MerkleNodeValue>(
    int contextId,
    int kind,
    ScannedProtocolBundles<N> bundles,
    String pool,
  ) {
    final nodes = bundles.commitments.map((e) => e.node).toList();
    final tip = _nativeSizes[kind];
    if (tip == null) {
      throw ZcashErrors.merkleBuilderFailed(
        "updateState",
        reason: "Native $pool mirror has no tracked size.",
      );
    }
    if (nodes.isEmpty) return;
    final start = bundles.finalTreeSize - nodes.length;
    final all = _leavesBytes(nodes, pool);
    List<int> fresh = all;
    if (start == tip) {
      // Exact continuation: append everything.
    } else if (start < tip) {
      // Historical range: the overlapping part must be byte-identical to
      // what was fed before, otherwise the scan diverged.
      final overlap = tip - start;
      if (overlap >= nodes.length) {
        // Entirely covered by previous feeds: verify everything, skip.
        _verifyOverlap(kind, start, all, pool);
        return;
      }
      _verifyOverlap(kind, start, all.sublist(0, overlap * 32), pool);
      fresh = all.sublist(overlap * 32);
    } else {
      throw ZcashErrors.merkleBuilderFailed(
        "updateState",
        reason:
            "Native $pool mirror diverged (tip $tip, batch starts at "
            "$start).",
        details: {"diverged": "true"},
      );
    }
    _call(
      'updateState',
      () => _merkle.updateState(contextId, kind: kind, leaves: fresh),
    );
    final skipped = nodes.length - fresh.length ~/ 32;
    _nativeSizes[kind] = tip + fresh.length ~/ 32;
    _journalAppend(
      kind: kind,
      start: start + skipped,
      leaves: fresh,
      pool: pool,
    );
  }

  static List<int> _leavesBytes(List<MerkleNodeValue> nodes, String pool) {
    final leaves = <int>[];
    for (final n in nodes) {
      final b = n.toBytes();
      if (b.length != 32) {
        throw ZcashErrors.merkleBuilderFailed(
          "updateState",
          reason: "Bad $pool leaf length ${b.length}, want 32.",
        );
      }
      leaves.addAll(b);
    }
    return leaves;
  }

  /// Verify that [bytes] (covering `[start, start + bytes.length ~/ 32)`)
  /// match the journaled leaves exactly. Throws on divergence or when the
  /// range is not journaled (e.g. sits inside absorbed history).
  void _verifyOverlap(int kind, int start, List<int> bytes, String pool) {
    if (bytes.isEmpty) return;
    final j = _poolJournal(kind);
    if (start < j.base ||
        start + bytes.length ~/ 32 > j.base + j.leaves.length ~/ 32) {
      throw ZcashErrors.merkleBuilderFailed(
        "updateState",
        reason:
            "Native $pool mirror diverged (re-fed range [$start, ...) is "
            "not journaled).",
        details: {"diverged": "true"},
      );
    }
    final off = (start - j.base) * 32;
    for (var i = 0; i < bytes.length; i++) {
      if (j.leaves[off + i] != bytes[i]) {
        throw ZcashErrors.merkleBuilderFailed(
          "updateState",
          reason:
              "Native $pool mirror diverged (re-fed leaves differ at "
              "position ${start + i ~/ 32}).",
          details: {"diverged": "true"},
        );
      }
    }
  }

  /// Append freshly fed leaves to the journal at absolute [start].
  /// The journal must continue exactly where it left off; callers pass the
  /// skipped-overlap offset through [start].
  void _journalAppend({
    required int kind,
    required int start,
    required List<int> leaves,
    required String pool,
  }) {
    if (leaves.isEmpty) return;
    final j = _poolJournal(kind);
    if (start != j.base + j.leaves.length ~/ 32) {
      throw ZcashErrors.merkleBuilderFailed(
        "updateState",
        reason:
            "Journal diverged (base ${j.base}, len ${j.leaves.length ~/ 32}, "
            "batch starts at $start).",
        details: {"diverged": "true"},
      );
    }
    j.leaves.addAll(leaves);
  }

  void _journalRecordCheckpoint(int id) {
    for (final kind in const [
      MerkleApi.sapling,
      MerkleApi.orchard,
      MerkleApi.ironwood,
    ]) {
      final tip = _nativeSizes[kind];
      if (tip != null) _poolJournal(kind).checkpoints[id] = tip;
    }
  }

  /// Shared absorb path: native absorb + journal truncation stay in
  /// lockstep so the journal always covers exactly [absorbBase, tip).
  void _absorbNativeSubtree({
    required int contextId,
    required int kind,
    required int start,
    required List<int> root,
  }) {
    if (root.length != 32) {
      throw ZcashErrors.merkleBuilderFailed(
        "absorbSubtree",
        reason: "Bad subtree root length ${root.length}, want 32.",
      );
    }
    _call(
      'updateSubtree',
      () => _merkle.updateSubtree(
        contextId,
        kind: kind,
        start: start,
        root32: BuBytes(root),
      ),
    );
    final j = _poolJournal(kind);
    final newBase = start + _subtreeSpan;
    if (newBase < j.base) {
      throw ZcashErrors.merkleBuilderFailed(
        "absorbSubtree",
        reason: "Absorb moved base backwards (${j.base} -> $newBase).",
      );
    }
    final drop = newBase - j.base;
    final dropBytes = drop * 32;
    if (dropBytes > j.leaves.length) {
      throw ZcashErrors.merkleBuilderFailed(
        "absorbSubtree",
        reason: "Absorb beyond journaled tip (base ${j.base}, drop $drop).",
      );
    }
    j.leaves.removeRange(0, dropBytes);
    j.base = newBase;
    _nativeSizes[kind] = newBase;
    // Checkpoints at or below the new base live inside absorbed history
    // (unwitnessable natively by design); drop them from the journal so
    // restore replays only usable snapshots.
    j.checkpoints.removeWhere((_, size) => size <= newBase);
  }

  Future<List<List<int>>> _fetchSubtreeRoots({
    required int kind,
    required int startIndex,
  }) async {
    if (kind == MerkleApi.ironwood) {
      final subtrees = await provider.requestOnceAsync(
        ZcashGrpcRequestMessage(
          request: ZWalletdGetSubtreeRoots(
            getSubtreeRoots: ZWalletdGetSubtreeRootsArg(
              startIndex: startIndex,
              shieldedProtocol: ZWalletdShieldedProtocol.ironwood,
            ),
          ),
        ),
      );
      return subtrees.map((s) => List<int>.from(s.getRootHashes())).toList();
    }
    final protocol =
        kind == MerkleApi.sapling
            ? ZcashProtocol.sapling
            : ZcashProtocol.orchard;
    final subtrees = await provider.requestOnceAsync(
      ZcashGrpcRequestMessage(
        request: ZWalletdGetSubtreeRoots(
          getSubtreeRoots: ZWalletdGetSubtreeRootsArg(
            startIndex: startIndex,
            shieldedProtocol: protocol.toShieldedProtocol(),
          ),
        ),
      ),
    );
    if (kind == MerkleApi.orchard) {
      final latest = subtrees.lastOrNull?.completingBlockHeight;
      if (subtrees.isNotEmpty && latest == null) {
        throw ZcashErrors.merkleBuilderFailed(
          "updateSubtreeRoots",
          reason: "Unexcpected service response. Invalid subtree block height.",
        );
      }
    }
    return subtrees.map((s) => List<int>.from(s.getRootHashes())).toList();
  }

  /// Ironwood subtree-root absorption. Unlike [_updateSubtreeRootes] this
  /// uses the lightwalletd ironwood protocol directly (`ZcashProtocol` has
  /// no ironwood variant; the tree itself is Orchard-typed).
  Future<int> _updateIronwoodSubtreeRoots({required int startIndex}) async {
    final roots = await _fetchSubtreeRoots(
      kind: MerkleApi.ironwood,
      startIndex: startIndex,
    );
    final contextId = await _getOrCreateContext();
    var index = startIndex;
    for (final root in roots) {
      if (root.length != 32) {
        throw ZcashErrors.merkleBuilderFailed(
          "initSubtreeRoot",
          reason: "Bad ironwood subtree root length ${root.length}, want 32.",
        );
      }
      _absorbNativeSubtree(
        contextId: contextId,
        kind: MerkleApi.ironwood,
        start: index * _subtreeSpan,
        root: root,
      );
      index++;
    }
    return index - 1;
  }

  Future<int> _updateSubtreeRootes({
    required int startIndex,
    required ZcashProtocol protocol,
  }) async {
    final roots = await _fetchSubtreeRoots(
      kind: _buKind(protocol),
      startIndex: startIndex,
    );
    final contextId = await _getOrCreateContext();
    final kind = _buKind(protocol);
    var index = startIndex;
    for (final root in roots) {
      if (root.length != 32) {
        throw ZcashErrors.merkleBuilderFailed(
          "initSubtreeRoot",
          reason: "Bad subtree root length ${root.length}, want 32.",
        );
      }
      _absorbNativeSubtree(
        contextId: contextId,
        kind: kind,
        start: index * _subtreeSpan,
        root: root,
      );
      index++;
    }
    return index - 1;
  }
}

/// In-memory tip journal for one native pool: contiguous leaves plus the
/// checkpoints snapshotted while they were maintained.
class _PoolJournal {
  int base = 0;
  final List<int> leaves;
  final Map<int, int> checkpoints;
  _PoolJournal({List<int>? leaves, Map<int, int>? checkpoints})
    : leaves = leaves ?? [],
      checkpoints = checkpoints ?? {};

  bool get isEmpty => leaves.isEmpty && checkpoints.isEmpty && base == 0;

  /// Tree size at the journal tip.
  int get tipSize => base + leaves.length ~/ 32;

  void restore({
    required int base,
    required List<int> leaves,
    required Map<int, int> checkpoints,
  }) {
    if (base < 0 || leaves.length % 32 != 0) {
      throw ZcashErrors.merkleBuilderFailed(
        "restoreJournal",
        reason: "Bad journal (base $base, leaves ${leaves.length}).",
      );
    }
    for (final e in checkpoints.entries) {
      if (e.key < 0 || e.value < 0) {
        throw ZcashErrors.merkleBuilderFailed(
          "restoreJournal",
          reason: "Bad journal checkpoint ${e.key} -> ${e.value}.",
        );
      }
    }
    this.base = base;
    this.leaves
      ..clear()
      ..addAll(leaves);
    this.checkpoints
      ..clear()
      ..addAll(checkpoints);
  }
}
