import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';
import 'package:zcash_dart/src/sapling/transaction/commitment.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/multipack.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/verifier.dart';

abstract mixin class SaplingBaseBundleVerifier {
  Future<bool> validateBundle({
    required SaplingBundle bundle,
    required List<int> sighash,
    required ZCashCryptoContext context,
    bool verifyProofs,
    bool verifySignatures,
  });
}

class SaplingBundleVerification implements SaplingBaseBundleVerifier {
  static SaplingVerifyInputs? _extractSpendProof({
    required JubJubNativePoint rk,
    required SaplingAnchor anchor,
    required SaplingNullifier nullifier,
    required SaplingValueCommitment cv,
    required GrothProofBytes zkproof,
  }) {
    // final rkPoint = rk.toPoint();
    if (rk.isSmallOrder()) {
      return null;
    }
    List<JubJubNativeFq> inputs = [];
    final affine = rk.toAffine();
    inputs.add(affine.u);
    inputs.add(affine.v);
    final cvAffine = cv.inner.toAffine();
    inputs.add(cvAffine.u);
    inputs.add(cvAffine.v);
    inputs.add(anchor.inner);
    final n = GMultipackUtils.computeMultipacking(
        BytesUtils.bytesToBits(nullifier.toBytes()));
    assert(n.length == 2, "unexpected multipacking result.");
    if (n.length != 2) {
      return null;
    }
    inputs.addAll(n);
    try {
      return SaplingVerifyInputs(proof: zkproof, inputs: inputs);
    } catch (_) {
      return null;
    }
  }

  static SaplingVerifyInputs? _checkOutputSync({
    required SaplingValueCommitment cv,
    required SaplingExtractedNoteCommitment cmu,
    required JubJubNativePoint epk,
    required GrothProofBytes zkproof,
  }) {
    if (epk.isSmallOrder()) return null;
    List<JubJubNativeFq> inputs = [];
    final cvAffine = cv.inner.toAffine();
    inputs.add(cvAffine.u);
    inputs.add(cvAffine.v);
    final epkAfine = epk.toAffine();
    inputs.add(epkAfine.u);
    inputs.add(epkAfine.v);
    inputs.add(JubJubNativeFq.fromBytes(cmu.toBytes()));
    try {
      return SaplingVerifyInputs(proof: zkproof, inputs: inputs);
    } catch (_) {
      return null;
    }
  }

  static FutureOr<SaplingVerifyInputs?> _checkSpend(
      {required SaplingValueCommitment cv,
      required SaplingAnchor anchor,
      required SaplingNullifier nullifier,
      required SaplingSpendVerificationKey rk,
      required ReddsaSignature spendAuthSignature,
      required List<int> sighash,
      required GrothProofBytes zkproof,
      required ZCashCryptoContext context,
      required bool verifySignatures}) async {
    final proof = _extractSpendProof(
        rk: rk.toPoint(),
        anchor: anchor,
        nullifier: nullifier,
        cv: cv,
        zkproof: zkproof);
    if (proof == null) return null;
    if (verifySignatures &&
        !await context.verifyRedJubJubSignature(
            vk: rk, signature: spendAuthSignature, message: sighash)) {
      return null;
    }
    return proof;
  }

  @override
  Future<bool> validateBundle(
      {required SaplingBundle bundle,
      required List<int> sighash,
      required ZCashCryptoContext context,
      bool verifyProofs = true,
      bool verifySignatures = true}) async {
    final bindingSignature = bundle.authorization?.bindingSignature;
    if (bindingSignature == null) return false;
    SaplingCommitmentSum commitmentSum = SaplingCommitmentSum.zero();
    List<SaplingVerifyInputs> spendsProofs = [];
    List<SaplingVerifyInputs> outputProofs = [];
    for (final i in bundle.shieldedSpends) {
      final sig = i.authSig;
      final proof = i.zkProof;
      if (sig == null || proof == null) return false;
      final r = await _checkSpend(
          context: context,
          cv: i.cv,
          anchor: i.anchor,
          nullifier: i.nullifier,
          rk: i.rk,
          spendAuthSignature: sig,
          sighash: sighash,
          zkproof: proof,
          verifySignatures: verifySignatures);
      if (r == null) return false;
      spendsProofs.add(r);
      commitmentSum += i.cv;
    }
    for (final i in bundle.shieldedOutputs) {
      final proof = i.zkproof;
      if (proof == null) return false;
      final r = _checkOutputSync(
          cv: i.cv, cmu: i.cmu, epk: i.ephemeralKey.toPoint(), zkproof: proof);
      if (r == null) return false;
      outputProofs.add(r);
      commitmentSum -= i.cv;
    }

    final vk = commitmentSum.toBvk(bundle.valueBalance);
    if (!verifySignatures ||
        await context.verifyRedJubJubSignature(
            vk: vk, signature: bindingSignature, message: sighash)) {
      if (!verifyProofs) return true;

      final spendOk = spendsProofs.isEmpty ||
          await context.verifySaplingSpendProofs(spendsProofs);
      final outputOk = outputProofs.isEmpty ||
          await context.verifySaplingOutputProofs(outputProofs);
      return outputOk && spendOk;
    }
    return false;
  }
}
