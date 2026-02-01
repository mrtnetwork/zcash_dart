import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/variable.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';

class GBooleanUtils {
  static List<GBoolean> u64ToBits(BellmanConstraintSystem cs, BigInt? value) {
    final values = List<bool?>.generate(64, (i) {
      if (value == null) return null;
      return ((value >> i) & BigInt.one) == BigInt.one;
    });

    final bits = <GBoolean>[];
    for (int i = 0; i < 64; i++) {
      final bit = GAllocatedBit.alloc(cs: cs, value: values[i]);
      bits.add(GBooleanIs(bit));
    }

    return bits;
  }

  /// Converts a field element into a little-endian vector of booleans
  static List<GBoolean> fqToBits(
      BellmanConstraintSystem cs, JubJubNativeFq? value) {
    final allocatedBits =
        fieldToBits<JubJubNativeFq>(cs, value, JubJubFqConst.bits);
    return allocatedBits.map((b) => GBooleanIs(b)).toList();
  }

  static List<GBoolean> frToBits(
      BellmanConstraintSystem cs, JubJubNativeFr? value) {
    final allocatedBits =
        fieldToBits<JubJubNativeFr>(cs, value, JubJubFrConst.bits);
    return allocatedBits.map((b) => GBooleanIs(b)).toList();
  }

  static List<GAllocatedBit> fieldToBits<F extends JubJubPrimeField<F>>(
      BellmanConstraintSystem cs, F? value, int numBits) {
    final List<bool?> values;

    if (value != null) {
      values = [];
      final leBits = value.toBits().reversed.toList();
      final charBits = value.charBits();
      final Iterator<bool> fieldChar = charBits.reversed.iterator;
      bool foundOne = false;
      for (final bool b in leBits) {
        fieldChar.moveNext();
        foundOne = foundOne || fieldChar.current;
        if (!foundOne) {
          continue;
        }
        values.add(b);
      }
      assert(values.length == numBits);
    } else {
      values = List<bool?>.filled(numBits, null);
    }
    final List<GAllocatedBit> bits = [];
    final Iterable<bool?> reversedValues = values.reversed;
    for (final bool? b in reversedValues) {
      bits.add(GAllocatedBit.alloc(cs: cs, value: b));
    }

    return bits;
  }
}

class GAllocatedBit with Equality {
  final GVariable variable;
  final bool? value;
  const GAllocatedBit(this.variable, this.value);
  factory GAllocatedBit.alloc(
      {required BellmanConstraintSystem cs, required bool? value}) {
    final v = cs.alloc(() {
      if (value == null) {
        throw ArgumentException.invalidOperationArguments("alloc",
            reason: "Missing value.");
      }
      return value ? JubJubNativeFq.one() : JubJubNativeFq.zero();
    });
    cs.enforce((lc) => lc + cs.one() - v, (lc) => lc + v, (lc) => lc);
    return GAllocatedBit(v, value);
  }

  bool getValue() {
    final value = this.value;
    if (value == null) {
      throw BellmanException.operationFailed("getValue",
          reason: "Value missing.");
    }
    return value;
  }

  /// Allocate a boolean variable conditionally
  factory GAllocatedBit.allocConditionally(
      {required BellmanConstraintSystem cs,
      required bool? value,
      required GAllocatedBit mustBeFalse}) {
    final v = cs.alloc(
      () {
        if (value == null) {
          throw ArgumentException.invalidOperationArguments(
              "allocConditionally",
              reason: "Missing value.");
        }
        return value ? JubJubNativeFq.one() : JubJubNativeFq.zero();
      },
    );
    cs.enforce((lc) => lc + cs.one() - mustBeFalse.variable - v, (lc) => lc + v,
        (lc) => lc);
    return GAllocatedBit(v, value);
  }

  /// XOR operation: returns a new allocated bit
  factory GAllocatedBit.xor(
      BellmanConstraintSystem cs, GAllocatedBit a, GAllocatedBit b) {
    bool? resultValue;
    final v = cs.alloc(
      () {
        resultValue = a.getValue() ^ b.getValue();
        return resultValue! ? JubJubNativeFq.one() : JubJubNativeFq.zero();
      },
    );
    cs.enforce((lc) => lc + a.variable + a.variable, (lc) => lc + b.variable,
        (lc) => lc + a.variable + b.variable - v);
    return GAllocatedBit(v, resultValue);
  }

  /// AND operation: returns a new allocated bit
  factory GAllocatedBit.and(
      BellmanConstraintSystem cs, GAllocatedBit a, GAllocatedBit b) {
    bool? resultValue;
    final v = cs.alloc(
      () {
        resultValue = a.getValue() & b.getValue();
        return resultValue! ? JubJubNativeFq.one() : JubJubNativeFq.zero();
      },
    );
    cs.enforce(
        (lc) => lc + a.variable, (lc) => lc + b.variable, (lc) => lc + v);
    return GAllocatedBit(v, resultValue);
  }

  /// AND-NOT operation: a AND (NOT b)
  factory GAllocatedBit.andNot(
      BellmanConstraintSystem cs, GAllocatedBit a, GAllocatedBit b) {
    bool? resultValue;
    final v = cs.alloc(
      () {
        resultValue = a.getValue() & !b.getValue();
        return resultValue! ? JubJubNativeFq.one() : JubJubNativeFq.zero();
      },
    );
    cs.enforce((lc) => lc + a.variable, (lc) => lc + cs.one() - b.variable,
        (lc) => lc + v);

    return GAllocatedBit(v, resultValue);
  }

  /// NOR operation: (NOT a) AND (NOT b)
  factory GAllocatedBit.nor(
      BellmanConstraintSystem cs, GAllocatedBit a, GAllocatedBit b) {
    bool? resultValue;
    final v = cs.alloc(
      () {
        resultValue = !a.getValue() & !b.getValue();
        return resultValue! ? JubJubNativeFq.one() : JubJubNativeFq.zero();
      },
    );
    cs.enforce((lc) => lc + cs.one() - a.variable,
        (lc) => lc + cs.one() - b.variable, (lc) => lc + v);
    return GAllocatedBit(v, resultValue);
  }

  @override
  List<dynamic> get variables => [variable, value];
}

sealed class GBoolean with Equality {
  const GBoolean();
  LinearCombination lc(GVariable one, JubJubNativeFq coeff);
  bool? _getValue();
  bool get hasValue => _getValue() != null;
  GBoolean not();

  bool getValue() {
    final value = _getValue();
    if (value == null) {
      throw BellmanException.operationFailed("getValue",
          reason: "Missing value.");
    }
    return value;
  }

  /// Checks if the boolean is a constant
  bool get isConstant => false;

  /// Enforce that two GBooleans are equal
  static void enforceEqual(
      {required BellmanConstraintSystem cs,
      required GBoolean a,
      required GBoolean b}) {
    switch ((a, b)) {
      // Both constants
      case (GBooleanConstant(c: bool a), GBooleanConstant(c: bool b)):
        if (a != b) {
          throw BellmanException.operationFailed("enforceEqual",
              reason: "Unsatisfiable constraint: constants are different");
        }
        break;

      // One is constant true
      case (GBooleanConstant(c: true), final a):
      case (final a, GBooleanConstant(c: true)):
        cs.enforce((lc) => lc, (lc) => lc,
            (lc) => lc + cs.one() - a.lc(cs.one(), JubJubNativeFq.one()));
        break;

      // One is constant false
      case (GBooleanConstant(c: false), final other):
      case (final other, GBooleanConstant(c: false)):
        cs.enforce((lc) => lc, (lc) => lc,
            (lc) => lc + other.lc(cs.one(), JubJubNativeFq.one()));
        break;

      // Both allocated bits (or Is/Not)
      default:
        cs.enforce(
            (lc) => lc,
            (lc) => lc,
            (lc) =>
                a.lc(cs.one(), JubJubNativeFq.one()) -
                b.lc(cs.one(), JubJubNativeFq.one()));
        break;
    }
  }

  /// Perform XOR over two boolean operands
  factory GBoolean.xor(
      {required BellmanConstraintSystem cs,
      required GBoolean a,
      required GBoolean b}) {
    switch ((a, b)) {
      // One operand is constant false
      case (GBooleanConstant(c: false), final x):
      case (final x, GBooleanConstant(c: false)):
        return x;

      // One operand is constant true
      case (GBooleanConstant(c: true), final x):
      case (final x, GBooleanConstant(c: true)):
        return x.not();

      // a XOR (NOT b) = NOT(a XOR b)
      case (final GBooleanIs isVal, final GBooleanNot notVal):
      case (final GBooleanNot notVal, final GBooleanIs isVal):
        return GBoolean.xor(cs: cs, a: isVal, b: notVal.not()).not();

      // a XOR b = (NOT a) XOR (NOT b) or both Is
      case (GBooleanIs(bit: final a), GBooleanIs(bit: final b)):
      case (GBooleanNot(bit: final a), GBooleanNot(bit: final b)):
        return GBooleanIs(GAllocatedBit.xor(cs, a, b));
    }
  }

  /// Perform AND over two boolean operands
  factory GBoolean.and(BellmanConstraintSystem cs, GBoolean a, GBoolean b) {
    switch ((a, b)) {
      case (GBooleanConstant(c: false), _):
      case (_, GBooleanConstant(c: false)):
        return GBooleanConstant(false);
      case (GBooleanConstant(c: true), final x):
      case (final x, GBooleanConstant(c: true)):
        return x;

      // a AND (NOT b) or (NOT a) AND b
      case (GBooleanIs(bit: final isVal), GBooleanNot(bit: final notVal)):
      case (GBooleanNot(bit: final notVal), GBooleanIs(bit: final isVal)):
        return GBooleanIs(GAllocatedBit.andNot(cs, isVal, notVal));

      // (NOT a) AND (NOT b) = a NOR b
      case (GBooleanNot(:final bit), GBooleanNot(bit: final bVal)):
        return GBooleanIs(GAllocatedBit.nor(cs, bit, bVal));

      // a AND b
      case (GBooleanIs(:final bit), GBooleanIs(bit: final bVal)):
        return GBooleanIs(GAllocatedBit.and(cs, bit, bVal));
    }
  }

  /// SHA-256 "ch" function: (a AND b) XOR ((NOT a) AND c)
  factory GBoolean.sha256Ch(
      BellmanConstraintSystem cs, GBoolean a, GBoolean b, GBoolean c) {
    // Compute constant value if all are known
    bool chValue() =>
        ((a.getValue() & b.getValue()) ^ ((!a.getValue()) & c.getValue()));

    switch ((a, b, c)) {
      // All constants
      case (GBooleanConstant(), GBooleanConstant(), GBooleanConstant()):
        return GBooleanConstant(chValue());

      // a is false
      case (GBooleanConstant(c: false), _, final GBoolean cVal):
        return cVal;

      // b is false
      case (final aVal, GBooleanConstant(c: false), final GBoolean cVal):
        return GBoolean.and(cs, aVal.not(), cVal);

      // c is false
      case (final aVal, final bVal, GBooleanConstant(c: false)):
        return GBoolean.and(cs, aVal, bVal);

      // c is true
      case (final aVal, final bVal, GBooleanConstant(c: true)):
        return GBoolean.and(cs, aVal, bVal.not()).not();

      // b is true
      case (final aVal, GBooleanConstant(c: true), final cVal):
        return GBoolean.and(cs, aVal.not(), cVal.not()).not();

      default:
        break;
    }
    final v = chValue();
    // Allocate variable in the constraint system
    final ch = cs.alloc(
      () {
        return v ? JubJubNativeFq.one() : JubJubNativeFq.zero();
      },
    );

    // Enforce: a * (b - c) = ch - c
    cs.enforce(
        (lc) =>
            b.lc(cs.one(), JubJubNativeFq.one()) -
            c.lc(cs.one(), JubJubNativeFq.one()),
        (lc) => a.lc(cs.one(), JubJubNativeFq.one()),
        (lc) => lc + ch - c.lc(cs.one(), JubJubNativeFq.one()));

    return GBooleanIs(GAllocatedBit(ch, v));
  }

  /// SHA-256 "maj" function: (a AND b) XOR (a AND c) XOR (b AND c)
  factory GBoolean.sha256Maj(
      BellmanConstraintSystem cs, GBoolean a, GBoolean b, GBoolean c) {
    // Compute constant value if all are known
    bool majValue() => ((a.getValue() & b.getValue()) ^
        (a.getValue() & c.getValue()) ^
        (b.getValue() & c.getValue()));

    switch ((a, b, c)) {
      case (GBooleanConstant(), GBooleanConstant(), GBooleanConstant()):
        return GBooleanConstant(majValue());

      // a is false
      case (GBooleanConstant(c: false), final bVal, final cVal):
        return GBoolean.and(cs, bVal, cVal);

      case (final aVal, GBooleanConstant(c: false), final cVal):
        return GBoolean.and(cs, aVal, cVal);

      case (final aVal, final bVal, GBooleanConstant(c: false)):
        return GBoolean.and(cs, aVal, bVal);

      case (final aVal, final bVal, GBooleanConstant(c: true)):
        return GBoolean.and(cs, aVal.not(), bVal.not()).not();

      // b is true
      case (final aVal, GBooleanConstant(c: true), final cVal):
        return GBoolean.and(cs, aVal.not(), cVal.not()).not();

      // a is true
      case (GBooleanConstant(c: true), final bVal, final cVal):
        return GBoolean.and(cs, bVal.not(), cVal.not()).not();

      // All allocated bits (Is/Not)
      default:
        break;
    }
    final v = majValue();
    // Allocate variable in the constraint system
    final maj = cs.alloc(
      () {
        return v ? JubJubNativeFq.one() : JubJubNativeFq.zero();
      },
    );

    // Compute b AND c first
    final bc = GBoolean.and(cs, b, c);

    cs.enforce(
        (lc) =>
            bc.lc(cs.one(), JubJubNativeFq.one()) +
            bc.lc(cs.one(), JubJubNativeFq.one()) -
            b.lc(cs.one(), JubJubNativeFq.one()) -
            c.lc(cs.one(), JubJubNativeFq.one()),
        (lc) => a.lc(cs.one(), JubJubNativeFq.one()),
        (lc) => bc.lc(cs.one(), JubJubNativeFq.one()) - maj);
    return GBooleanIs(GAllocatedBit(maj, v));
  }
}

class GBooleanIs extends GBoolean {
  final GAllocatedBit bit;
  const GBooleanIs(this.bit);
  @override
  String toString() {
    return "Is($bit)";
  }

  @override
  LinearCombination lc(GVariable one, JubJubNativeFq coeff) {
    return LinearCombination.zero() + (coeff, bit.variable);
  }

  @override
  bool? _getValue() {
    return bit.value;
  }

  @override
  GBoolean not() {
    return GBooleanNot(bit);
  }

  @override
  List<dynamic> get variables => [bit];
}

class GBooleanNot extends GBoolean {
  final GAllocatedBit bit;
  const GBooleanNot(this.bit);

  @override
  LinearCombination lc(GVariable one, JubJubNativeFq coeff) {
    return LinearCombination.zero() + (coeff, one) - (coeff, bit.variable);
  }

  @override
  bool? _getValue() {
    final v = bit.value;
    if (v == null) return null;
    return !v;
  }

  @override
  String toString() {
    return "Not($bit)";
  }

  @override
  GBoolean not() {
    return GBooleanIs(bit);
  }

  @override
  List<dynamic> get variables => [bit];
}

class GBooleanConstant extends GBoolean {
  final bool c;
  const GBooleanConstant(this.c);
  @override
  String toString() {
    return "Constant($c)";
  }

  @override
  bool get isConstant => true;

  @override
  LinearCombination lc(GVariable one, JubJubNativeFq coeff) {
    if (c) {
      return LinearCombination.zero() + (coeff, one);
    }
    return LinearCombination.zero();
  }

  @override
  bool? _getValue() {
    return c;
  }

  @override
  GBoolean not() {
    return GBooleanConstant(!c);
  }

  @override
  List<dynamic> get variables => [c];
}
