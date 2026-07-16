import 'dart:async';
import 'dart:collection';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/builder/types.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/merkle/tree/shard_tree.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/provider.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';

abstract class MerkleController {
  FutureOr<OrchardShardTree> getOrcardShardTree();
  FutureOr<SaplingShardTree> getSaplingShardTree();

  FutureOr<SerializableMerkleInsertReport?> updateState(
    List<ScannedBlock> scannedBlocks, {
    bool continually = false,
  });
  Future<void> initSubtreeRoot({
    required int finalSaplingTree,
    required int finalOrchardTree,
  });
  Future<void> insertSubtree(SerializableMerkleInsertReport subutree);
  FutureOr<ChainMerkleState> toSerializableChainShardTree();

  FutureOr<BuildMerleOutput> buildMerkle({
    int? targetHeight,
    List<SaplingScannedOutput> saplingOutputs = const [],
    List<OrchardScannedOutput> orchardOutputs = const [],
  });
}

class DefaultMerkleController implements MerkleController {
  final ZcashCryptoContext context;
  final IGrpcProvider<
    IServiceProvider,
    IServiceRequestParams,
    BaseGRPCServiceRequestParams
  >
  provider;
  final OrchardShardTree _orchardTree;
  final SaplingShardTree _saplingTree;
  final TreeLevel shardHeight = TreeLevel(NoteEncryptionConst.shardHeight);
  final _lock = SafeAtomicLock();
  MerkleState? _latestState;
  Hashable<OrchardMerkleHash> get orchardHashable => _orchardTree.hashContext;
  Hashable<SaplingNode> get saplingHashable => _saplingTree.hashContext;
  int _saplingSubtreeIndex = 0;
  int _orchardSubtreeIndex = 0;
  int get saplingSubtreeIndex => _saplingSubtreeIndex;
  int get orchardSubtreeIndex => _orchardSubtreeIndex;

  DefaultMerkleController._({
    required this.context,
    required this.provider,
    OrchardShardTree? orchardTree,
    SaplingShardTree? saplingTree,
    int? saplingSubtreeIndex,
    int? orchardSubtreeIndex,
  }) : _orchardTree =
           orchardTree ??
           OrchardShardTree(OrchardShardStore(context.orchardHashable())),
       _saplingTree =
           saplingTree ??
           SaplingShardTree(SaplingShardStore(context.saplingHashable())),
       _saplingSubtreeIndex = saplingSubtreeIndex ?? 0,
       _orchardSubtreeIndex = orchardSubtreeIndex ?? 0;
  factory DefaultMerkleController({
    required ZcashCryptoContext context,
    required IGrpcProvider<
      IServiceProvider,
      IServiceRequestParams,
      BaseGRPCServiceRequestParams
    >
    provider,
  }) {
    return DefaultMerkleController._(context: context, provider: provider);
  }
  factory DefaultMerkleController.fromChainMerkleState({
    required ZcashCryptoContext context,
    required IGrpcProvider<
      IServiceProvider,
      IServiceRequestParams,
      BaseGRPCServiceRequestParams
    >
    provider,
    required ChainMerkleState state,
  }) {
    return DefaultMerkleController._(
      context: context,
      provider: provider,
      orchardSubtreeIndex: state.orchardSabtreeIndex,
      orchardTree: state.orchard,
      saplingSubtreeIndex: state.saplingSubtreeIndex,
      saplingTree: state.sapling,
    );
  }
  factory DefaultMerkleController.deserialize({
    List<int>? bytes,
    CborObject? obj,
    required ZcashCryptoContext context,
    required ZcashWalletdProvider provider,
  }) {
    final state = ChainMerkleState.deserialize(
      bytes: bytes,
      orchardHashable: context.orchardHashable(),
      saplingHashable: context.saplingHashable(),
      object: obj,
    );
    return DefaultMerkleController.fromChainMerkleState(
      context: context,
      provider: provider,
      state: state,
    );
  }

  @override
  Future<void> initSubtreeRoot({
    required int finalSaplingTree,
    required int finalOrchardTree,
  }) async {
    await _lock.run(() async {
      final cSapIndex = _saplingSubtreeIndex;
      final cOrchardIndex = _orchardSubtreeIndex;
      int index = finalSaplingTree ~/ BinaryOps.mask16;
      if (index > cSapIndex) {
        _saplingSubtreeIndex = await _updateSaplingSubtreeRoots(cSapIndex + 1);
      }
      index = finalOrchardTree ~/ BinaryOps.mask16;
      if (index > cOrchardIndex) {
        _orchardSubtreeIndex = await _updateOrchardSubtreeRoots(
          cOrchardIndex + 1,
        );
      }
    });
  }

  @override
  Future<void> insertSubtree(SerializableMerkleInsertReport subutree) async {
    await initSubtreeRoot(
      finalOrchardTree: subutree.finalOrchardTree,
      finalSaplingTree: subutree.finalSaplingTree,
    );
    await _lock.run(() async {
      final sapling = subutree.sapling;
      SplayTreeMap<int, LeafPosition>? saplingCheckpoints;
      SplayTreeMap<int, LeafPosition>? orchardCheckpoints;
      final chainState = subutree.chainState;
      await updateChainState(
        IntUtils.max(subutree.height - 1, 0),
        chainState: chainState,
      );
      if (sapling != null) {
        final entries = sapling.checkpoints.map(
          (e) => MapEntry<int, LeafPosition>(e.checkpoint, e.position),
        );
        saplingCheckpoints = SplayTreeMap<int, LeafPosition>.from(
          Map<int, LeafPosition>.fromEntries(entries),
        );
        _saplingTree.insertTree(sapling.subtree, saplingCheckpoints);
      }
      final orchard = subutree.orchard;
      if (orchard != null) {
        final entries = orchard.checkpoints.map(
          (e) => MapEntry<int, LeafPosition>(e.checkpoint, e.position),
        );
        orchardCheckpoints = SplayTreeMap<int, LeafPosition>.from(
          Map<int, LeafPosition>.fromEntries(entries),
        );
        _orchardTree.insertTree(orchard.subtree, orchardCheckpoints);
      }
      final saplingMissing = ensureCheckpoints(
        orchardCheckpoints?.keys.toList() ?? [],
        saplingCheckpoints,
        chainState.finalSaplingTree,
      );
      final orchardMissing = ensureCheckpoints(
        saplingCheckpoints?.keys.toList() ?? [],
        orchardCheckpoints,
        chainState.finalOrchardTree,
      );
      final minSaplingHeight = _saplingTree.store.maxCheckpointId() ?? 0;
      for (final i in saplingMissing) {
        if (i.key > minSaplingHeight) {
          _saplingTree.store.addCheckpoint(i.key, i.value);
        }
      }
      final minOrchardHeight = _orchardTree.store.maxCheckpointId() ?? 0;
      for (final i in orchardMissing) {
        if (i.key > minOrchardHeight) {
          _orchardTree.store.addCheckpoint(i.key, i.value);
        }
      }
    });
  }

  Future<MerkleState> _buildContinuallyState({
    required MerkleState? previousState,
    required List<ScannedBlock> scannedBlocks,
  }) async {
    if (scannedBlocks.isEmpty) {
      throw MerkleBuilderException.failed(
        "updateState",
        reason: "No scanned blocks provided.",
      );
    }

    final scannedBlock = scannedBlocks.first.blockId;
    ChainState state = switch (previousState) {
      MerkleState(:final state) => state,
      null => await updateChainState(IntUtils.max(0, scannedBlock - 1)),
    };
    final latestState = MerkleState(
      state: state,
      saplingFinalTreeSize: scannedBlocks.last.bundles.sapling.finalTreeSize,
      orchardFinalTreeSize: scannedBlocks.last.bundles.orchard.finalTreeSize,
      latestBlockId: scannedBlocks.last.blockId,
      startBlock: scannedBlock,
    );
    if (previousState == null) {
      return latestState;
    }

    try {
      final int expectedOrchardTreeSize = previousState.orchardFinalTreeSize;
      final int expectedSaplingTreeSize = previousState.saplingFinalTreeSize;
      final first = scannedBlocks.first;
      final actualOrchardStart =
          first.bundles.orchard.finalTreeSize -
          first.bundles.orchard.commitments.length;

      final actualSaplingStart =
          first.bundles.sapling.finalTreeSize -
          first.bundles.sapling.commitments.length;

      final int expectedNextBlock = previousState.latestBlockId + 1;
      if (scannedBlock != expectedNextBlock) {
        throw MerkleBuilderException.failed(
          "updateState",
          reason: "Non-sequential block detected. ",
        );
      }
      if (actualOrchardStart != expectedOrchardTreeSize) {
        throw MerkleBuilderException.failed(
          "updateState",
          reason: "Orchard tree size mismatch at block $scannedBlock.",
        );
      }

      if (actualSaplingStart != expectedSaplingTreeSize) {
        throw MerkleBuilderException.failed(
          "updateState",
          reason: "Sapling tree size mismatch at block $scannedBlock. ",
        );
      }
      return latestState;
    } on MerkleBuilderException catch (e) {
      throw MerkleBuilderException(
        e.message,
        details: {
          ...e.details ?? {},
          "firstBlock": latestState.startBlock.toString(),
          "latestBlockId": latestState.latestBlockId.toString(),
          "orchardFinalTreeSize": latestState.orchardFinalTreeSize.toString(),
          "saplingFinalTreeSize": latestState.saplingFinalTreeSize.toString(),
          "stateBlockHeight": latestState.state.blockHeight.toString(),
          "actualOrchardTreeSize":
              scannedBlocks.first.bundles.orchard.finalTreeSize.toString(),
          "actualSaplingTreeSize":
              scannedBlocks.first.bundles.sapling.finalTreeSize.toString(),
        },
      );
    }
  }

  @override
  Future<SerializableMerkleInsertReport?> updateState(
    List<ScannedBlock> scannedBlocks, {
    bool continually = false,
  }) async {
    if (scannedBlocks.isEmpty) return null;
    scannedBlocks = switch (continually) {
      true => scannedBlocks,
      false =>
        scannedBlocks.clone()..sort((a, b) => a.blockId.compareTo(b.blockId)),
    };
    final int finalOrchardTreeSize =
        scannedBlocks.last.bundles.orchard.finalTreeSize;
    final int finalSaplingTreeSize =
        scannedBlocks.last.bundles.sapling.finalTreeSize;
    await initSubtreeRoot(
      finalOrchardTree: finalOrchardTreeSize,
      finalSaplingTree: finalSaplingTreeSize,
    );
    return await _lock.run(() async {
      if (!continually) _latestState = null;
      final scannedBlock = scannedBlocks.first.blockId;
      ChainState chainState;
      if (continually) {
        final state = await _buildContinuallyState(
          scannedBlocks: scannedBlocks,
          previousState: _latestState,
        );
        _latestState = state;
        chainState = state.state;
      } else {
        chainState = await updateChainState(IntUtils.max(scannedBlock - 1, 0));
      }
      final startOrchard = LeafPosition(
        scannedBlocks.first.bundles.orchard.finalTreeSize -
            scannedBlocks.first.bundles.orchard.commitments.length,
      );

      final startSapling = LeafPosition(
        scannedBlocks.first.bundles.sapling.finalTreeSize -
            scannedBlocks.first.bundles.sapling.commitments.length,
      );

      final endOrchard = LeafPosition(
        scannedBlocks.last.bundles.orchard.finalTreeSize,
      );
      final endSapling = LeafPosition(
        scannedBlocks.last.bundles.sapling.finalTreeSize,
      );
      final saplingCommitments =
          scannedBlocks.expand((e) => e.bundles.sapling.commitments).toList();
      final orchardCommitments =
          scannedBlocks.expand((e) => e.bundles.orchard.commitments).toList();

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
      final saplingMissing = ensureCheckpoints(
        orchardSubtree?.checkpoints.keys.toList() ?? [],
        saplingSubtree?.checkpoints,
        chainState.finalSaplingTree,
      );

      final orchardMissing = ensureCheckpoints(
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
      final minOrchardHeight = _orchardTree.store.maxCheckpointId() ?? 0;
      for (final i in orchardMissing) {
        if (i.key > minOrchardHeight) {
          _orchardTree.store.addCheckpoint(i.key, i.value);
        }
      }
      return SerializableMerkleInsertReport(
        height: scannedBlock,
        finalOrchardTree: finalOrchardTreeSize,
        chainState: chainState,
        finalSaplingTree: finalSaplingTreeSize,
        sapling: switch (saplingSubtree) {
          null => null,
          TreeBatchInsertReport<SaplingNode, int> insert =>
            SerializableTreeInsertReport(
              subtree: insert.subtree,
              checkpoints:
                  insert.checkpoints.entries
                      .map(
                        (e) => SerializableTreeCheckpointPosition(
                          checkpoint: e.key,
                          position: e.value,
                        ),
                      )
                      .toList(),
            ),
        },
        orchard: switch (orchardSubtree) {
          null => null,
          TreeBatchInsertReport<OrchardMerkleHash, int> insert =>
            SerializableTreeInsertReport(
              subtree: insert.subtree,
              checkpoints:
                  insert.checkpoints.entries
                      .map(
                        (e) => SerializableTreeCheckpointPosition(
                          checkpoint: e.key,
                          position: e.value,
                        ),
                      )
                      .toList(),
            ),
        },
      );
    });
  }

  static BuildMerleOutput buildMerkleStatic({
    required int targetHeight,
    required ZcashCryptoContext context,
    List<SaplingScannedOutput> saplingOutputs = const [],
    List<OrchardScannedOutput> orchardOutputs = const [],
    OrchardShardTree? orchardTree,
    SaplingShardTree? saplingTree,
  }) {
    if (saplingOutputs.isEmpty && orchardOutputs.isEmpty) {
      return BuildMerleOutput(
        orchardNotes: [],
        saplingNotes: [],
        orchardAnchor: OrchardAnchor.emptyTree(),
        saplingAnchor: SaplingAnchor.emptyTree(),
      );
    }
    bool hasSapling = saplingOutputs.isNotEmpty;
    if (hasSapling && saplingTree == null) {
      throw MerkleBuilderException.failed(
        "buildMerkle",
        reason: "Missing sapling shard tree.",
      );
    }
    bool hasOrchard = orchardOutputs.isNotEmpty;
    if (hasOrchard && orchardTree == null) {
      throw MerkleBuilderException.failed(
        "buildMerkle",
        reason: "Missing orchard shard tree.",
      );
    }
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
    final height = targetHeight;

    final saplingCheckpoint = switch (saplingTree) {
      SaplingShardTree sapling when hasSapling => sapling.findLatestCheckpoint(
        height,
      ),
      _ => null,
    };
    final orchardCheckpoint = switch (orchardTree) {
      OrchardShardTree orchard when hasOrchard => orchard.findLatestCheckpoint(
        height,
      ),
      _ => null,
    };

    int? anchorHeight = () {
      if (saplingCheckpoint != null && orchardCheckpoint != null) {
        return IntUtils.min(saplingCheckpoint, orchardCheckpoint);
      }
      return saplingCheckpoint ?? orchardCheckpoint;
    }();
    if (anchorHeight == null) {
      throw MerkleBuilderException.failed(
        "buildMerkle",
        reason: "No valid checkpoint was found.",
      );
    }
    final oRoot = switch (orchardTree) {
      OrchardShardTree orchard when hasOrchard => orchard.rootAtCheckpointId(
        anchorHeight,
      ),
      _ => null,
    };

    final sRoot = switch (saplingTree) {
      SaplingShardTree sapling when hasSapling => sapling.rootAtCheckpointId(
        anchorHeight,
      ),
      _ => null,
    };
    final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
    oNotes = [];
    final List<ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
    sNotes = [];
    if (hasOrchard && oRoot == null) {
      throw MerkleBuilderException.failed(
        "buildMerkle",
        reason: "Missing orchard checkpoint",
      );
    }
    if (hasSapling && sRoot == null) {
      throw MerkleBuilderException.failed(
        "buildMerkle",
        reason: "Missing sapling checkpoint",
      );
    }

    for (final output in orchardOutputs) {
      final oMerkle = orchardTree?.witnessAtCheckpointIdCaching(
        position: output.noteCommitmentTreePosition,
        checkpointId: anchorHeight,
      );
      if (oMerkle == null) {
        throw MerkleBuilderException.failed(
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
        throw MerkleBuilderException.failed(
          "buildMerkle",
          reason: "Orchard anchor mismatch.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
      oNotes.add(ScannedOutputWithMerkle(output: output, merklePath: oMerkle));
    }
    for (final output in saplingOutputs) {
      final sMerkle = saplingTree?.witnessAtCheckpointIdCaching(
        position: output.noteCommitmentTreePosition,
        checkpointId: anchorHeight,
      );
      if (sMerkle == null) {
        throw MerkleBuilderException.failed(
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
        throw MerkleBuilderException.failed(
          "buildMerkle",
          reason: "Sapling anchor mismatch.",
          details: {
            "position": output.noteCommitmentTreePosition.position.toString(),
            "height": anchorHeight.toString(),
          },
        );
      }
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
  Future<BuildMerleOutput> buildMerkle({
    int? targetHeight,
    List<SaplingScannedOutput> saplingOutputs = const [],
    List<OrchardScannedOutput> orchardOutputs = const [],
  }) async {
    final height = targetHeight ?? await _currentHeight();
    return buildMerkleStatic(
      targetHeight: height,
      context: context,
      orchardOutputs: orchardOutputs,
      saplingOutputs: saplingOutputs,
      orchardTree: _orchardTree,
      saplingTree: _saplingTree,
    );
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
  ChainMerkleState toSerializableChainShardTree() {
    return ChainMerkleState(
      sapling: _saplingTree,
      orchard: _orchardTree,
      orchardSabtreeIndex: _orchardSubtreeIndex,
      saplingSubtreeIndex: _saplingSubtreeIndex,
    );
  }

  static
  /// Ensures that checkpoints exist for the given heights.
  List<MapEntry<int, Checkpoint>>
  ensureCheckpoints<H extends MerkleNodeValue>(
    Iterable<int> ensureHeights,
    SplayTreeMap<int, LeafPosition>? existingCheckpointPositions,
    NonEmptyFrontier<H>? stateFinalTree,
  ) {
    final result = <MapEntry<int, Checkpoint>>[];

    for (final ensureHeight in ensureHeights) {
      MapEntry<int, LeafPosition>? lastEntry;

      // 🔑 Efficient ordered lookup (early break)
      final it = existingCheckpointPositions?.entries.iterator;
      while (it != null && it.moveNext()) {
        final entry = it.current;
        if (entry.key > ensureHeight) break;
        lastEntry = entry;
      }

      if (lastEntry == null) {
        // Equivalent to Rust's:
        // state_final_tree.value().map_or_else(...)
        // final frontierValue = stateFinalTree.frontier;

        final checkpoint =
            stateFinalTree == null
                ? Checkpoint.treeEmpty()
                : Checkpoint.atPosition(stateFinalTree.position);

        result.add(MapEntry(ensureHeight, checkpoint));
      } else {
        final existingHeight = lastEntry.key;
        final position = lastEntry.value;

        if (existingHeight < ensureHeight) {
          result.add(MapEntry(ensureHeight, Checkpoint.atPosition(position)));
        }
        // else: equal → skip (same as Rust)
      }
    }

    return result;
  }

  Future<int> _updateSaplingSubtreeRoots(int startIndex) async {
    final sapligSubtree = await provider.requestOnceAsync(
      ZcashGrpcRequestMessage(
        request: ZWalletdGetSubtreeRoots(
          getSubtreeRoots: ZWalletdGetSubtreeRootsArg(
            shieldedProtocol: ZcashProtocol.sapling.toShieldedProtocol(),
            startIndex: startIndex,
          ),
        ),
      ),
    );
    int index = startIndex;
    for (final i in sapligSubtree) {
      final roothash = i.getRootHashes();
      final addr = NodeAddress(level: shardHeight, index: index++);
      _saplingTree.insert(
        value: SaplingNode.fromBytes(roothash),
        rootAddr: addr,
      );
    }
    return index;
  }

  Future<int> _updateOrchardSubtreeRoots(int startIndex) async {
    final orchardSubtree = await provider.requestOnceAsync(
      ZcashGrpcRequestMessage(
        request: ZWalletdGetSubtreeRoots(
          getSubtreeRoots: ZWalletdGetSubtreeRootsArg(
            shieldedProtocol: ZcashProtocol.orchard.toShieldedProtocol(),
            startIndex: startIndex,
          ),
        ),
      ),
    );

    final latest = orchardSubtree.lastOrNull?.completingBlockHeight;
    if (orchardSubtree.isNotEmpty && latest == null) {
      throw MerkleBuilderException.failed(
        "updateOrchardSubtreeRoots",
        reason: "Unexcpected service response. Invalid subtree block height.",
      );
    }
    int index = startIndex;
    for (final i in orchardSubtree) {
      final roothash = i.getRootHashes();
      _orchardTree.insert(
        value: OrchardMerkleHash.fromBytes(roothash),
        rootAddr: NodeAddress(level: shardHeight, index: index++),
      );
    }
    return index;
  }

  Future<int> _currentHeight() async {
    final blockId = await provider.request(
      ZcashGrpcRequestMessage(request: ZWalletdGetLatestBlock()),
    );
    return blockId.getHeight();
  }

  Future<ChainState> _getChainState(int block) async {
    if (block <= 0) {
      block = 1;
    }
    final chainStateData = await provider.request(
      ZcashGrpcRequestMessage(
        request: ZWalletdGetTreeState(
          getTreeState: ZWalletdBlockID(height: BigInt.from(block)),
        ),
      ),
    );
    return chainStateData.toChainState();
  }

  Future<ChainState> updateChainState(
    int block, {
    ChainState? chainState,
  }) async {
    chainState ??= await _getChainState(block);

    _orchardTree.insertFrontier(
      Frontier(frontier: chainState.finalOrchardTree),
      RetentionCheckpoint(
        marking: MarkingState.reference,
        id: chainState.blockHeight,
      ),
    );
    _saplingTree.insertFrontier(
      Frontier(frontier: chainState.finalSaplingTree),
      RetentionCheckpoint(
        marking: MarkingState.reference,
        id: chainState.blockHeight,
      ),
    );
    return chainState;
  }
}

class MerkleState {
  final ChainState state;
  final int saplingFinalTreeSize;
  final int orchardFinalTreeSize;
  final int latestBlockId;
  final int startBlock;
  const MerkleState({
    required this.state,
    required this.saplingFinalTreeSize,
    required this.orchardFinalTreeSize,
    required this.latestBlockId,
    required this.startBlock,
  });

  @override
  String toString() {
    return "MerkleState {saplingFinalTreeSize:$saplingFinalTreeSize, orchardFinalTreeSize:$orchardFinalTreeSize, latestBlockId:$latestBlockId}";
  }
}
