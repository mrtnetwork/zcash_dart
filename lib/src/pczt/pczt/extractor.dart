import 'dart:async';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/orchard/verifier/orchard.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/transparent/pczt/utils.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/sapling/verifier/sapling.dart';

abstract mixin class PcztExtractor implements PcztV1 {
  static const _supportedVersions = [TxVersionType.v5, TxVersionType.v6];

  void _ensureSupportedVersion(TxVersion version) {
    if (!_supportedVersions.contains(version.type)) {
      throw ZcashErrors.pcztFailed(
        "toTxData",
        reason: "Unsupported transaction version.",
      );
    }
    if (version.type == TxVersionType.v6 && ironwood != null) {
      // The Ironwood bundle must use the ironwood_v3 bundle version;
      // enforced at extraction via the slot-specific version below.
    }
  }

  TransactionData toTxData() {
    final version = global.getTxVersion();
    _ensureSupportedVersion(version);
    final consensusBranchId = global.getBranchId();
    final transparent = this.transparent.extractEffects();
    final sapling = this.sapling.extractEffects();
    final orchard = this.orchard.extractEffects(
      params: OrchardPcztBundleParams.forBranch(
        branch: consensusBranchId,
        isIronwoodPool: false,
      ),
    );
    OrchardBundle? ironwood = switch (this.ironwood) {
      null => null,
      OrchardPcztBundle ironwood => ironwood.extractEffects(
        params: OrchardPcztBundleParams.forBranch(
          branch: consensusBranchId,
          isIronwoodPool: true,
        ),
      ),
    };
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
      ironwoodBundle: ironwood,
      saplingBundle: sapling,
    );
  }

  Future<({ZcashTransaction tx, List<int> sighash})> _extract(
    ZcashCryptoContext context,
    bool verifySignatures,
  ) async {
    final version = global.getTxVersion();
    _ensureSupportedVersion(version);
    final transparent = this.transparent.extract();
    this.transparent.inputs;
    final sapling = this.sapling.extract();
    final consensusBranchId = global.getBranchId();
    // final params = OrchardPcztBundleParams.forBranch(consensusBranchId);
    final orchard = this.orchard.extract(
      params: OrchardPcztBundleParams.forBranch(
        branch: consensusBranchId,
        isIronwoodPool: false,
      ),
    );
    final ironwoodExtracted = switch (ironwood) {
      OrchardPcztBundle ironwood => ironwood.extract(
        params: OrchardPcztBundleParams.forBranch(
          branch: consensusBranchId,
          isIronwoodPool: true,
        ),
      ),
      null => null,
    };
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
      ironwoodBundle: ironwoodExtracted?.bundle,
      saplingBundle: sapling?.bundle,
      transparentBundle: transparent.bundle,
    );
    final digest = txData.toTxDeigest();

    final sighash = SighashGenerator.forVersion(
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
    final ironwoodBundle = await ironwoodExtracted?.buildBindingAutorization(
      sighash: sighash,
      context: context,
      verifyBindingSignature: verifySignatures,
    );
    txData = txData.copyWith(
      saplingBundle: saplingBundle,
      orchardBundle: orchardBundle,
      ironwoodBundle: ironwoodBundle,
    );
    return (
      tx: ZcashTransaction(txId: txData.toTxId(), transactionData: txData),
      sighash: sighash,
    );
  }

  FutureOr<ZcashTransaction> extract(
    ZcashCryptoContext context, {
    SaplingBaseBundleVerifier? saplingBundleVerification,
    OrchardBaseBundleVerifier? orchardBundleVerification,
    bool verifyProofs = true,
    bool verifySignatures = true,
    // required int orchardVersion,
    // bool disableCrossAddress = false,
  }) async {
    final consensusBranchId = global.getBranchId();
    // final params = OrchardPcztBundleParams.forBranch(consensusBranchId);
    final tx = await _extract(context, verifySignatures);
    final saplingBundle = tx.tx.transactionData.saplingBundle;
    final orchardBundle = tx.tx.transactionData.orchardBundle;
    final ironwoodBundle = tx.tx.transactionData.ironwoodBundle;
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
          throw ZcashErrors.pcztFailed(
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
        version:
            OrchardPcztBundleParams.forBranch(
              branch: consensusBranchId,
              isIronwoodPool: false,
            ).version,
      );
      if (!verifiy) {
        throw ZcashErrors.pcztFailed(
          "extract",
          reason: "Orchard bundle verification failed.",
        );
      }
    }
    if (ironwoodBundle != null && ironwoodBundle.actions.isNotEmpty) {
      orchardBundleVerification ??= OrchardBundleVerifier();
      final verifiy = await orchardBundleVerification.validateBundle(
        bundle: ironwoodBundle,
        sighash: sighash,
        context: context,
        verifyProofs: verifyProofs,
        verifySignatures: verifySignatures,
        version:
            OrchardPcztBundleParams.forBranch(
              branch: consensusBranchId,
              isIronwoodPool: true,
            ).version,
      );
      if (!verifiy) {
        throw ZcashErrors.pcztFailed(
          "extract",
          reason: "Ironwood bundle verification failed.",
        );
      }
    }
    return tx.tx;
  }
}
