import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/pczt/exception/exception.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';

import 'extractor.dart';

abstract mixin class PcztIoFinalizer implements PcztExtractor {
  bool hasShieldedSpends() {
    return sapling.spends.isNotEmpty || orchard.actions.isNotEmpty;
  }

  bool hasShieldedOutputs() {
    return sapling.outputs.isNotEmpty || orchard.actions.isNotEmpty;
  }

  bool hasTransparentSpends() {
    return transparent.inputs.isNotEmpty;
  }

  bool hasTransparentOutputs() {
    return transparent.outputs.isNotEmpty;
  }

  Future<void> finalizeIo(ZCashCryptoContext context) async {
    if (!hasShieldedSpends() && !hasTransparentSpends()) {
      throw PcztException.failed("finalizeIo", reason: "No spends.");
    }
    if (!hasShieldedOutputs() && !hasTransparentOutputs()) {
      throw PcztException.failed("finalizeIo", reason: "No outputs.");
    }
    final tx = toTxData();
    final digest = tx.toTxDeigest();
    final sighash = SighashGenerator.v5(
        tx: tx,
        digest: digest,
        input: ShieldedSignableInput(),
        amounts: transparent.inputs.map((e) => e.value).toList(),
        scriptPubKeys: transparent.inputs.map((e) => e.scriptPubkey).toList());
    await sapling.finalize(sighash: sighash, context: context);
    await orchard.finalize(sighash: sighash, context: context);
    if (hasShieldedSpends() || hasShieldedOutputs()) {
      global.disableModifiable();
    }
  }
}

abstract mixin class PcztSpendFinalizer implements PcztExtractor {
  void finalizeSpends() {
    transparent.finalize();
  }
}
