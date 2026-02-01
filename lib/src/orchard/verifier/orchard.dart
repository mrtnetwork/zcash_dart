import 'dart:async';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/transaction/bundle.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/verifier.dart';

abstract mixin class OrchardBaseBundleVerifier {
  Future<bool> validateBundle(
      {required OrchardBundle bundle,
      required List<int> sighash,
      required ZCashCryptoContext context,
      bool verifyProofs,
      bool verifySignatures});
}

class OrchardBundleVerifier implements OrchardBaseBundleVerifier {
  @override
  Future<bool> validateBundle(
      {required OrchardBundle bundle,
      required List<int> sighash,
      required ZCashCryptoContext context,
      bool verifyProofs = true,
      bool verifySignatures = true}) async {
    final bindingSig = bundle.authorization?.bindingSignature;
    final proof = bundle.authorization?.proof;
    if (bindingSig == null || proof == null) return false;

    for (final i in bundle.actions) {
      final sig = i.authorization;
      if (sig == null) return false;
      if (verifySignatures &&
          !await context.verifyRedPallasSignature(
              vk: i.rk, signature: sig, message: sighash)) {
        return false;
      }
    }

    final bvk = bundle.toBvk();
    if (verifySignatures &&
        !await context.verifyRedPallasSignature(
            vk: bvk, signature: bindingSig, message: sighash)) {
      return false;
    }
    return !verifyProofs ||
        await (context.verifyOrchardProof(OrchardVerifyInputs(
            proofBytes: proof.inner, instances: bundle.toCircuitInstance())));
  }
}
