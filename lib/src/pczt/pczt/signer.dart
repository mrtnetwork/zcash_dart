import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/pczt/exception/exception.dart';
import 'package:zcash_dart/src/pczt/pczt/extractor.dart';
import 'package:zcash_dart/src/sapling/keys/keys.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/keys/private_key.dart';

abstract mixin class PcztSigner implements PcztExtractor {
  ({TransactionData txData, TxDigestsPart digest, List<int> sighash})
      _generateTxDigest(SignableInput input) {
    final txData = toTxData();
    final digest = txData.toTxDeigest();
    final amounts = transparent.inputs.map((e) => e.value).toList();
    final scripts = transparent.inputs.map((e) => e.scriptPubkey).toList();
    final sighash = SighashGenerator.v5(
        tx: txData,
        digest: digest,
        input: input,
        amounts: amounts,
        scriptPubKeys: scripts);
    return (txData: txData, digest: digest, sighash: sighash.asImmutableBytes);
  }

  Future<void> signTransparent(
      {required int index,
      required ZECPrivate sk,
      required ZCashCryptoContext context}) async {
    final input = transparent.inputs.elementAtOrNull(index);
    if (input == null) {
      throw PcztException.failed("signTransparent",
          reason: "Index out of range.", details: {"index": index});
    }

    final redeemScript = input.redeemScript ?? input.scriptPubkey;
    final signableInput = TransparentSignableInput(
        hashType: input.sighashType,
        index: index,
        scriptCode: redeemScript,
        sciptPubKey: input.scriptPubkey,
        amount: input.value);
    final digests = _generateTxDigest(signableInput);
    await input.sign(sighash: digests.sighash, context: context, sk: sk);

    /// Update transaction modifiability:
    ///
    /// - If the signer added a signature that does not use SIGHASH_ANYONECANPAY,
    ///   transparent inputs are no longer modifiable.
    if ((input.sighashType & BitcoinOpCodeConst.sighashAnyoneCanPay) == 0) {
      global.disableInputModifable();
    }

    /// - If the signer added a signature that does not use SIGHASH_NONE,
    ///   transparent outputs are no longer modifiable.
    ///   This also applies to SIGHASH_SINGLE.
    if ((input.sighashType & ~BitcoinOpCodeConst.sighashAnyoneCanPay) !=
        BitcoinOpCodeConst.sighashNone) {
      global.disableOutputModifable();
    }

    /// - If the signer added a signature that uses SIGHASH_SINGLE,
    ///   the HasSighashSingle flag must be set.
    if ((input.sighashType & ~BitcoinOpCodeConst.sighashAnyoneCanPay) ==
        BitcoinOpCodeConst.sighashSingle) {
      global.setHasSighashAll();
    }
    global.disableShieldModifiable();
  }

  Future<void> signSapling(
      {required int index,
      required SaplingSpendAuthorizingKey ask,
      required ZCashCryptoContext context}) async {
    final spend = sapling.spends.elementAtOrNull(index);
    if (spend == null) {
      throw PcztException.failed("signSapling",
          reason: "Index out of range.", details: {"index": index});
    }
    spend.verifyNullifier(context);
    final digests = _generateTxDigest(ShieldedSignableInput());
    await spend.sign(sighash: digests.sighash, ask: ask, context: context);
    global.disableModifiable();
  }

  Future<void> signOrchard(
      {required int index,
      required OrchardSpendAuthorizingKey ask,
      required ZCashCryptoContext context}) async {
    final action = orchard.actions.elementAtOrNull(index);
    if (action == null) {
      throw PcztException.failed("signOrchard",
          reason: "Index out of range.", details: {"index": index});
    }
    action.spend.verifyNullifier(context);
    final digests = _generateTxDigest(ShieldedSignableInput());
    await action.sign(sighash: digests.sighash, context: context, ask: ask);

    global.disableModifiable();
  }

  void setSaplingProofGenerationKey(
      {required int index,
      SaplingProofGenerationKey? proofGenerationKey,
      SaplingExpandedSpendingKey? expsk}) {
    final spend = sapling.spends.elementAtOrNull(index);
    if (spend == null) {
      throw PcztException.failed("setSaplingProofGenerationKey",
          reason: "Index out of range.", details: {"index": index});
    }
    if (proofGenerationKey == null && expsk == null) {
      throw PcztException.failed("setSaplingProofGenerationKey",
          reason: "Either proofGenerationKey or expsk must be provided.",
          details: {"index": index});
    }
    proofGenerationKey ??=
        SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(expsk!);
    spend.setProofGenerationKey(proofGenerationKey);
  }
}
