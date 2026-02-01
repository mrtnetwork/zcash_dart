import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/orchard/transaction/commitment.dart';

class OrchardUtils {
  static ({OrchardSpendingKey sk, OrchardFullViewingKey fvk})
      createDummySpendKey() {
    final sk = OrchardSpendingKey(QuickCrypto.generateRandom());
    final f = VestaNativeFq.fromBytes64(PrfExpand.orchardAsk.apply(sk.sk));
    if (f.isZero()) {
      throw OrchardException.operationFailed("createDummySpendKey",
          reason: "zero scalar.");
    }
    final generator = OrchardKeyUtils.orchardSpendAuthSigBasepointNative;
    var pk = generator * f;
    if ((pk.toBytes()[31] >> 7).toU8 == 1) {
      pk = generator * -f;
    }
    final ak = OrchardSpendVerificationKey(pk);
    final fvk = OrchardFullViewingKey(
        ak: OrchardSpendValidatingKey(ak),
        nk: OrchardNullifierDerivingKey.fromSpendKey(sk),
        rivk: OrchardCommitIvkRandomness.fromSpendKey(sk));
    return (sk: sk, fvk: fvk);
  }

  static VestaNativeFq toNonZeroScalar(List<int> scalarBytes) {
    final scalar = VestaNativeFq.fromBytes64(scalarBytes);
    if (scalar.isZero()) {
      throw OrchardException.operationFailed("toNonZeroScalar",
          reason: "zero scalar.");
    }
    return scalar;
  }

  static PallasNativePoint kaOrchardNative(
      {required PallasNativePoint base, required VestaNativeFq sk}) {
    assert(!sk.isZero());
    final PallasNativePoint p = base * sk;
    if (p.isIdentity()) {
      throw OrchardException.operationFailed("toNonZeroScalar",
          reason: "Scalar multiplication resulted in the identity point.");
    }
    return p;
  }

  static PallasNativeFp deriveNullfierKey({
    required OrchardNullifierDerivingKey nk,
    required PallasNativeFp rho,
    required PallasNativeFp psi,
    required OrchardNoteCommitment cm,
    required ZCashCryptoContext context,
  }) {
    final k = PallasNativePoint.hashToCurve(
        domainPrefix: "z.cash:Orchard", message: "K".codeUnits);
    final s = (k *
            VestaNativeFq.fromBytes(
                (nk.prfNf(rho: rho, context: context) + psi).toBytes()) +
        cm.inner);
    return s.toAffine().x;
  }

  static const int lOrchardBase = 255;

  /// SWU hash-to-curve personalization for the value commitment generator
  static const String valueCommitmentPersonalization = "z.cash:Orchard-cv";

  /// SWU hash-to-curve value for the value commitment generator
  static const List<int> valueCommitmentVBytes = [0x76]; // ASCII 'v'

  /// SWU hash-to-curve value for the value commitment generator
  static const List<int> valueCommitmentRBytes = [0x72]; // ASCII 'r'

  static const String noteCommitmentPersonalization =
      "z.cash:Orchard-NoteCommit";
}
