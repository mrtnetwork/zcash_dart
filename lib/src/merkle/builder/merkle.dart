import 'dart:async';
import 'dart:collection';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/builder/types.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/provider.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';

abstract class MerkleBuilder {
  int? saplingMaxCheckpointHeigt(int height);
  int? orchardMaxCheckpointHeight(int height);
  OrchardShardTree getOrcardShardTree();
  SaplingShardTree getSaplingShardTree();
  List<int> serializeSaplingTree();
  List<int> serializeOrchardTree();
  FutureOr<void> updateState(List<ScannedBlock> scannedBlocks);
  Future<void> initSubtreeRoot();
  FutureOr<BuildMerleOutput> buildMerkle({
    int? targetHeight,
    List<SaplingScannedOutput> saplingOutputs = const [],
    List<OrchardScannedOutput> orchardOutputs = const [],
  });
}

class DefaultMerkleBuilder implements MerkleBuilder {
  final ZCashCryptoContext context;
  final ZCashWalletdProvider provider;
  final OrchardShardTree _orchardTree;
  final SaplingShardTree _saplingTree;
  final TreeLevel shardHeight = TreeLevel(NoteEncryptionConst.shardHeight);
  final _lock = SafeAtomicLock();
  bool _saplingUpdated = false;
  bool _orchardUpdated = false;
  ChainState? _chainState;

  DefaultMerkleBuilder({
    required this.context,
    required this.provider,
    OrchardShardTree? orchardTree,
    SaplingShardTree? saplingTree,
  }) : _orchardTree =
           orchardTree ??
           OrchardShardTree(OrchardShardStore(context.orchardHashable())),
       _saplingTree =
           saplingTree ??
           SaplingShardTree(SaplingShardStore(context.saplingHashable()));

  @override
  Future<void> initSubtreeRoot() async {
    if (_saplingUpdated && _orchardUpdated) return;
    await _lock.run(() async {
      if (!_saplingUpdated) {
        await _updateSaplingSubtreeRoots();
        _saplingUpdated = true;
      }
      if (!_orchardUpdated) {
        await _updateOrchardSubtreeRoots();
        _orchardUpdated = true;
      }
    });
  }

  @override
  Future<void> updateState(List<ScannedBlock> scannedBlocks) async {
    await initSubtreeRoot();
    await _lock.run(() async {
      if (scannedBlocks.isEmpty) return;
      scannedBlocks =
          scannedBlocks.clone()..sort((a, b) => a.blockId.compareTo(b.blockId));
      final chainState = await _updateeChainState(
        block: scannedBlocks.first.blockId - 1,
      );
      final startOrchard = LeafPosition(
        scannedBlocks.first.orchard.finalTreeSize -
            scannedBlocks.first.orchard.commitments.length,
      );
      final startSapling = LeafPosition(
        scannedBlocks.first.sapling.finalTreeSize -
            scannedBlocks.first.sapling.commitments.length,
      );
      final endOrchard = LeafPosition(scannedBlocks.last.orchard.finalTreeSize);
      final endSapling = LeafPosition(scannedBlocks.last.sapling.finalTreeSize);
      final saplingCommitments =
          scannedBlocks.expand((e) => e.sapling.commitments).toList();
      final orchardCommitments =
          scannedBlocks.expand((e) => e.orchard.commitments).toList();

      final orchardSubtree = LocatedPrunableTree.fromIter<
        int,
        OrchardMerkleHash
      >(
        positionRange: LeafPositionRange(start: startOrchard, end: endOrchard),
        pruneLevel: shardHeight,
        hashContext: _orchardTree.hashContext,
        values: orchardCommitments.map((e) => (e.node, e.retention)).iterator,
      );
      if (orchardSubtree != null) {
        _orchardTree.insertTree(
          orchardSubtree.subtree,
          orchardSubtree.checkpoints,
        );
      }
      final saplingSubtree = LocatedPrunableTree.fromIter<int, SaplingNode>(
        positionRange: LeafPositionRange(start: startSapling, end: endSapling),
        pruneLevel: shardHeight,
        hashContext: _saplingTree.hashContext,
        values: saplingCommitments.map((e) => (e.node, e.retention)).iterator,
      );
      if (saplingSubtree != null) {
        _saplingTree.insertTree(
          saplingSubtree.subtree,
          saplingSubtree.checkpoints,
        );
      }

      final saplingMissing = _ensureCheckpoints(
        orchardSubtree?.checkpoints.keys.toList() ?? [],
        saplingSubtree?.checkpoints,
        chainState.finalSaplingTree,
      );
      final orchardMissing = _ensureCheckpoints(
        saplingSubtree?.checkpoints.keys.toList() ?? [],
        orchardSubtree?.checkpoints,
        chainState.finalOrchardTree,
      );

      final minSaplingHeight = _saplingTree.store.maxCheckpointId() ?? 0;
      for (final i in saplingMissing) {
        if (i.key > minSaplingHeight) {
          _saplingTree.store.addCheckpoint(i.key, i.value);
        }
      }
      final minOrchardHeigt = _orchardTree.store.maxCheckpointId() ?? 0;
      for (final i in orchardMissing) {
        if (i.key > minOrchardHeigt) {
          _orchardTree.store.addCheckpoint(i.key, i.value);
        }
      }
    });
  }

  @override
  Future<BuildMerleOutput> buildMerkle({
    int? targetHeight,
    List<SaplingScannedOutput> saplingOutputs = const [],
    List<OrchardScannedOutput> orchardOutputs = const [],
  }) async {
    if (saplingOutputs.isEmpty && orchardOutputs.isEmpty) {
      throw MerkleTreeException.failed(
        "buildMerkle",
        reason: "At least one spend required.",
      );
    }
    bool hasSapling = saplingOutputs.isNotEmpty;
    bool hasOrchard = orchardOutputs.isNotEmpty;
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
    final height = targetHeight ?? await _currentHeight();
    final saplingNote = saplingMaxCheckpointHeigt(height);
    final orchardNote = orchardMaxCheckpointHeight(height);
    int anchorHeight = () {
      if (saplingNote != null && orchardNote != null) {
        return IntUtils.min(saplingNote, orchardNote);
      }
      return saplingNote ?? orchardNote!;
    }();
    final oRoot = _orchardTree.rootAtCheckpointId(anchorHeight);
    final sRoot = _saplingTree.rootAtCheckpointId(anchorHeight);
    final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
    oNotes = [];
    final List<ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
    sNotes = [];
    if (hasOrchard && oRoot == null) {
      throw MerkleTreeException.failed(
        "buildMerkle",
        reason: "Missing orchard checkpoint",
      );
    }
    if (hasSapling && sRoot == null) {
      throw MerkleTreeException.failed(
        "buildMerkle",
        reason: "Missing sapling checkpoint",
      );
    }

    for (final output in orchardOutputs) {
      final oMerkle = _orchardTree.witnessAtCheckpointIdCaching(
        position: output.noteCommitmentTreePosition,
        checkpointId: anchorHeight,
      );
      if (oMerkle == null) {
        throw MerkleTreeException.failed(
          "buildMerkle",
          reason: "Mising orchard checkpoint",
        );
      }
      if (oRoot?.inner !=
          oMerkle
              .root(
                cmx:
                    output.note.commitment(context).toExtractedNoteCommitment(),
                hashContext: context.orchardHashable(),
              )
              .inner) {
        throw MerkleTreeException.failed(
          "buildMerkle",
          reason: "Orchard anchor mismatch.",
          details: {
            "position": output.noteCommitmentTreePosition.position,
            "height": anchorHeight,
          },
        );
      }
      oNotes.add(ScannedOutputWithMerkle(output: output, merklePath: oMerkle));
    }
    for (final output in saplingOutputs) {
      final sMerkle = _saplingTree.witnessAtCheckpointIdCaching(
        position: output.noteCommitmentTreePosition,
        checkpointId: anchorHeight,
      );
      if (sMerkle == null) {
        throw MerkleTreeException.failed(
          "buildMerkle",
          reason: "Mising sapling checkpoint",
        );
      }
      if (sRoot?.inner !=
          sMerkle
              .root(
                SaplingNode.fromCmu(output.note.cmu(context)),
                context.saplingHashable(),
              )
              .inner) {
        throw MerkleTreeException.failed(
          "buildMerkle",
          reason: "Sapling anchor mismatch.",
          details: {
            "position": output.noteCommitmentTreePosition.position,
            "height": anchorHeight,
          },
        );
      }
      // assert();
      sNotes.add(ScannedOutputWithMerkle(output: output, merklePath: sMerkle));
    }

    return BuildMerleOutput(
      orchardNotes: oNotes,
      saplingNotes: sNotes,
      orchardAnchor: oRoot?.toAnchor() ?? OrchardAnchor.emptyTree(),
      saplingAnchor: sRoot?.toAnchor() ?? SaplingAnchor.emptyTree(),
    );
  }

  @override
  int? saplingMaxCheckpointHeigt(int height) {
    final int maxCheckpoint = height - 1;
    for (int i = maxCheckpoint; i > 0; i--) {
      final checkpoint = _saplingTree.store.getCheckpoint(i);
      if (checkpoint != null) return i;
    }
    return null;
  }

  // ignore: annotate_overrides
  int? orchardMaxCheckpointHeight(int height) {
    final int maxCheckpoint = height - 1;
    for (int i = maxCheckpoint; i > 0; i--) {
      final checkpoint = _orchardTree.store.getCheckpoint(i);
      if (checkpoint != null) return i;
    }
    return null;
  }

  @override
  OrchardShardTree getOrcardShardTree() {
    return OrchardShardTree(_orchardTree.store.clone());
  }

  @override
  SaplingShardTree getSaplingShardTree() {
    return SaplingShardTree(_saplingTree.store.clone());
  }

  @override
  List<int> serializeOrchardTree() {
    return _orchardTree.toSerializeBytes();
  }

  @override
  List<int> serializeSaplingTree() {
    return _saplingTree.toSerializeBytes();
  }

  static
  /// Ensures that checkpoints exist for the given heights.
  List<MapEntry<int, Checkpoint>>
  _ensureCheckpoints<H extends LayoutSerializable>(
    Iterable<int> ensureHeights,
    SplayTreeMap<int, LeafPosition>? existingCheckpointPositions,
    Frontier<H> stateFinalTree,
  ) {
    final List<MapEntry<int, Checkpoint>> result = [];

    for (final ensureHeight in ensureHeights) {
      // Find the last checkpoint <= ensureHeight
      final previous =
          existingCheckpointPositions?.entries
              .where((e) => e.key <= ensureHeight)
              .toList() ??
          [];

      final MapEntry<int, LeafPosition>? lastEntry =
          previous.isEmpty ? null : previous.last;

      if (lastEntry == null) {
        final position = stateFinalTree.frontier?.position;
        // No preceding checkpoint: use stateFinalTree
        final checkpoint = switch (position) {
          null => Checkpoint.treeEmpty(),
          _ => Checkpoint.atPosition(position),
        };

        result.add(MapEntry(ensureHeight, checkpoint));
      } else {
        final existingHeight = lastEntry.key;
        final position = lastEntry.value;

        if (existingHeight < ensureHeight) {
          result.add(MapEntry(ensureHeight, Checkpoint.atPosition(position)));
        }
      }
    }

    return result;
  }

  Future<void> _updateSaplingSubtreeRoots() async {
    final sapligSubtree = await provider.requestOnce(
      ZWalletdRequestGetSubtreeRoots(
        GetSubtreeRootsArg.defaultConfig(ShieldedProtocol.sapling),
      ),
    );
    int index = 0;
    for (final i in sapligSubtree) {
      final roothash = i.rootHash;
      if (roothash == null) {
        throw MerkleTreeException.failed(
          "buildMerkle",
          reason: "Unexcpected provider response.",
        );
      }
      _saplingTree.insert(
        value: SaplingNode.fromBytes(roothash),
        rootAddr: NodeAddress(level: shardHeight, index: index++),
      );
    }
  }

  Future<void> _updateOrchardSubtreeRoots() async {
    final orchardSubtree = await provider.requestOnce(
      ZWalletdRequestGetSubtreeRoots(
        GetSubtreeRootsArg.defaultConfig(ShieldedProtocol.orchard),
      ),
    );
    int index = 0;
    for (final i in orchardSubtree) {
      final roothash = i.rootHash;
      if (roothash == null) {
        throw MerkleTreeException.failed(
          "buildMerkle",
          reason: "Unexcpected provider response.",
        );
      }
      _orchardTree.insert(
        value: OrchardMerkleHash.fromBytes(roothash),
        rootAddr: NodeAddress(level: shardHeight, index: index++),
      );
    }
  }

  Future<int> _currentHeight() async {
    final blockId = await provider.request(ZWalletdRequestGetLatestBlock());
    final height = blockId.height;
    if (height == null) {
      throw MerkleTreeException.failed(
        "currentHeight",
        reason: "Unexcpected provider response. Missing block height.",
      );
    }
    return height;
  }

  Future<ChainState> _getChainState(int block) async {
    final chainStateData =
        _chainState ??=
            (await provider.request(
              ZWalletdRequestGetTreeState(WalletdBlockId(height: block)),
            )).toChainState();
    return chainStateData;
  }

  Future<ChainState> _updateeChainState({int? block}) async {
    ChainState? chainState = _chainState;
    block ??= await _currentHeight();
    if (chainState == null) {
      chainState = await _getChainState(block);
      _orchardTree.insertFrontier(
        chainState.finalOrchardTree,
        RetentionCheckpoint(
          marking: MarkingState.reference,
          id: chainState.blockHeight,
        ),
      );
      _saplingTree.insertFrontier(
        chainState.finalSaplingTree,
        RetentionCheckpoint(
          marking: MarkingState.reference,
          id: chainState.blockHeight,
        ),
      );
    }
    return chainState;
  }
}
