import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/transaction/commitment.dart';

class OrchardUtils {
  /// Returns whether two addresses correspond to the same expanded
  /// receiver, i.e. have equal `(g_d, pk_d)`.
  ///
  /// This matches the equality notion used by the cross-address
  /// restriction (official `Address::same_expanded_receiver`, enforced by
  /// the post-NU6.3 circuit)
  static bool sameExpandedReceiver(OrchardAddress a, OrchardAddress b) {
    return a == b;
  }

  static ({OrchardSpendingKey sk, OrchardFullViewingKey fvk})
  createDummySpendKey() {
    final sk = OrchardSpendingKey(QuickCrypto.generateRandom());
    final pallas = blockchainUtils.api.pallas;
    final f = pallas.scReduce64(PrfExpand.orchardAsk.apply(sk.sk));
    if (BytesUtils.isZeroConst(f)) {
      throw ZcashErrors.orchardFailed(
        "createDummySpendKey",
        reason: "zero scalar.",
      );
    }
    var pk = pallas.mult(f, OrchardKeyUtils.orchardSpendAuthSigBasepointBytes);
    if ((pk[31] >> 7) == 1) {
      pk = pallas.neg(pk);
    }
    final ak = RedPallasSpendPublicKey.fromBytes(pk);
    final fvk = OrchardFullViewingKey(
      ak: OrchardSpendValidatingKey(ak),
      nk: OrchardNullifierDerivingKey.fromSpendKey(sk),
      rivk: OrchardCommitIvkRandomness.fromSpendKey(sk),
    );
    return (sk: sk, fvk: fvk);
  }

  static BuBytes toNonZeroScalar(List<int> scalarBytes) {
    final scalar = blockchainUtils.api.pallas.scReduce64(scalarBytes);
    if (BytesUtils.isZeroConst(scalar)) {
      throw ZcashErrors.orchardFailed(
        "toNonZeroScalar",
        reason: "zero scalar.",
      );
    }
    return scalar;
  }

  static BuBytes kaOrchardBytes({
    required List<int> base,
    required List<int> sk,
  }) {
    final pallas = blockchainUtils.api.pallas;
    final p = pallas.mult(sk, base);
    if (BytesUtils.bytesEqualConst(p, pallas.identity())) {
      throw ZcashErrors.orchardFailed(
        "toNonZeroScalar",
        reason: "Scalar multiplication resulted in the identity point.",
      );
    }
    return p;
  }

  static BuBytes deriveNullfierKey({
    required OrchardNullifierDerivingKey nk,
    required List<int> rho,
    required List<int> psi,
    required OrchardNoteCommitment cm,
    required ZcashCryptoContext context,
  }) {
    final prf = nk.prfNf(rho: rho, context: context);
    final sumBytes = blockchainUtils.api.vesta.scAdd(prf, psi);
    if (!blockchainUtils.api.pallas.scCheck(sumBytes)) {
      throw ZcashErrors.orchardFailed(
        "deriveNullfierKey",
        reason: "Invalid scalar.",
      );
    }
    final k = blockchainUtils.api.pallas.hashToCurvePasta(
      domainPrefix: "z.cash:Orchard",
      message: "K".codeUnits,
    );
    final s = blockchainUtils.api.pallas.mult(sumBytes, k);
    final out = blockchainUtils.api.pallas.add(s, cm.toBytes());
    return PallasPoint.fromBytes(out).toAffine().x.toBytes();
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
