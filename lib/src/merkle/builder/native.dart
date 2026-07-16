import 'dart:async';
import 'dart:collection';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/builder/types.dart';
import 'package:zcash_dart/src/merkle/tree/shard_tree.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/provider.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';
import 'package:zcash_dart/src/zk_proof/lib/lib.dart';
import 'merkle.dart';

class NativeMerkleController implements MerkleController {
  final ZKLib lib;
  final ZcashCryptoContext context;
  final IGrpcProvider<
    IServiceProvider,
    IServiceRequestParams,
    BaseGRPCServiceRequestParams
  >
  provider;
  final TreeLevel shardHeight = TreeLevel(NoteEncryptionConst.shardHeight);
  ChainMerkleState? _state;
  int? _contextId;
  final _lock = SafeAtomicLock();
  MerkleState? _latestState;
  int _saplingSubtreeIndex = 0;
  int _orchardSubtreeIndex = 0;
  int get saplingSubtreeIndex => _saplingSubtreeIndex;
  int get orchardSubtreeIndex => _orchardSubtreeIndex;

  NativeMerkleController._({
    required this.lib,
    required this.context,
    required this.provider,
    ChainMerkleState? state,
    int? saplingSubtreeIndex,
    int? orchardSubtreeIndex,
  }) : _state = state,
       _saplingSubtreeIndex = saplingSubtreeIndex ?? 0,
       _orchardSubtreeIndex = orchardSubtreeIndex ?? 0;
  factory NativeMerkleController({
    required ZcashCryptoContext context,
    required IGrpcProvider<
      IServiceProvider,
      IServiceRequestParams,
      BaseGRPCServiceRequestParams
    >
    provider,
    required ZKLib liberary,
  }) {
    return NativeMerkleController._(
      lib: liberary,
      context: context,
      provider: provider,
    );
  }

  factory NativeMerkleController.fromChainMerkleState({
    required ZcashCryptoContext context,
    required IGrpcProvider<
      IServiceProvider,
      IServiceRequestParams,
      BaseGRPCServiceRequestParams
    >
    provider,
    required ZKLib liberary,
    required ChainMerkleState state,
  }) {
    return NativeMerkleController._(
      context: context,
      provider: provider,
      lib: liberary,
      state: state,
      orchardSubtreeIndex: state.orchardSabtreeIndex,
      saplingSubtreeIndex: state.saplingSubtreeIndex,
    );
  }

  factory NativeMerkleController.deserialize({
    List<int>? bytes,
    CborObject? obj,
    required ZcashCryptoContext context,
    required ZcashWalletdProvider provider,
    required ZKLib liberary,
  }) {
    final state = ChainMerkleState.deserialize(
      bytes: bytes,
      orchardHashable: context.orchardHashable(),
      saplingHashable: context.saplingHashable(),
      object: obj,
    );
    return NativeMerkleController.fromChainMerkleState(
      context: context,
      provider: provider,
      state: state,
      liberary: liberary,
    );
  }

  Future<int> _getOrCreateContext() async {
    return _lock.run(() async {
      int? id = _contextId;
      if (id != null) return id;
      final context =
          _state ??
          ChainMerkleState(
            orchard: OrchardShardTree(
              OrchardShardStore(this.context.orchardHashable()),
            ),
            sapling: SaplingShardTree(
              SaplingShardStore(this.context.saplingHashable()),
            ),
            saplingSubtreeIndex: 0,
            orchardSabtreeIndex: 0,
          );

      final contextId = lib.sendRequest(ZKRequestMerkleCreateContext(context));
      _contextId = contextId;
      _state = null;
      return contextId;
    }, lockId: LockId.two);
  }

  /// should not used controlle after close context.
  Future<void> closeContext() async {
    return _lock.run(() async {
      int? id = _contextId;
      if (id == null) return;
      lib.sendRequest(ZKRequestMerkleCloseContext(contextId: id));
      _contextId = null;
    }, lockId: LockId.two);
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
    });
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
  }) async {
    if (saplingOutputs.isEmpty && orchardOutputs.isEmpty) {
      return BuildMerleOutput(
        orchardNotes: [],
        saplingNotes: [],
        orchardAnchor: OrchardAnchor.emptyTree(),
        saplingAnchor: SaplingAnchor.emptyTree(),
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
    // final
    final height = targetHeight ?? await _currentHeight();
    final contextId = await _getOrCreateContext();
    final context = await toSerializableChainShardTree();

    final saplingCheckpoint = switch (hasSapling) {
      true => context.sapling.findLatestCheckpoint(height),
      _ => null,
    };
    final orchardCheckpoint = switch (hasOrchard) {
      true => context.orchard.findLatestCheckpoint(height),
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
    // OrchardMerkleHash? oRoot;
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
              protocol: ZcashProtocol.orchard,
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
          protocol: ZcashProtocol.sapling,
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
    final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
    oNotes = [];
    final List<ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
    sNotes = [];
    for (final oIndexed in saplingOutputs.indexed) {
      final output = oIndexed.$2;
      final witness = saplingWitnesses.paths.elementAt(oIndexed.$1);
      final root = saplingWitnesses.root;
      if (root == null) {
        throw MerkleBuilderException.failed(
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
                SaplingNode.fromCmu(output.note.cmu(this.context)),
                this.context.saplingHashable(),
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
      sNotes.add(ScannedOutputWithMerkle(output: output, merklePath: witness));
    }

    for (final oIndexed in orchardOutputs.indexed) {
      final output = oIndexed.$2;
      final witness = orchardWitnesses.paths.elementAt(oIndexed.$1);
      final root = orchardWitnesses.root;
      if (root == null) {
        throw MerkleBuilderException.failed(
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
                    output.note
                        .commitment(this.context)
                        .toExtractedNoteCommitment(),
                hashContext: this.context.orchardHashable(),
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
      oNotes.add(ScannedOutputWithMerkle(output: output, merklePath: witness));
    }

    return BuildMerleOutput(
      orchardNotes: oNotes,
      saplingNotes: sNotes,
      orchardAnchor: orchardWitnesses.anchor,
      saplingAnchor: saplingWitnesses.anchor,
    );
  }

  @override
  Future<OrchardShardTree> getOrcardShardTree() async {
    final contextId = await _getOrCreateContext();
    final state = lib.sendRequest(
      ZKRequestMerkleGetContext(contextId: contextId),
    );
    return OrchardShardTree(
      state
          .toContext(context)
          .orchard
          .store
          .clone(hashContext: context.orchardHashable()),
    );
  }

  @override
  Future<SaplingShardTree> getSaplingShardTree() async {
    final contextId = await _getOrCreateContext();
    final state = lib.sendRequest(
      ZKRequestMerkleGetContext(contextId: contextId),
    );
    return SaplingShardTree(
      state
          .toContext(context)
          .sapling
          .store
          .clone(hashContext: context.saplingHashable()),
    );
  }

  Future<({List<E> paths, H root})>
  _buildWitnessPaths<H extends MerkleNodeValue, E extends MerklePath<H>>({
    required H Function(List<int> bytes) fromBytes,
    required E Function(List<H> paths, LeafPosition position) createPath,
    required ZcashProtocol protocol,
    required int contextId,
    required int anchorHeight,
    required List<int> possitions,
  }) async {
    final orchardWitness = lib.sendRequest(
      ZKRequestMerkleCreateWitness(
        contextId: contextId,
        params: CreateWitnessParams(
          protocol: protocol,
          height: anchorHeight,
          positions: possitions,
        ),
      ),
    );
    final root = switch (orchardWitness.anchor) {
      null => null,
      List<int> anchor => fromBytes(anchor),
    };
    if (root == null) {
      throw MerkleBuilderException.failed(
        "buildMerkle",
        reason: "Missing ${protocol.name} checkpoint",
      );
    }
    final pathes = orchardWitness.merkles;
    if (pathes.length != possitions.length) {
      throw MerkleBuilderException.failed(
        "buildMerkle",
        reason:
            "Mismatch between requested positions and returned merkle paths.",
      );
    }

    final merkles =
        pathes
            .map(
              (e) => createPath(
                e.paths.map(fromBytes).toList(),
                LeafPosition(e.position),
              ),
            )
            .toList();
    return (root: root, paths: merkles);
  }

  @override
  Future<void> insertSubtree(SerializableMerkleInsertReport subutree) async {
    await initSubtreeRoot(
      finalOrchardTree: subutree.finalOrchardTree,
      finalSaplingTree: subutree.finalSaplingTree,
    );
    await _lock.run(() async {
      final chainState = subutree.chainState;
      await updateChainState(subutree.height, chainState: chainState);
      final contextId = await _getOrCreateContext();
      lib.sendRequest(
        ZKRequestMerkleMergeState(contextId: contextId, report: subutree),
      );
    });
  }

  @override
  Future<ChainMerkleState> toSerializableChainShardTree() async {
    final contextId = await _getOrCreateContext();
    final state = lib.sendRequest(
      ZKRequestMerkleGetContext(contextId: contextId),
    );
    return state
        .toContext(context)
        .copyWith(
          orchardSabtreeIndex: _orchardSubtreeIndex,
          saplingSubtreeIndex: _saplingSubtreeIndex,
        );
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
      null => await updateChainState(IntUtils.max(scannedBlock - 1, 0)),
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
      if (continually) {
        final state = await _buildContinuallyState(
          scannedBlocks: scannedBlocks,
          previousState: _latestState,
        );
        _latestState = state;
      } else {
        await updateChainState(IntUtils.max(0, scannedBlock - 1));
      }
      final contextId = await _getOrCreateContext();
      final result = lib.sendRequest(
        ZKRequestMerkleUpdateState(
          contextId: contextId,
          scannedBlocks: ScannedBlocksBundles(
            bundles: scannedBlocks.map((e) => e.bundles).toList(),
            startHeight: scannedBlock,
          ),
        ),
      );
      return result.toReport(context);
    });
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
    final id = await _getOrCreateContext();
    lib.sendRequest(
      ZKRequestMerkleInsertChainState(contextId: id, chainState: chainState),
    );
    return chainState;
  }

  Future<int> _updateSubtreeRootes({
    required int startIndex,
    required ZcashProtocol protocol,
  }) async {
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
    final contextId = await _getOrCreateContext();
    final subtree = SubtreeRoots(
      start: startIndex,
      hashes: subtrees.map((e) => e.getRootHashes()).toList(),
    );
    return await lib.sendRequest(
      ZKRequestMerkleUpdateSubtree(
        contextId: contextId,
        subtree: subtree,
        protocol: protocol,
      ),
    );
  }
}
