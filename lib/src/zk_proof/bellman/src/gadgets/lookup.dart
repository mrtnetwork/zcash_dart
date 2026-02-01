import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/boolean.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/num.dart';

class GLookupUtils {
  /// Synthesize constants for each base pattern
  static void synth(int windowSize, Iterable<JubJubNativeFq> constants,
      List<JubJubNativeFq> assignment) {
    if (assignment.length != (1 << windowSize)) {
      throw ArgumentException.invalidOperationArguments("synth",
          reason: "Assignment length must be ${2 ^ windowSize}.");
    }

    for (int i = 0; i < constants.length; i++) {
      JubJubNativeFq constant = constants.elementAt(i);
      JubJubNativeFq cur = -assignment[i] + constant;
      assignment[i] = cur;
      for (int j = i + 1; j < assignment.length; j++) {
        if ((j & i) == i) {
          assignment[j] += cur;
        }
      }
    }
  }

  /// Performs a 3-bit window table lookup
  static (GAllocatedNum, GAllocatedNum) lookup3XY(BellmanConstraintSystem cs,
      List<GBoolean> bits, List<(JubJubNativeFq, JubJubNativeFq)> coords) {
    if (bits.length != 3 || coords.length != 8) {
      throw BellmanException.operationFailed("lookup3XY",
          reason: "Invalid input length.");
    }

    int? i;
    if (bits[0].hasValue && bits[1].hasValue && bits[2].hasValue) {
      i = 0;
      if (bits[0].getValue()) i += 1;
      if (bits[1].getValue()) i += 2;
      if (bits[2].getValue()) i += 4;
    }

    final resX = GAllocatedNum.alloc(cs, () {
      if (i == null) {
        throw BellmanException.operationFailed("lookup3XY",
            reason: "GIndex not available for x.");
      }
      return coords[i].$1;
    });

    final resY = GAllocatedNum.alloc(cs, () {
      if (i == null) {
        throw BellmanException.operationFailed("lookup3XY",
            reason: "GIndex not available for y.");
      }
      return coords[i].$2;
    });

    final xCoeffs = List<JubJubNativeFq>.filled(8, JubJubNativeFq.zero());
    final yCoeffs = List<JubJubNativeFq>.filled(8, JubJubNativeFq.zero());
    synth(3, coords.map((c) => c.$1), xCoeffs);
    synth(3, coords.map((c) => c.$2), yCoeffs);

    final precomp = GBoolean.and(cs, bits[1], bits[2]);

    final one = cs.one();

    cs.enforce(
      (lc) =>
          lc +
          (xCoeffs[1], one) +
          bits[1].lc(one, xCoeffs[3]) +
          bits[2].lc(one, xCoeffs[5]) +
          precomp.lc(one, xCoeffs[7]),
      (lc) => lc + bits[0].lc(one, JubJubNativeFq.one()),
      (lc) =>
          lc +
          resX.variable -
          (xCoeffs[0], one) -
          bits[1].lc(one, xCoeffs[2]) -
          bits[2].lc(one, xCoeffs[4]) -
          precomp.lc(one, xCoeffs[6]),
    );

    cs.enforce(
        (lc) =>
            lc +
            (yCoeffs[1], one) +
            bits[1].lc(one, yCoeffs[3]) +
            bits[2].lc(one, yCoeffs[5]) +
            precomp.lc(one, yCoeffs[7]),
        (lc) => lc + bits[0].lc(one, JubJubNativeFq.one()),
        (lc) =>
            lc +
            resY.variable -
            (yCoeffs[0], one) -
            bits[1].lc(one, yCoeffs[2]) -
            bits[2].lc(one, yCoeffs[4]) -
            precomp.lc(one, yCoeffs[6]));

    return (resX, resY);
  }

  /// Performs a 3-bit window table lookup with conditional negation
  static (GNum, GNum) lookup3XYWithConditionalNegation(
      BellmanConstraintSystem cs,
      List<GBoolean> bits,
      List<(JubJubNativeFq, JubJubNativeFq)> coords) {
    if (bits.length != 3 || coords.length != 4) {
      throw BellmanException.operationFailed("lookup3XYWithConditionalNegation",
          reason: "Invalid input length.");
    }

    int? i;
    if (bits[0].hasValue && bits[1].hasValue) {
      i = 0;
      if (bits[0].getValue()) i += 1;
      if (bits[1].getValue()) i += 2;
    }

    final y = GAllocatedNum.alloc(cs, () {
      if (i == null) {
        throw BellmanException.operationFailed(
            "lookup3XYWithConditionalNegation",
            reason: "GIndex not available for y.");
      }
      JubJubNativeFq tmp = coords[i].$2;
      if (bits[2].hasValue && bits[2].getValue()) {
        tmp = -tmp;
      }
      return tmp;
    });

    final one = cs.one();

    final xCoeffs = List<JubJubNativeFq>.filled(4, JubJubNativeFq.zero());
    final yCoeffs = List<JubJubNativeFq>.filled(4, JubJubNativeFq.zero());
    synth(2, coords.map((c) => c.$1), xCoeffs);
    synth(2, coords.map((c) => c.$2), yCoeffs);

    final precomp = GBoolean.and(cs, bits[0], bits[1]);

    final x = GNum.zero()
        .addBoolWithCoeff(one, GBooleanConstant(true), xCoeffs[0])
        .addBoolWithCoeff(one, bits[0], xCoeffs[1])
        .addBoolWithCoeff(one, bits[1], xCoeffs[2])
        .addBoolWithCoeff(one, precomp, xCoeffs[3]);

    final yLc = precomp.lc(one, yCoeffs[3]) +
        bits[1].lc(one, yCoeffs[2]) +
        bits[0].lc(one, yCoeffs[1]) +
        (yCoeffs[0], one);

    cs.enforce(
        (lc) => lc + yLc + yLc,
        (lc) => lc + bits[2].lc(one, JubJubNativeFq.one()),
        (lc) => lc + yLc - y.variable);

    return (x, GNum.fromAllocatedNum(y));
  }
}
