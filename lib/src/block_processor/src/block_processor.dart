import 'dart:async';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/exception.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/provider.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';

class DefaultZCashBlockScanner extends DefaultZCashBlockProcessor {
  final ZCashWalletdProvider provider;
  DefaultZCashBlockScanner(
      {required ZCashBlockProcessorConfig config, required this.provider})
      : super(config);

  /// Scans a range of blocks and emits scanned block results as a stream.
  /// [pendingNullifier] for detect account spends.
  Stream<ScannedBlock> scanBlock(int start, int end,
      {List<Nullifier> pendingNullifier = const []}) {
    if (end < start) {
      throw ZCashBlockScannerException.failed("scanBlock",
          reason: "Invalid block range.");
    }
    final request = provider.requestStream(
        ZWalletdRequestGetBlockRange(WalletdBlockRange.range(start, end)));
    BlockStateInfo? previousState;
    final nullifiers = pendingNullifier.clone();

    return request.map((block) {
      final state = buildBlockState(block, previousState: previousState);
      final scanned = _scanBlockInternal(block, state, nullifiers: nullifiers);
      previousState = state;
      return scanned;
    });
  }
}

class DefaultZCashBlockProcessor extends ZCashBlockProcessor {
  @override
  final ZCashBlockProcessorConfig config;
  DefaultZCashBlockProcessor(this.config);
}

abstract mixin class ZCashBlockProcessor {
  abstract final ZCashBlockProcessorConfig config;
  ZCashNetwork get network => config.network;
  List<SaplingIvk> get saplingIvks => config.saplingIvks;
  List<OrchardKeyAgreementPrivateKey> get orchardIvks => config.orchardIvks;
  late SaplingDomainNative _saplingDomain = config.saplingDomain;
  SaplingDomainNative get saplingDomain => _saplingDomain;
  OrchardDomainNative get orchardDomain => config.orchardDomain;

  /// Builds and validates block state information from a compact block,
  /// optionally verifying continuity with the previous block state.
  BlockStateInfo buildBlockState(CompactBlock block,
      {BlockStateInfo? previousState}) {
    if (!block.isValid()) {
      throw ZCashBlockScannerException.failed("buildBlockState",
          reason: "Invalid compact block information.");
    }
    final height = block.getHeight();

    final upgrade = NetworkUpgrade.fromHeight(height, config.network);
    int? saplingCommitmentTreeSize = block.saplingCommitmentTreeSize;
    int? orchardCommitmentTreeSize = block.orchardCommitmentTreeSize;
    if (saplingCommitmentTreeSize == null) {
      if (upgrade.hasSapling()) {
        throw ZCashBlockScannerException.failed("buildBlockState",
            reason: "Invalid compact block sapling tree size.");
      }
      saplingCommitmentTreeSize = 0;
    }
    if (orchardCommitmentTreeSize == null) {
      if (upgrade.hasOrchard()) {
        throw ZCashBlockScannerException.failed("buildBlockState",
            reason: "Invalid compact block orchard tree size.");
      }
      orchardCommitmentTreeSize = 0;
    }
    orchardCommitmentTreeSize -= block.totalOrchardOutputs();
    saplingCommitmentTreeSize -= block.totalSaplingOutputs();
    if (orchardCommitmentTreeSize.isNegative ||
        saplingCommitmentTreeSize.isNegative) {
      throw ZCashBlockScannerException.failed("buildBlockState",
          reason: "Invalid compact block tree size.");
    }
    final orchardFinalTreeSize =
        orchardCommitmentTreeSize + block.totalOrchardOutputs();
    final saplingFinalTreeSize =
        saplingCommitmentTreeSize + block.totalSaplingOutputs();

    Zip212Enforcement fromNetworkUpgrade() {
      if (upgrade < NetworkUpgrade.canopy) {
        return Zip212Enforcement.off;
      }
      final gracePeriod =
          upgrade.activeHeight(network) + NetworkUpgrade.gracePeriod;
      if (gracePeriod < height) {
        return Zip212Enforcement.gracePeriod;
      }
      return Zip212Enforcement.on;
    }

    if (previousState != null) {
      if (height != (previousState.blockId + 1) ||
          orchardCommitmentTreeSize != previousState.orchardFinalTreeSize ||
          saplingCommitmentTreeSize != previousState.saplingFinalTreeSize) {
        throw ZCashBlockScannerException.failed("buildBlockState",
            reason: "Block state mismatch with previous block.");
      }
    }

    return BlockStateInfo(
        orchardCommitmentTreeSize: orchardCommitmentTreeSize,
        saplingCommitmentTreeSize: saplingCommitmentTreeSize,
        upgrade: upgrade,
        orchardFinalTreeSize: orchardFinalTreeSize,
        saplingFinalTreeSize: saplingFinalTreeSize,
        blockId: height,
        blockhash: block.getHash(),
        timestamp: block.timestamp(),
        zip212enforcement: fromNetworkUpgrade());
  }

  /// Scans a compact block and returns the resulting scanned block.
  ScannedBlock scan(CompactBlock block) =>
      scanBlockInternal(block, buildBlockState(block));
  ScannedBlock scanBlockInternal(CompactBlock block, BlockStateInfo state,
      {List<Nullifier> nullifiers = const []}) {
    return _scanBlockInternal(block, state, nullifiers: nullifiers.clone());
  }

  ScannedBlock _scanBlockInternal(CompactBlock block, BlockStateInfo state,
      {List<Nullifier> nullifiers = const []}) {
    if (saplingDomain.zip212enforcement != state.zip212enforcement) {
      _saplingDomain = SaplingDomainNative(saplingDomain.context,
          zip212enforcement: state.zip212enforcement);
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
          sapling:
              SaplingScannedBundles(finalTreeSize: state.saplingFinalTreeSize),
          orchard:
              OrchardScannedBundles(finalTreeSize: state.orchardFinalTreeSize));
    }
    int orchardCommitmentTreeSize = state.orchardCommitmentTreeSize;
    int saplingCommitmentTreeSize = state.saplingCommitmentTreeSize;
    List<ScannedTx> scannedTxes = [];
    List<ScannedBlockNullifiers<OrchardNullifier>> orchardNullifiers = [];
    List<ScannedBlockNullifiers<SaplingNullifier>> saplingNullifiers = [];
    List<ScannedBlockCommitment<OrchardMerkleHash>> orchardCommitments = [];
    List<ScannedBlockCommitment<SaplingNode>> saplingCommitments = [];
    Retention<int> buildRetention(bool isLastCommitment, bool isMarked) {
      if (isLastCommitment) {
        return RetentionCheckpoint(
            marking: isMarked ? MarkingState.marked : MarkingState.none,
            id: blockId);
      }
      if (isMarked) {
        return RetentionMarked();
      }
      return RetentionEphemeral();
    }

    for (final tx in txes) {
      List<OrchardScannedOutput> orchardOutputs = [];
      List<SaplingScannedOutput> saplingOutputs = [];
      final txId = tx.getTxId();
      final txIndex = tx.getTxIndex();
      final actions = tx.getCompactActions();
      final outputs = tx.getOutputDescription();
      final List<OrchardNullifier> orchardSpends = [];
      for (final output in actions) {
        final leafPosition = orchardCommitmentTreeSize + output.outputIndex;
        assert(leafPosition < state.orchardFinalTreeSize);
        final decrypt = orchardDomain.batchIvkCompactNoteDecryption(
            ivks: orchardIvks, output: output);
        if (decrypt != null) {
          final scanKey = config.findOrchardScanKey(decrypt.ivk);
          OrchardNullifier? nullifier;
          final fvk = scanKey.scanKey.fvk;
          if (fvk != null) {
            nullifier =
                decrypt.note.nullifier(fvk: fvk, context: config.context);
            nullifiers.add(nullifier);
          }
          orchardOutputs.add(OrchardScannedOutput(
              index: output.outputIndex,
              ephemeralKey: output.ephemeralKey,
              note: decrypt.note,
              noteCommitmentTreePosition: LeafPosition(leafPosition),
              account: scanKey.ivk,
              isChange: false,
              nullifier: nullifier));
        }

        orchardCommitments.add(ScannedBlockCommitment(
            node: OrchardMerkleHash(output.cmx.inner),
            retention: buildRetention(
                leafPosition + 1 == state.orchardFinalTreeSize,
                decrypt != null)));
        orchardSpends.add(output.nf);
        orchardNullifiers.add(ScannedBlockNullifiers(
            txId: txId, index: output.outputIndex, nullifier: output.nf));
      }

      for (final output in outputs) {
        final leafPosition = saplingCommitmentTreeSize + output.outputIndex;
        assert(leafPosition < state.saplingFinalTreeSize);
        final decrypt = saplingDomain.batchIvkCompactNoteDecryption(
            ivks: saplingIvks, output: output);
        if (decrypt != null) {
          final scanKey = config.findSaplingScanKey(decrypt.ivk);
          SaplingNullifier? nullifier;
          final fvk = scanKey.scanKey.fvk;
          if (fvk != null) {
            nullifier = decrypt.note.nullifier(
                nk: fvk.vk.nk, position: leafPosition, context: config.context);
            nullifiers.add(nullifier);
          }
          saplingOutputs.add(SaplingScannedOutput(
              index: output.outputIndex,
              ephemeralKey: output.ephemeralKey,
              note: decrypt.note,
              noteCommitmentTreePosition: LeafPosition(leafPosition),
              account: scanKey.ivk,
              nullifier: nullifier,
              isChange: false));
        }
        saplingCommitments.add(ScannedBlockCommitment(
            node: SaplingNode(output.cmu.inner),
            retention: buildRetention(
                leafPosition + 1 == state.saplingFinalTreeSize,
                decrypt != null)));
      }
      final spends = tx.getSpends();
      for (final i in spends) {
        saplingNullifiers.add(
            ScannedBlockNullifiers(txId: txId, index: txIndex, nullifier: i));
      }
      final accountSpends = nullifiers
          .where((e) => spends.contains(e) || orchardSpends.contains(e))
          .toList();
      nullifiers.removeWhere((e) => accountSpends.contains(e));
      scannedTxes.add(ScannedTx(
          txId: txId,
          index: txIndex,
          saplingOutputs: saplingOutputs,
          orchardOutputs: orchardOutputs,
          orchardSpends: accountSpends.whereType<OrchardNullifier>().toList(),
          saplingSpends: accountSpends.whereType<SaplingNullifier>().toList()));
      orchardCommitmentTreeSize += actions.length;
      saplingCommitmentTreeSize += outputs.length;
    }
    return ScannedBlock(
        blockId: blockId,
        timestamp: timestamp,
        blockhash: blockHash,
        txes: scannedTxes,
        sapling: SaplingScannedBundles(
            finalTreeSize: state.saplingFinalTreeSize,
            commitments: saplingCommitments,
            nullifiers: saplingNullifiers),
        orchard: OrchardScannedBundles(
            finalTreeSize: state.orchardFinalTreeSize,
            commitments: orchardCommitments,
            nullifiers: orchardNullifiers));
  }
}
