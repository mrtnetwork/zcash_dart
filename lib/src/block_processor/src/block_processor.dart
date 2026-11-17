import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/provider.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transaction/sighash_digest/types.dart';
import 'package:zcash_dart/src/transaction/types/transaction.dart';

class DefaultZcashBlockScanner extends DefaultZcashBlockProcessor {
  DefaultZcashBlockScanner({required super.config, required super.provider});

  /// Scans a range of blocks and emits scanned block results as a stream.
  Stream<ScannedBlock> scanBlock(int start, int end) {
    if (end < start) {
      throw ZcashErrors.scannerFailed(
        "scanBlock",
        reason: "Invalid block range.",
      );
    }
    final request = provider.requestStream(
      _createBlockRangeRequest(start, end),
    );
    BlockStateInfo? previousState;

    return request.asyncMap((block) {
      final state = buildBlockState(block, previousState: previousState);
      final scanned = _scanBlockInternal(block, state);
      previousState = state;
      return scanned;
    });
  }

  /// Scans a range of blocks and emits scanned block results as a stream.
  Future<Stream<T>> scanBlockAsync<T extends Object?>({
    required int start,
    required int end,
    required Future<T> Function(ScannedBlock block) onProcessed,
    Duration? throttleDelay,
  }) async {
    if (end < start) {
      throw ZcashErrors.scannerFailed(
        "scanBlock",
        reason: "Invalid block range.",
      );
    }
    final request = await provider.requestStreamAsync(
      _createBlockRangeRequest(start, end),
    );
    BlockStateInfo? previousState;
    return request.asyncMap((block) async {
      if (throttleDelay != null) await Future.delayed(throttleDelay);
      final state = buildBlockState(block, previousState: previousState);
      final scanned = await _scanBlockInternal(block, state);
      previousState = state;
      final result = await onProcessed(scanned);
      return result;
    });
  }

  /// Scans a range of blocks and emits scanned nullifiers results as a stream.
  Stream<ScannedNullifiers> scanNullifiers(int start, int end) {
    if (end < start) {
      throw ZcashErrors.scannerFailed(
        "scanBlock",
        reason: "Invalid block range.",
      );
    }
    final request = provider.requestStream(
      _createBlockRangeRequest(start, end),
    );
    BlockStateInfo? previousState;

    return request.map((block) {
      final state = buildBlockState(block, previousState: previousState);
      final scanned = _scanBlockNullifiers(block, state);
      previousState = state;
      return scanned;
    });
  }

  /// Scans a range of blocks and emits scanned nullifiers results as a stream.
  Future<Stream<ScannedNullifiers>> scanNullifiersAsync(
    int start,
    int end,
  ) async {
    if (end < start) {
      throw ZcashErrors.scannerFailed(
        "scanBlock",
        reason: "Invalid block range.",
      );
    }
    final request = await provider.requestStreamAsync(
      _createBlockRangeRequest(start, end),
    );
    BlockStateInfo? previousState;

    return request.map((block) {
      final state = buildBlockState(block, previousState: previousState);
      final scanned = _scanBlockNullifiers(block, state);
      previousState = state;
      return scanned;
    });
  }
}

class DefaultZcashBlockProcessor extends ZcashBlockProcessor {
  @override
  final IGrpcProvider<
    IServiceProvider,
    IServiceRequestParams,
    BaseGRPCServiceRequestParams
  >
  provider;
  @override
  final ZcashBlockProcessorConfig config;
  DefaultZcashBlockProcessor({required this.config, required this.provider});
}

abstract mixin class ZcashBlockProcessor {
  IGrpcProvider<
    IServiceProvider,
    IServiceRequestParams,
    BaseGRPCServiceRequestParams
  >
  get provider;
  abstract final ZcashBlockProcessorConfig config;
  ZcashNetwork get network => config.network;
  late SaplingDomain _saplingDomain = config.saplingDomain;
  SaplingDomain get saplingDomain => _saplingDomain;
  OrchardDomain get orchardDomain => config.orchardDomain;
  OrchardDomain get ironwoodDomain => config.ironwoodDomain;

  /// Builds and validates block state information from a compact block,
  /// optionally verifying continuity with the previous block state.
  BlockStateInfo buildBlockState(
    CompactBlock block, {
    BlockStateInfo? previousState,
  }) {
    if (!block.isValid()) {
      throw ZcashErrors.scannerFailed(
        "buildBlockState",
        reason: "Invalid compact block information.",
      );
    }
    final height = block.getHeight();

    final upgrade = config.activationProvider.protocolFromHeight(
      config.network,
      height,
    );
    int? saplingCommitmentTreeSize = block.saplingCommitmentTreeSize ?? 0;
    int? orchardCommitmentTreeSize = block.orchardCommitmentTreeSize ?? 0;
    int? ironwoodCommitmentTreeSize = block.ironwoodCommitmentTreeSize ?? 0;

    orchardCommitmentTreeSize -= block.totalOrchardOutputs();
    ironwoodCommitmentTreeSize -= block.totalIronwoodOutputs();
    saplingCommitmentTreeSize -= block.totalSaplingOutputs();
    if (orchardCommitmentTreeSize.isNegative ||
        ironwoodCommitmentTreeSize.isNegative ||
        saplingCommitmentTreeSize.isNegative) {
      throw ZcashErrors.scannerFailed(
        "buildBlockState",
        reason: "Invalid compact block tree size.",
      );
    }
    final orchardFinalTreeSize =
        orchardCommitmentTreeSize + block.totalOrchardOutputs();
    final ironwoodFinalTreeSize =
        ironwoodCommitmentTreeSize + block.totalIronwoodOutputs();
    final saplingFinalTreeSize =
        saplingCommitmentTreeSize + block.totalSaplingOutputs();

    if (previousState != null) {
      if (height != (previousState.blockId + 1) ||
          orchardCommitmentTreeSize != previousState.orchardFinalTreeSize ||
          ironwoodCommitmentTreeSize != previousState.ironwoodFinalTreeSize ||
          saplingCommitmentTreeSize != previousState.saplingFinalTreeSize) {
        throw ZcashErrors.scannerFailed(
          "buildBlockState",
          reason: "Block state mismatch with previous block.",
        );
      }
    }
    final zip212enforcement = config.activationProvider.zip212Enforcement(
      network,
      height,
      protocol: upgrade,
    );

    return BlockStateInfo(
      orchardCommitmentTreeSize: orchardCommitmentTreeSize,
      saplingCommitmentTreeSize: saplingCommitmentTreeSize,
      ironwoodCommitmentTreeSize: ironwoodCommitmentTreeSize,
      upgrade: upgrade,
      orchardFinalTreeSize: orchardFinalTreeSize,
      saplingFinalTreeSize: saplingFinalTreeSize,
      ironwoodFinalTreeSize: ironwoodFinalTreeSize,
      blockId: height,
      blockhash: block.getHash(),
      timestamp: block.timestamp(),
      zip212enforcement: zip212enforcement,
    );
  }

  /// Scans a compact block and returns the resulting scanned block.
  Future<ScannedBlock> scanBlockSync(CompactBlock block) =>
      _scanBlockInternal(block, buildBlockState(block));

  Future<ScannedBlock> _scanBlockInternal(
    CompactBlock block,
    BlockStateInfo state,
  ) async {
    if (saplingDomain.zip212enforcement != state.zip212enforcement) {
      _saplingDomain = SaplingDomain(
        saplingDomain.context,
        zip212enforcement: state.zip212enforcement,
      );
    }
    final txes = block.vtx ?? [];
    final blockId = state.blockId;
    final timestamp = state.timestamp;
    final blockHash = state.blockhash;
    if (txes.isEmpty) {
      return ScannedBlock(
        blockId: blockId,
        timestamp: timestamp,
        blockhash: blockHash,
        bundles: ScannedBlockBundles(
          sapling: ScannedProtocolBundles(
            finalTreeSize: state.saplingFinalTreeSize,
          ),
          orchard: ScannedProtocolBundles(
            finalTreeSize: state.orchardFinalTreeSize,
          ),
          ironwood: ScannedProtocolBundles(
            finalTreeSize: state.ironwoodFinalTreeSize,
          ),
        ),
        orchardNullifiers: [],
        ironwoodNullifiers: [],
        saplingNullifiers: [],
      );
    }
    int orchardCommitmentTreeSize = state.orchardCommitmentTreeSize;
    int ironwoodCommitmentTreeSize = state.ironwoodCommitmentTreeSize;
    int saplingCommitmentTreeSize = state.saplingCommitmentTreeSize;
    List<ScannedTx> scannedTxes = [];
    List<ScannedBlockNullifier<OrchardNullifier>> orchardNullifiers = [];
    List<ScannedBlockNullifier<OrchardNullifier>> ironwoodNullifiers = [];
    List<ScannedBlockNullifier<SaplingNullifier>> saplingNullifiers = [];
    List<ScannedBlockCommitment<OrchardMerkleHash>> orchardCommitments = [];
    List<ScannedBlockCommitment<OrchardMerkleHash>> ironwoodCommitments = [];
    List<ScannedBlockCommitment<SaplingNode>> saplingCommitments = [];
    Retention<int> buildRetention(bool isLastCommitment, bool isMarked) {
      if (isLastCommitment) {
        return RetentionCheckpoint(
          marking: isMarked ? MarkingState.marked : MarkingState.none,
          id: blockId,
        );
      }
      if (isMarked) {
        return RetentionMarked();
      }
      return RetentionEphemeral();
    }

    final orchardIvks = config.getOrchardIvks(blockId);
    final saplingIvks = config.getSaplingIvks(blockId);

    Map<ZcashTxId, TransactionData?> cachedTx = {};

    for (final tx in txes) {
      List<OrchardScannedOutputWithIvk> orchardOutputs = [];
      List<OrchardScannedOutputWithIvk> ironwoodOutputs = [];
      List<SaplingScannedOutputWithIvk> saplingOutputs = [];
      final txId = tx.getTxId();
      final txIndex = tx.getTxIndex();
      final actions = tx.getCompactActions();
      final ironwoodActions = tx.getCompactIronwoodActions();
      final outputs = tx.getOutputDescription();
      for (final output in actions) {
        final leafPosition = orchardCommitmentTreeSize + output.outputIndex;
        assert(leafPosition < state.orchardFinalTreeSize);
        BatchIVKDecryptionResult<
          OrchardKeyAgreementPrivateKey,
          OrchardNote,
          OrchardAddress
        >?
        decrypt = orchardDomain.batchIvkCompactNoteDecryption(
          ivks: orchardIvks,
          output: output,
        );

        if (decrypt != null && config.exportMemos && decrypt.memo == null) {
          final fullOutput = await _tryGetTransaction(
            txId: txId,
            index: output.outputIndex,
            protocol: ZcashProtocol.orchard,
            txes: cachedTx,
          );
          assert(
            fullOutput != null,
            "Failed to export full output from transaction",
          );
          if (fullOutput != null) {
            final newDecrypt = orchardDomain.batchIvkNoteDecryption(
              ivks: orchardIvks,
              output: fullOutput.cast<OrchardShildOutput>(),
            );
            assert(
              newDecrypt != null,
              "Unexpected decrypt result. must not be null.",
            );
            assert(
              newDecrypt?.memo != null,
              "Unexpected decrypt result. memo must not be null.",
            );
            if (newDecrypt != null) decrypt = newDecrypt;
          }
        }
        if (decrypt != null) {
          final scanKey = config.findOrchardScanKey(decrypt.ivk);
          OrchardNullifier? nullifier;
          final fvk = scanKey.scanKey.fvk;
          if (fvk != null) {
            nullifier = decrypt.note.nullifier(
              fvk: fvk,
              context: config.context,
            );
          }
          orchardOutputs.add(
            OrchardScannedOutputWithIvk(
              output: OrchardScannedOutput(
                index: output.outputIndex,
                ephemeralKey: output.ephemeralKey,
                note: decrypt.note,

                noteCommitmentTreePosition: LeafPosition(leafPosition),
              ),
              ivk: scanKey.ivk,
              nullifier: nullifier,
              memo: decrypt.memo,
            ),
          );
        }

        orchardCommitments.add(
          ScannedBlockCommitment(
            node: OrchardMerkleHash(output.cmx.inner),
            retention: buildRetention(
              leafPosition + 1 == state.orchardFinalTreeSize,
              decrypt != null,
            ),
          ),
        );
        orchardNullifiers.add(
          ScannedBlockNullifier(
            txId: txId,
            index: output.outputIndex,
            nullifier: output.nf,
          ),
        );
      }

      // Ironwood pool (NU6.3 second slot): same Orchard-shaped compact
      // actions, separate tree, v3 trial-decryption domain. Viewing keys
      // are shared with the Orchard pool.
      for (final output in ironwoodActions) {
        final leafPosition = ironwoodCommitmentTreeSize + output.outputIndex;
        assert(leafPosition < state.ironwoodFinalTreeSize);
        BatchIVKDecryptionResult<
          OrchardKeyAgreementPrivateKey,
          OrchardNote,
          OrchardAddress
        >?
        decrypt = ironwoodDomain.batchIvkCompactNoteDecryption(
          ivks: orchardIvks,
          output: output,
        );
        if (decrypt != null && config.exportMemos && decrypt.memo == null) {
          final fullOutput = await _tryGetTransaction(
            txId: txId,
            index: output.outputIndex,
            protocol: ZcashProtocol.orchard,
            isIronwood: true,
            txes: cachedTx,
          );
          assert(
            fullOutput != null,
            "Failed to export full output from transaction",
          );
          if (fullOutput != null) {
            final newDecrypt = ironwoodDomain.batchIvkNoteDecryption(
              ivks: orchardIvks,
              output: fullOutput.cast<OrchardShildOutput>(),
            );
            assert(
              newDecrypt != null,
              "Unexpected decrypt result. must not be null.",
            );
            assert(
              newDecrypt?.memo != null,
              "Unexpected decrypt result. memo must not be null.",
            );
            if (newDecrypt != null) decrypt = newDecrypt;
          }
        }
        if (decrypt != null) {
          final scanKey = config.findOrchardScanKey(decrypt.ivk);
          OrchardNullifier? nullifier;
          final fvk = scanKey.scanKey.fvk;
          if (fvk != null) {
            nullifier = decrypt.note.nullifier(
              fvk: fvk,
              context: config.context,
            );
          }
          ironwoodOutputs.add(
            OrchardScannedOutputWithIvk(
              output: OrchardScannedOutput(
                index: output.outputIndex,
                ephemeralKey: output.ephemeralKey,
                note: decrypt.note,

                noteCommitmentTreePosition: LeafPosition(leafPosition),
              ),
              ivk: scanKey.ivk,
              nullifier: nullifier,
              memo: decrypt.memo,
            ),
          );
        }

        ironwoodCommitments.add(
          ScannedBlockCommitment(
            node: OrchardMerkleHash(output.cmx.inner),
            retention: buildRetention(
              leafPosition + 1 == state.ironwoodFinalTreeSize,
              decrypt != null,
            ),
          ),
        );
        ironwoodNullifiers.add(
          ScannedBlockNullifier(
            txId: txId,
            index: output.outputIndex,
            nullifier: output.nf,
          ),
        );
      }

      for (final output in outputs) {
        final leafPosition = saplingCommitmentTreeSize + output.outputIndex;
        assert(leafPosition < state.saplingFinalTreeSize);
        BatchIVKDecryptionResult<
          SaplingIvk,
          SaplingNote,
          SaplingPaymentAddress
        >?
        decrypt = saplingDomain.batchIvkCompactNoteDecryption(
          ivks: saplingIvks,
          output: output,
        );
        if (decrypt != null && config.exportMemos && decrypt.memo == null) {
          final fullOutput = await _tryGetTransaction(
            txId: txId,
            index: output.outputIndex,
            protocol: ZcashProtocol.sapling,
            txes: cachedTx,
          );
          assert(
            fullOutput != null,
            "Failed to export full output from transaction",
          );
          if (fullOutput != null) {
            final newDecrypt = saplingDomain.batchIvkNoteDecryption(
              ivks: saplingIvks,
              output: fullOutput.cast<SaplingShildOutput>(),
            );
            assert(
              newDecrypt != null,
              "Unexpected decrypt result. must not be null.",
            );
            assert(
              newDecrypt?.memo != null,
              "Unexpected decrypt result. mem0 must not be null.",
            );
            if (newDecrypt != null) decrypt = newDecrypt;
          }
        }
        if (decrypt != null) {
          final scanKey = config.findSaplingScanKey(decrypt.ivk);
          SaplingNullifier? nullifier;
          final fvk = scanKey.scanKey.fvk;
          if (fvk != null) {
            nullifier = decrypt.note.nullifier(
              nk: fvk.vk.nk,
              position: leafPosition,
              context: config.context,
            );
          }
          saplingOutputs.add(
            SaplingScannedOutputWithIvk(
              output: SaplingScannedOutput(
                index: output.outputIndex,
                ephemeralKey: output.ephemeralKey,
                note: decrypt.note,

                noteCommitmentTreePosition: LeafPosition(leafPosition),
              ),
              ivk: scanKey.ivk,
              nullifier: nullifier,
              memo: decrypt.memo,
            ),
          );
        }
        saplingCommitments.add(
          ScannedBlockCommitment(
            node: SaplingNode(output.cmu.inner),
            retention: buildRetention(
              leafPosition + 1 == state.saplingFinalTreeSize,
              decrypt != null,
            ),
          ),
        );
      }
      saplingNullifiers.addAll(
        tx.getSpends().map(
          (e) =>
              ScannedBlockNullifier(txId: txId, index: txIndex, nullifier: e),
        ),
      );

      scannedTxes.add(
        ScannedTx(
          txId: txId,
          index: txIndex,
          saplingOutputs: saplingOutputs,
          orchardOutputs: orchardOutputs,
          ironwoodOutputs: ironwoodOutputs,
        ),
      );
      orchardCommitmentTreeSize += actions.length;
      ironwoodCommitmentTreeSize += ironwoodActions.length;
      saplingCommitmentTreeSize += outputs.length;
    }
    return ScannedBlock(
      blockId: blockId,
      timestamp: timestamp,
      blockhash: blockHash,
      txes: scannedTxes,
      saplingNullifiers: saplingNullifiers,
      orchardNullifiers: orchardNullifiers,
      ironwoodNullifiers: ironwoodNullifiers,
      bundles: ScannedBlockBundles(
        sapling: ScannedProtocolBundles(
          finalTreeSize: state.saplingFinalTreeSize,
          commitments: saplingCommitments,
        ),
        orchard: ScannedProtocolBundles(
          finalTreeSize: state.orchardFinalTreeSize,
          commitments: orchardCommitments,
        ),
        ironwood: ScannedProtocolBundles(
          finalTreeSize: state.ironwoodFinalTreeSize,
          commitments: ironwoodCommitments,
        ),
      ),
    );
  }

  ScannedNullifiers scanNullifiersSync(CompactBlock block) =>
      _scanBlockNullifiers(block, buildBlockState(block));
  ScannedNullifiers _scanBlockNullifiers(
    CompactBlock block,
    BlockStateInfo state,
  ) {
    final txes = block.vtx ?? [];
    final blockId = state.blockId;
    final timestamp = state.timestamp;
    final blockHash = state.blockhash;
    if (txes.isEmpty) {
      return ScannedNullifiers(
        blockId: blockId,
        timestamp: timestamp,
        blockhash: blockHash,
      );
    }
    List<ScannedBlockNullifier<OrchardNullifier>> orchardNullifiers = [];
    List<ScannedBlockNullifier<OrchardNullifier>> ironwoodNullifiers = [];
    List<ScannedBlockNullifier<SaplingNullifier>> saplingNullifiers = [];

    for (final tx in txes) {
      final txId = tx.getTxId();
      final txIndex = tx.getTxIndex();
      final actions = tx.getCompactActions();
      for (final output in actions) {
        orchardNullifiers.add(
          ScannedBlockNullifier(
            txId: txId,
            index: output.outputIndex,
            nullifier: output.nf,
          ),
        );
      }
      for (final output in tx.getCompactIronwoodActions()) {
        ironwoodNullifiers.add(
          ScannedBlockNullifier(
            txId: txId,
            index: output.outputIndex,
            nullifier: output.nf,
          ),
        );
      }
      final spends = tx.getSpends();
      for (final i in spends) {
        saplingNullifiers.add(
          ScannedBlockNullifier(txId: txId, index: txIndex, nullifier: i),
        );
      }
    }
    return ScannedNullifiers(
      blockId: blockId,
      timestamp: timestamp,
      blockhash: blockHash,
      orchardNullifiers: orchardNullifiers,
      ironwoodNullifiers: ironwoodNullifiers,
      saplingNullifiers: saplingNullifiers,
    );
  }

  Future<ShieldedOutput?> _tryGetTransaction({
    required ZcashTxId txId,
    required int index,
    required ZcashProtocol protocol,
    bool isIronwood = false,
    required Map<ZcashTxId, TransactionData?> txes,
  }) async {
    try {
      if (txes.containsKey(txId) && txes[txId] == null) {
        return null;
      }
      final txData = await provider.request(
        ZcashGrpcRequestMessage(
          request: ZWalletdGetTransaction(
            getTransaction: ZWalletdTxFilter(hash: txId.hash),
          ),
        ),
      );
      final toTx = txData.toTransaction();
      txes[txId] = toTx;
      final ShieldedOutput? result = switch (protocol) {
        ZcashProtocol.orchard =>
          isIronwood
              ? toTx.ironwoodBundle?.actions.elementAtOrNull(index)
              : toTx.orchardBundle?.actions.elementAtOrNull(index),
        ZcashProtocol.sapling => toTx.saplingBundle?.shieldedOutputs.elementAt(
          index,
        ),
        ZcashProtocol.transparent => null,
      };
      return result;
    } catch (_) {
      return null;
    }
  }

  ZcashGrpcRequestMessage<ZWalletdCompactBlock> _createBlockRangeRequest(
    int start,
    int end,
  ) {
    return ZcashGrpcRequestMessage(
      request: ZWalletdGetBlockRange(
        getBlockRange: ZWalletdBlockRange(
          start: ZWalletdBlockID(height: BigInt.from(start)),
          end: ZWalletdBlockID(height: BigInt.from(end)),
        ),
      ),
    );
  }
}
