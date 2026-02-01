import 'dart:async';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/verifier/orchard.dart';
import 'package:zcash_dart/src/pczt/exception/exception.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/transparent/pczt/utils.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/sapling/verifier/sapling.dart';

abstract mixin class PcztExtractor implements PcztV1 {
  TransactionData toTxData() {
    final version = global.getTxVersion();
    if (version.type != TxVersionType.v5) {
      throw PcztException.failed(
        "toTxData",
        reason: "Unsupported transaction version.",
      );
    }
    final consensusBranchId = global.getBranchId();
    final transparent = this.transparent.extractEffects();
    final sapling = this.sapling.extractEffects();
    final orchard = this.orchard.extractEffects();
    return TransactionData(
      version: version,
      consensusBranchId: consensusBranchId,
      locktime: TransparentPcztUtils.getTranspareentLocktime(
        global.fallbackLockTime,
        this.transparent.inputs,
      ),
      expiryHeight: global.expiryHeight,
      transparentBundle: transparent,
      orchardBundle: orchard,
      saplingBundle: sapling,
    );
  }

  Future<({ZCashTransaction tx, List<int> sighash})> _extract(
    ZCashCryptoContext context,
    bool verifySignatures,
  ) async {
    final version = global.getTxVersion();
    if (version.type != TxVersionType.v5) {
      throw PcztException.failed(
        "toTxData",
        reason: "Unsupported transaction version.",
      );
    }
    final consensusBranchId = global.getBranchId();
    final transparent = this.transparent.extract();
    this.transparent.inputs;
    final sapling = this.sapling.extract();
    final orchard = this.orchard.extract();
    final lockTime = TransparentPcztUtils.getTranspareentLocktime(
      global.fallbackLockTime,
      this.transparent.inputs,
    );
    TransactionData txData = TransactionData(
      version: version,
      consensusBranchId: consensusBranchId,
      locktime: lockTime,
      expiryHeight: global.expiryHeight,
      orchardBundle: orchard?.bundle,
      saplingBundle: sapling?.bundle,
      transparentBundle: transparent.bundle,
    );
    final digest = txData.toTxDeigest();

    final sighash = SighashGenerator.v5(
      tx: txData,
      digest: digest,
      input: ShieldedSignableInput(),
      amounts: this.transparent.inputs.map((e) => e.value).toList(),
      scriptPubKeys:
          this.transparent.inputs.map((e) => e.scriptPubkey).toList(),
    );
    final saplingBundle = await sapling?.buildBindingAutorization(
      sighash: sighash,
      context: context,
      verifySignature: verifySignatures,
    );
    final orchardBundle = await orchard?.buildBindingAutorization(
      sighash: sighash,
      context: context,
      verifyBindingSignature: verifySignatures,
    );
    txData = txData.copyWith(
      saplingBundle: saplingBundle,
      orchardBundle: orchardBundle,
    );
    return (
      tx: ZCashTransaction(txId: txData.toTxId(), transactionData: txData),
      sighash: sighash,
    );
  }

  FutureOr<ZCashTransaction> extract(
    ZCashCryptoContext context, {
    SaplingBaseBundleVerifier? saplingBundleVerification,
    OrchardBaseBundleVerifier? orchardBundleVerification,
    bool verifyProofs = true,
    bool verifySignatures = true,
  }) async {
    final tx = await _extract(context, verifySignatures);
    final saplingBundle = tx.tx.transactionData.saplingBundle;
    final orchardBundle = tx.tx.transactionData.orchardBundle;
    final sighash = tx.sighash;
    if (saplingBundle != null &&
        (saplingBundle.shieldedSpends.isNotEmpty ||
            saplingBundle.shieldedOutputs.isNotEmpty)) {
      saplingBundleVerification ??= SaplingBundleVerification();
      if (verifyProofs || verifySignatures) {
        final verifiy = await saplingBundleVerification.validateBundle(
          bundle: saplingBundle,
          sighash: sighash,
          context: context,
          verifyProofs: verifyProofs,
          verifySignatures: verifySignatures,
        );
        if (!verifiy) {
          throw PcztException.failed(
            "extract",
            reason: "Sapling bundle verification failed.",
          );
        }
      }
    }
    if (orchardBundle != null && orchardBundle.actions.isNotEmpty) {
      orchardBundleVerification ??= OrchardBundleVerifier();
      final verifiy = await orchardBundleVerification.validateBundle(
        bundle: orchardBundle,
        sighash: sighash,
        context: context,
        verifyProofs: verifyProofs,
        verifySignatures: verifySignatures,
      );
      if (!verifiy) {
        throw PcztException.failed(
          "extract",
          reason: "Orchard bundle verification failed.",
        );
      }
    }
    return tx.tx;
  }
}
