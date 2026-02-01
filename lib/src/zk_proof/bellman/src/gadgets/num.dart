import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/variable.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/boolean.dart';

class GAllocatedNum {
  final JubJubNativeFq? value;
  final GVariable variable;
  const GAllocatedNum(this.value, this.variable);
  JubJubNativeFq getValue() {
    final value = this.value;
    if (value == null) {
      throw BellmanException.operationFailed("getValue",
          reason: "Missing value.");
    }
    return value;
  }

  /// Allocate a new number in the constraint system
  factory GAllocatedNum.alloc(
      BellmanConstraintSystem cs, JubJubNativeFq Function() valueFn) {
    JubJubNativeFq? newValue;
    final varAllocated = cs.alloc(
      () {
        final tmp = valueFn();
        newValue = tmp;
        return tmp;
      },
    );

    return GAllocatedNum(newValue, varAllocated);
  }

  void inputize(BellmanConstraintSystem cs) {
    if (value == null) {
      throw BellmanException.operationFailed("inputize",
          reason: "Cannot inputize a GAllocatedNum with no value.");
    }
    final inputVar = cs.allocInput(() => value!);
    cs.enforce(
        (lc) => lc + inputVar, (lc) => lc + cs.one(), (lc) => lc + variable);
  }

  /// Converts this number into little-endian bit representation,
  /// strictly enforcing that the number is within field range.
  List<GBoolean> toBitsLeStrict(BellmanConstraintSystem cs) {
    if (value == null) {
      throw BellmanException.operationFailed("toBitsLeStrict",
          reason: "Cannot convert a GAllocatedNum with no value to bits.");
    }

    /// Helper: k-ary AND of a list of bits
    GAllocatedBit karyAnd(
        BellmanConstraintSystem cs, List<GAllocatedBit> bits) {
      if (bits.isEmpty) {
        throw BellmanException.operationFailed("toBitsLeStrict");
      }
      GAllocatedBit cur = bits.first;
      for (int i = 1; i < bits.length; i++) {
        cur = GAllocatedBit.and(cs, cur, bits[i]);
      }
      return cur;
    }

    final fieldBits = JubJubFqConst.bits; // total number of bits in the field
    final aBits = value!.toBits(); // little-endian bits of self.value
    final bBits = (-JubJubNativeFq.one()).toBits();

    List<GAllocatedBit> result = [];
    List<GAllocatedBit> currentRun = [];
    GAllocatedBit? lastRun;
    bool foundOne = false;

    for (int i = fieldBits - 1; i >= 0; i--) {
      final aBitVal = aBits[i];
      final bBit = bBits[i];

      // Skip initial zeros before the first '1' in modulus
      foundOne |= bBit;
      if (!foundOne) {
        if (aBitVal) {
          throw BellmanException.operationFailed("toBitsLeStrict",
              reason: "Bit exceeds field size.");
        }
        continue;
      }

      if (bBit) {
        final bit = GAllocatedBit.alloc(cs: cs, value: aBitVal);
        currentRun.add(bit);
        result.add(bit);
      } else {
        if (currentRun.isNotEmpty) {
          if (lastRun != null) {
            currentRun.add(lastRun);
          }
          lastRun = karyAnd(cs, currentRun);
          currentRun.clear();
        }

        final bit = GAllocatedBit.allocConditionally(
            cs: cs, value: aBitVal, mustBeFalse: lastRun!);
        result.add(bit);
      }
    }
    if (currentRun.isNotEmpty) {
      throw BellmanException.operationFailed("toBitsLeStrict");
    }

    // Reconstruct linear combination to enforce equality with self.variable
    LinearCombination lc = LinearCombination.zero();
    JubJubNativeFq coeff = JubJubNativeFq.one();

    for (final bit in result.reversed) {
      lc = lc + (coeff, bit.variable);
      coeff = coeff.double();
    }
    lc = lc - variable;
    cs.enforce((lc) => lc, (lc) => lc, (_) => lc);
    return result.map((bit) => GBooleanIs(bit)).toList().reversed.toList();
  }

  List<GBoolean> toBitsLe(BellmanConstraintSystem cs) {
    if (value == null) {
      throw BellmanException.operationFailed("toBitsLe",
          reason: "Cannot convert a GAllocatedNum with no value to bits");
    }

    // Convert the value into little-endian bits
    final bits = GBooleanUtils.fieldToBits(cs, value, JubJubFqConst.bits);

    // Reconstruct linear combination to enforce equality with self.variable
    LinearCombination lc = LinearCombination.zero();
    JubJubNativeFq coeff = JubJubNativeFq.one();

    for (final bit in bits) {
      lc = lc + (coeff, bit.variable);
      coeff = coeff.double();
    }

    lc = lc - variable;

    cs.enforce((lc) => lc, (lc) => lc, (_) => lc);

    // Convert AllocatedBit into GBoolean for consistency
    return bits.map((bit) => GBooleanIs(bit)).toList();
  }

  /// Multiply two allocated numbers and constrain the result in the CS
  GAllocatedNum mul(BellmanConstraintSystem cs, GAllocatedNum other) {
    JubJubNativeFq? newValue;

    // Allocate the product variable
    final productVar = cs.alloc(
      () {
        final tmp = getValue() * other.getValue();
        newValue = tmp;
        return tmp;
      },
    );

    // Enforce multiplication constraint: a * b = product
    cs.enforce((lc) => lc + variable, (lc) => lc + other.variable,
        (lc) => lc + productVar);

    return GAllocatedNum(newValue, productVar);
  }

  /// Squares this allocated number and enforces the constraint in the CS
  GAllocatedNum square(BellmanConstraintSystem cs) {
    JubJubNativeFq? newValue;

    // Allocate the squared variable
    final squaredVar = cs.alloc(
      () {
        final tmp = getValue().square();
        newValue = tmp;
        return tmp;
      },
    );

    // Enforce: a * a = squared
    cs.enforce(
        (lc) => lc + variable, (lc) => lc + variable, (lc) => lc + squaredVar);

    return GAllocatedNum(newValue, squaredVar);
  }

  void assertNonZero(BellmanConstraintSystem cs) {
    final value = getValue();

    // Allocate an ephemeral inverse variable
    final invVar = cs.alloc(
      () {
        if (value.isZero()) {
          throw BellmanException.operationFailed("assertNonZero",
              reason: "Division by zero.");
        }
        final inv = value.invert();
        if (inv == null) {
          throw BellmanException.operationFailed("assertNonZero",
              reason: "Division by zero.");
        }
        return inv;
      },
    );

    cs.enforce(
        (lc) => lc + variable, (lc) => lc + invVar, (lc) => lc + cs.one());
  }

  static (GAllocatedNum, GAllocatedNum) conditionallyReverse(
    BellmanConstraintSystem cs,
    GAllocatedNum a,
    GAllocatedNum b,
    GBoolean condition,
  ) {
    final c = GAllocatedNum.alloc(
      cs,
      () {
        if (!condition.hasValue) {
          throw BellmanException.operationFailed("conditionallyReverse",
              reason: "Condition value missing");
        }
        return condition.getValue() ? b.getValue() : a.getValue();
      },
    );
    cs.enforce(
        (lc) => lc + a.variable - b.variable,
        (lc) => lc + condition.lc(cs.one(), JubJubNativeFq.one()),
        (lc) => lc + a.variable - c.variable);

    final d = GAllocatedNum.alloc(cs, () {
      if (!condition.hasValue) {
        throw BellmanException.operationFailed("conditionallyReverse",
            reason: "Condition value missing");
      }
      return condition.getValue() ? a.getValue() : b.getValue();
    });
    cs.enforce(
        (lc) => lc + b.variable - a.variable,
        (lc) => lc + condition.lc(cs.one(), JubJubNativeFq.one()),
        (lc) => lc + b.variable - d.variable);

    return (c, d);
  }
}

class GNum {
  final JubJubNativeFq? value;
  final LinearCombination lc;

  const GNum({required this.value, required this.lc});

  /// Construct from a GAllocatedNum
  factory GNum.fromAllocatedNum(GAllocatedNum num) {
    return GNum(value: num.value, lc: LinearCombination.zero() + num.variable);
  }

  /// Zero element
  factory GNum.zero() {
    return GNum(value: JubJubNativeFq.zero(), lc: LinearCombination.zero());
  }

  bool get hasValue => value != null;

  JubJubNativeFq getValue() {
    final value = this.value;
    if (value == null) {
      throw BellmanException.operationFailed("getValue",
          reason: "Value missing.");
    }
    return value;
  }

  /// Multiply the linear combination by a scalar
  LinearCombination lcMul(JubJubNativeFq coeff) {
    return LinearCombination.zero() + (coeff, lc);
  }

  /// AstAdd a boolean with a coefficient
  GNum addBoolWithCoeff(GVariable one, GBoolean bit, JubJubNativeFq coeff) {
    JubJubNativeFq? newValue;
    if (value != null && bit.hasValue) {
      final v = getValue();
      newValue = bit.getValue() ? v + coeff : v;
    }
    return GNum(value: newValue, lc: lc + bit.lc(one, coeff));
  }
}
