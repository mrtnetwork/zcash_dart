import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';
import 'package:zcash_dart/src/pedersen_hash/src/constants.dart';
import 'package:zcash_dart/src/sapling/utils/utils.dart';

class SaplingCircuitConstants {
  static List<List<(JubJubNativeFq, JubJubNativeFq)>>
      proofGeneratorKeyGenerator() {
    return generateCircuitGenerator(
        SaplingUtils.proofGenerationKeyGeneratorNative);
  }

  static List<List<(JubJubNativeFq, JubJubNativeFq)>>
      noteCommitmentRandomnessGenerator() {
    return generateCircuitGenerator(
        SaplingUtils.noteCommitmentRandomnessGeneratorNative);
  }

  static List<List<(JubJubNativeFq, JubJubNativeFq)>>
      nullifierPositionGenerator() {
    return generateCircuitGenerator(
        SaplingUtils.nullifierPositionGeneratorNative);
  }

  static List<List<(JubJubNativeFq, JubJubNativeFq)>>
      valueCommitmentValueGenerator() {
    return generateCircuitGenerator(
        SaplingUtils.valueCommitmentValueGeneratorNative);
  }

  static List<List<(JubJubNativeFq, JubJubNativeFq)>>
      valueCommitmentRandomnessGenerator() {
    return generateCircuitGenerator(
        SaplingUtils.valueCommitmentRandomnessGeneratorNative);
  }

  static List<List<(JubJubNativeFq, JubJubNativeFq)>> spendingKeyGenerator() {
    return generateCircuitGenerator(SaplingUtils.spendingKeyGeneratorNative);
  }

  static List<List<(JubJubNativeFq, JubJubNativeFq)>> generateCircuitGenerator(
      JubJubNativePoint gen) {
    const int chunkPerGenerator = 84;
    List<List<(JubJubNativeFq, JubJubNativeFq)>> windows = [];
    for (int i = 0; i < chunkPerGenerator; i++) {
      final List<(JubJubNativeFq, JubJubNativeFq)> coeffs = [
        (JubJubNativeFq.zero(), JubJubNativeFq.one())
      ];
      JubJubNativePoint g = gen;
      for (int j = 0; j < 7; j++) {
        final gAffine = g.toAffine();
        coeffs.add((gAffine.u, gAffine.v));
        g += gen;
      }
      windows.add(coeffs);
      gen = g;
    }
    return windows;
  }

  static (JubJubNativeFq, JubJubNativeFq)? toMontgomeryCoords(
      JubJubNativePoint g) {
    final affine = g.toAffine();
    final x = affine.u;
    final y = affine.v;

    if (y == JubJubNativeFq.one()) {
      // The only solution for y = 1 is x = 0. (0, 1) is the neutral element,
      // so we map this to the point at infinity.
      return null;
    } else {
      // The map from a twisted Edwards curve is defined as
      // (x, y) -> (u, v) where
      //      u = (1 + y) / (1 - y)
      //      v = u / x
      //
      // This mapping is not defined for y = 1 and for x = 0.
      //
      // We have that y != 1 above. If x = 0, the only
      // solutions for y are 1 (contradiction) or -1.
      if (x.isZero()) {
        // (0, -1) is the point of order two which is not
        // the neutral element, so we map it to (0, 0) which is
        // the only affine point of order 2.
        return (JubJubNativeFq.zero(), JubJubNativeFq.zero());
      } else {
        // The mapping is defined as above.
        //
        // (x, y) -> (u, v) where
        //      u = (1 + y) / (1 - y)
        //      v = u / x
        final one = JubJubNativeFq.one();
        final yInv = (one - y).invert();
        final xInv = x.invert();
        if (yInv == null || xInv == null) {
          throw BellmanException.operationFailed("toMontgomeryCoords",
              reason: "Division by zero.");
        }
        final u = (one + y) * yInv;
        final v = u * xInv;

        // AstScale it into the correct curve constants
        // scaling factor = sqrt(4 / (a - d))
        return (u, v * JubJubNativeFq.montgomeryScale());
      }
    }
  }

  static List<List<List<(JubJubNativeFq, JubJubNativeFq)>>>
      generatePedersenCircuitGenerators() {
    const chunkPerGenerator = 63;
    final generator =
        PedersenUtils.generateHash<JubJubNativeFr, JubJubNativePoint>(
            (bytes) => JubJubNativePoint.fromBytes(bytes));
    // Process each segment
    return generator.map((gen0) {
      var gen = gen0; // cloned
      final List<List<(JubJubNativeFq, JubJubNativeFq)>> windows = [];

      for (var i = 0; i < chunkPerGenerator; i++) {
        // Create (x, y) coeffs for this chunk
        final List<(JubJubNativeFq, JubJubNativeFq)> coeffs = [];
        var g = gen;

        // coeffs = g, g*2, g*3, g*4
        for (var j = 0; j < 4; j++) {
          final coords = toMontgomeryCoords(g);
          if (coords == null) {
            throw BellmanException.operationFailed(
                "generatePedersenCircuitGenerators",
                reason: "we never encounter the point at infinity");
          }
          coeffs.add(coords);
          g = g + gen;
        }

        windows.add(coeffs);

        // Our chunks are separated by 2 bits to prevent overlap.
        for (var j = 0; j < 4; j++) {
          gen = gen.double();
        }
      }

      return windows;
    }).toList();
  }
}
