import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/merkle.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/range_constrained.dart';

class SinsemillaMessagePiece {
  final AssignedCell<PallasNativeFp> cellValue;
  final int numWords;
  const SinsemillaMessagePiece(this.cellValue, this.numWords);
  factory SinsemillaMessagePiece.fromFieldElem(
      {required SinsemillaConfig chip,
      required Layouter layouter,
      required PallasNativeFp? fieldElem,
      required int numWords}) {
    return chip.witnessMessagePiece(layouter, fieldElem, numWords);
  }
  factory SinsemillaMessagePiece.fromSubpieces(
      {required SinsemillaConfig chip,
      required Layouter layouter,
      required List<RangeConstrained<PallasNativeFp?>> subpieces}) {
    PallasNativeFp fieldElem = PallasNativeFp.zero();
    int totalBits = 0;

    for (final subpiece in subpieces) {
      if (totalBits >= 64) {
        throw Halo2Exception.operationFailed("fromSubpieces",
            reason: "Too many accumulated bits.");
      }
      final f = subpiece.inner;
      if (f != null) {
        final shift = PallasNativeFp(BigInt.one << totalBits) * f;
        fieldElem = fieldElem + shift;
      }
      totalBits += subpiece.numBits;
    }

    // SinsemillaMessage must be composed of K-bit words.
    if (totalBits % HashDomainConst.K != 0) {
      throw Halo2Exception.operationFailed("fromSubpieces",
          reason: "SinsemillaMessage bit-length not divisible by K.");
    }

    final int numWords = totalBits ~/ HashDomainConst.K;
    return SinsemillaMessagePiece.fromFieldElem(
        chip: chip,
        layouter: layouter,
        fieldElem: fieldElem,
        numWords: numWords);
  }
}

class SinsemillaMessage {
  final List<SinsemillaMessagePiece> messages;
  const SinsemillaMessage(this.messages);
}
