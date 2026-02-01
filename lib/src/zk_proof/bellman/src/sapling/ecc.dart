import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/boolean.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/lookup.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/num.dart';

class GEdwardsUtils {
  static GEdwardsPoint fixedBaseMultiplication(BellmanConstraintSystem cs,
      List<List<(JubJubNativeFq, JubJubNativeFq)>> base, List<GBoolean> by) {
    GEdwardsPoint? result;
    int windowIndex = 0;
    for (int i = 0; i < by.length; i += 3) {
      final chunkA = by.elementAtOrNull(i) ?? GBooleanConstant(false);

      final chunkB = by.elementAtOrNull(i + 1) ?? GBooleanConstant(false);

      final chunkC = by.elementAtOrNull(i + 2) ?? GBooleanConstant(false);

      final window = base[windowIndex];
      final (u, v) =
          GLookupUtils.lookup3XY(cs, [chunkA, chunkB, chunkC], window);

      final p = GEdwardsPoint(u: u, v: v);
      if (result == null) {
        result = p;
      } else {
        result = result.add(cs, p);
      }

      windowIndex++;
    }

    if (result == null) {
      throw ArgumentException.invalidOperationArguments(
          "fixedBaseMultiplication",
          reason: "Invalid input length.");
    }

    return result;
  }
}

class GEdwardsPoint {
  final GAllocatedNum u;
  final GAllocatedNum v;
  const GEdwardsPoint({required this.u, required this.v});
  void assertNotSmallOrder(BellmanConstraintSystem cs) {
    var tmp = double(cs);
    tmp = tmp.double(cs);
    tmp = tmp.double(cs);
    tmp.u.assertNonZero(cs);
  }

  void inputize(BellmanConstraintSystem cs) {
    u.inputize(cs);
    v.inputize(cs);
  }

  List<GBoolean> repr(BellmanConstraintSystem cs) {
    List<GBoolean> tmp = [];

    // Unpack u into bits (little-endian)
    List<GBoolean> uBits = u.toBitsLeStrict(cs);

    // Unpack v into bits (little-endian)
    List<GBoolean> vBits = v.toBitsLeStrict(cs);

    // Extend tmp with v bits, then append the least significant bit of u
    tmp.addAll(vBits);
    tmp.add(uBits[0]);

    return tmp;
  }

  factory GEdwardsPoint.interpret(
      BellmanConstraintSystem cs, GAllocatedNum u, GAllocatedNum v) {
    // -u^2 + v^2 = 1 + d * u^2 * v^2

    // Compute u^2
    final u2 = u.square(cs);

    // Compute v^2
    final v2 = v.square(cs);

    // Compute u^2 * v^2
    final u2v2 = u2.mul(cs, v2);

    final one = cs.one(); // assuming scalars are BigInt
    cs.enforce((lc) => lc - u2.variable + v2.variable, (lc) => lc + one,
        (lc) => lc + one + (JubJubNativeFq.edwardsD(), u2v2.variable));

    return GEdwardsPoint(u: u, v: v);
  }

  GEdwardsPoint double(BellmanConstraintSystem cs) {
    // Compute T = (u + v) * (v - EDWARDS_A*u)
    //           = (u + v) * (u + v)
    final t = GAllocatedNum.alloc(cs, () {
      JubJubNativeFq t0 = u.getValue();
      t0 += v.getValue();

      JubJubNativeFq t1 = u.getValue();
      t1 += v.getValue();

      t0 *= t1;

      return t0;
    });

    cs.enforce((lc) => lc + u.variable + v.variable,
        (lc) => lc + u.variable + v.variable, (lc) => lc + t.variable);

    // Compute A = u * v
    final a = u.mul(cs, v);

    // Compute C = d * A * A
    final c = GAllocatedNum.alloc(cs, () {
      JubJubNativeFq t0 = a.getValue() * a.getValue(); // square
      t0 *= JubJubNativeFq.edwardsD();
      return t0;
    });

    cs.enforce((lc) => lc + (JubJubNativeFq.edwardsD(), a.variable),
        (lc) => lc + a.variable, (lc) => lc + c.variable);

    // Compute u3 = (2 * A) / (1 + C)
    final u3 = GAllocatedNum.alloc(cs, () {
      final t0 = a.getValue() * JubJubNativeFq.from(2);

      final t1 = JubJubNativeFq.one() + c.getValue();
      final res = t1.invert();
      if (res != null) {
        return t0 * res;
      } else {
        throw BellmanException.operationFailed("double",
            reason: "Division by zero.");
      }
    });

    final one = cs.one();
    cs.enforce((lc) => lc + one + c.variable, (lc) => lc + u3.variable,
        (lc) => lc + a.variable + a.variable);

    // Compute v3 = (T + (EDWARDS_A-1)*A) / (1 - C)
    //            = (T - 2*A) / (1 - C)
    final v3 = GAllocatedNum.alloc(cs, () {
      JubJubNativeFq t0 = -a.getValue() * JubJubNativeFq.from(2);
      t0 += t.getValue();

      final t1 = JubJubNativeFq.one() - c.getValue();
      final res = t1.invert();
      if (res != null) {
        return t0 * res;
      } else {
        throw BellmanException.operationFailed("double",
            reason: "Division by zero.");
      }
    });
    cs.enforce((lc) => lc + one - c.variable, (lc) => lc + v3.variable,
        (lc) => lc + t.variable - a.variable - a.variable);
    return GEdwardsPoint(u: u3, v: v3);
  }

  GEdwardsPoint add(BellmanConstraintSystem cs, GEdwardsPoint other) {
    // Compute U = (u1 + v1) * (u2 + v2)
    final uppercaseU = GAllocatedNum.alloc(cs, () {
      JubJubNativeFq t0 = u.getValue();
      t0 += v.getValue();
      JubJubNativeFq t1 = other.u.getValue();
      t1 += other.v.getValue();
      t0 *= t1;
      return t0;
    });
    cs.enforce(
      (lc) => lc + u.variable + v.variable,
      (lc) => lc + other.u.variable + other.v.variable,
      (lc) => lc + uppercaseU.variable,
    );
    // Compute A = v2 * u1
    final a = other.v.mul(cs, u);
    // Compute B = u2 * v1
    final b = other.u.mul(cs, v);

    // Compute C = d * A * B
    final c = GAllocatedNum.alloc(cs, () {
      JubJubNativeFq t0 = a.getValue();
      t0 *= b.getValue();
      t0 *= JubJubNativeFq.edwardsD();
      return t0;
    });

    cs.enforce(
      (lc) => lc + (JubJubNativeFq.edwardsD(), a.variable),
      (lc) => lc + b.variable,
      (lc) => lc + c.variable,
    );

    // Compute u3 = (A + B) / (1 + C)
    final u3 = GAllocatedNum.alloc(cs, () {
      final t0 = a.getValue() + b.getValue();
      final t1 = JubJubNativeFq.one() + c.getValue();
      final ret = t1.invert();
      if (ret != null) {
        return t0 * ret;
      } else {
        throw BellmanException.operationFailed("add",
            reason: "Division by zero.");
      }
    });
    final one = cs.one();
    cs.enforce((lc) => lc + one + c.variable, (lc) => lc + u3.variable,
        (lc) => lc + a.variable + b.variable);
    // Compute v3 = (U - A - B) / (1 - C)
    final v3 = GAllocatedNum.alloc(cs, () {
      final t0 = uppercaseU.getValue() - a.getValue() - b.getValue();
      final t1 = JubJubNativeFq.one() - c.getValue();

      final res = t1.invert();
      if (res != null) {
        return t0 * res;
      } else {
        throw BellmanException.operationFailed("add",
            reason: "Division by zero.");
      }
    });
    cs.enforce((lc) => lc + one - c.variable, (lc) => lc + v3.variable,
        (lc) => lc + uppercaseU.variable - a.variable - b.variable);
    return GEdwardsPoint(u: u3, v: v3);
  }

  GEdwardsPoint mul(
    BellmanConstraintSystem cs,
    List<GBoolean> by,
  ) {
    GEdwardsPoint? curBase;
    GEdwardsPoint? result;

    for (int i = 0; i < by.length; i++) {
      final bit = by[i];

      // Initialize curBase or double it
      if (curBase == null) {
        curBase = this;
      } else {
        curBase = curBase.double(cs);
      }

      // Conditionally select curBase based on bit
      final thisBase = curBase.conditionallySelect(cs, bit);

      // Accumulate into result
      if (result == null) {
        result = thisBase;
      } else {
        result = result.add(cs, thisBase);
      }
    }

    if (result == null) {
      throw BellmanException.operationFailed("add",
          reason: "Invalid input length.");
    }

    return result;
  }

  GEdwardsPoint conditionallySelect(
    BellmanConstraintSystem cs,
    GBoolean condition,
  ) {
    // Compute u' = self.u if condition, else 0
    final uPrime = GAllocatedNum.alloc(cs, () {
      if (condition.getValue()) {
        return u.getValue();
      } else {
        return JubJubNativeFq.zero();
      }
    });

    // Enforce: condition * u = u'
    final one = cs.one();
    cs.enforce(
        (lc) => lc + u.variable,
        (_) => condition.lc(one, JubJubNativeFq.one()),
        (lc) => lc + uPrime.variable);

    // Compute v' = self.v if condition, else 1
    final vPrime = GAllocatedNum.alloc(cs, () {
      if (condition.getValue()) {
        return v.getValue();
      } else {
        return JubJubNativeFq.one();
      }
    });

    // Enforce: condition * v = v' - (1 - condition)
    cs.enforce(
        (lc) => lc + v.variable,
        (_) => condition.lc(one, JubJubNativeFq.one()),
        (lc) =>
            lc +
            vPrime.variable -
            condition.not().lc(one, JubJubNativeFq.one()));

    return GEdwardsPoint(u: uPrime, v: vPrime);
  }

  factory GEdwardsPoint.witness(
      BellmanConstraintSystem cs, JubJubNativePoint? p) {
    // Convert to affine if p is not null
    final affineP = p?.toAffine();

    // Allocate u
    final u = GAllocatedNum.alloc(cs, () {
      if (affineP != null) {
        return affineP.u;
      } else {
        throw BellmanException.operationFailed("witness");
      }
    });

    // Allocate v
    final v = GAllocatedNum.alloc(cs, () {
      if (affineP != null) {
        return affineP.v;
      } else {
        throw BellmanException.operationFailed("witness");
      }
    });

    // Interpret the point on curve
    return GEdwardsPoint.interpret(cs, u, v);
  }
}

class GMontgomeryPoint {
  final GNum x;
  final GNum y;
  const GMontgomeryPoint(this.x, this.y);
  GEdwardsPoint intoEdwards(BellmanConstraintSystem cs) {
    final JubJubNativeFq montgomeryScale = JubJubNativeFq.montgomeryScale();
    final u = GAllocatedNum.alloc(cs, () {
      final t0 = x.getValue() * montgomeryScale;

      final yValue = y.getValue();
      final ret = yValue.invert();
      if (ret == null) {
        throw BellmanException.operationFailed("intoEdwards",
            reason: "Division by zero.");
      }

      return t0 * ret;
    });

    cs.enforce(
      (lc) => lc + y.lcMul(JubJubNativeFq.one()),
      (lc) => lc + u.variable,
      (lc) => lc + x.lcMul(montgomeryScale),
    );

    // Compute v = (x - 1) / (x + 1)
    final v = GAllocatedNum.alloc(cs, () {
      final t0 = x.getValue() - JubJubNativeFq.one();
      final t1 = x.getValue() + JubJubNativeFq.one();
      final ret = t1.invert();
      if (ret == null) {
        throw BellmanException.operationFailed("intoEdwards",
            reason: "Division by zero.");
      }

      return t0 * ret;
    });

    final one = cs.one();
    cs.enforce(
      (lc) => lc + x.lcMul(JubJubNativeFq.one()) + one,
      (lc) => lc + v.variable,
      (lc) => lc + x.lcMul(JubJubNativeFq.one()) - one,
    );

    return GEdwardsPoint(u: u, v: v);
  }

  GMontgomeryPoint add(
    BellmanConstraintSystem cs,
    GMontgomeryPoint other,
  ) {
    final montgomeryA = JubJubNativeFq.montgomeryA();
    // Compute lambda = (y' - y) / (x' - x)
    final lambda = GAllocatedNum.alloc(cs, () {
      JubJubNativeFq n = other.y.getValue() - y.getValue();
      JubJubNativeFq d = other.x.getValue() - x.getValue();

      final ret = d.invert();
      if (ret == null) {
        throw BellmanException.operationFailed("add",
            reason: "Division by zero.");
      }
      return n * ret;
    });
    final scOne = JubJubNativeFq.one();
    cs.enforce(
        (lc) => lc + other.x.lcMul(scOne) - x.lcMul(scOne),
        (lc) => lc + lambda.variable,
        (lc) => lc + other.y.lcMul(scOne) - y.lcMul(scOne));

    // Compute x'' = lambda^2 - A - x - x'
    final xprime = GAllocatedNum.alloc(cs, () {
      JubJubNativeFq t0 = lambda.getValue() * lambda.getValue();
      t0 -= montgomeryA;
      t0 -= x.getValue();
      t0 -= other.x.getValue();
      return t0;
    });

    // Enforce lambda^2 = A + x + x' + x''
    final one = cs.one();
    cs.enforce(
        (lc) => lc + lambda.variable,
        (lc) => lc + lambda.variable,
        (lc) =>
            lc +
            (montgomeryA, one) +
            x.lcMul(scOne) +
            other.x.lcMul(scOne) +
            xprime.variable);

    // Compute y' = -(y + lambda * (x' - x))
    final yprime = GAllocatedNum.alloc(cs, () {
      var t0 = xprime.getValue() - x.getValue();
      t0 *= lambda.getValue();
      t0 += y.getValue();
      t0 = -t0;
      return t0;
    });

    // Enforce y' + y = lambda * (x' - x)
    cs.enforce(
      (lc) => lc + x.lcMul(scOne) - xprime.variable,
      (lc) => lc + lambda.variable,
      (lc) => lc + yprime.variable + y.lcMul(scOne),
    );

    return GMontgomeryPoint(
        GNum.fromAllocatedNum(xprime), GNum.fromAllocatedNum(yprime));
  }
}
