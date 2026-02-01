import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/groth16/params.dart';

class Groth16Verifier {
  final Groth16PreparedVerifyingKey vk;
  const Groth16Verifier(this.vk);

  bool verify(Groth16Proof proof, List<JubJubNativeFq> inputs) {
    if (inputs.length + 1 != vk.ic.length) {
      throw ArgumentException.invalidOperationArguments("verifyProof",
          reason: "Invalid input length.");
    }
    G1NativeProjective acc = vk.ic[0].toProjective();
    for (final i in inputs.indexed) {
      acc += (vk.ic[i.$1 + 1] * i.$2);
    }
    final terms = [
      (proof.a, G2NativePrepared.fromG2(proof.b)),
      (acc.toAffine(), vk.negGammaG2),
      (proof.c, vk.negDeltaG2),
    ];
    try {
      return MultiMillerLoopBls12()
              .multiMillerLoop(terms)
              .finalExponentiation() ==
          vk.alphaG1BetaG2;
    } on CryptoException {
      return false;
    }
  }
}
