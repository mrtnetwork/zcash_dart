import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'boolean.dart';

class GUInt32 with Equality {
  final List<GBoolean> bits;
  final int? value;
  GUInt32({required this.bits, int? value}) : value = value?.asU32;

  /// Construct a constant `GUInt32` from an integer
  factory GUInt32.constant(int value) {
    final bits = <GBoolean>[];
    int tmp = value;
    for (int i = 0; i < 32; i++) {
      bits.add(GBooleanConstant((tmp & 1) == 1));
      tmp >>= 1;
    }
    return GUInt32(bits: bits, value: value);
  }

  factory GUInt32.alloc(BellmanConstraintSystem cs, int? value) {
    final List<bool?> values = List<bool?>.filled(32, null);

    if (value != null) {
      int val = value;
      for (int i = 0; i < 32; i++) {
        values[i] = (val & 1) == 1;
        val >>= 1;
      }
    }
    // Allocate bits
    final bits = <GBoolean>[];
    for (int i = 0; i < values.length; i++) {
      final b = GAllocatedBit.alloc(cs: cs, value: values[i]);
      bits.add(GBooleanIs(b));
    }
    return GUInt32(bits: bits, value: value);
  }

  /// Little-endian bits (LSB first)
  List<GBoolean> intoBits() => bits;

  /// Big-endian bits
  List<GBoolean> intoBitsBe() => bits.reversed.toList();

  /// Construct from big-endian bits
  factory GUInt32.fromBitsBe(List<GBoolean> bits) {
    assert(bits.length == 32);

    int? value = 0;

    for (final b in bits) {
      if (value != null) {
        value = value << 1;
      }

      if (b.hasValue) {
        final v = b.getValue();
        if (v) {
          if (value != null) {
            value = value | 1;
          }
        }
      } else {
        value = null;
      }
    }

    return GUInt32(value: value, bits: bits.reversed.toList());
  }

  /// Construct from little-endian bits
  factory GUInt32.fromBits(List<GBoolean> bits) {
    assert(bits.length == 32);

    final newBits = List<GBoolean>.from(bits);
    int? value = 0;

    for (final b in newBits.reversed) {
      if (value != null) {
        value = value << 1;
      }
      switch (b) {
        case GBooleanConstant(c: true):
          if (value != null) {
            value = value | 1;
          }
          break;

        case GBooleanConstant(c: false):
          break;

        case GBooleanIs(bit: final bit):
          switch (bit.value) {
            case true:
              if (value != null) {
                value = value | 1;
              }
              break;
            case false:
              break;
            case null:
              value = null;
              break;
          }
          break;

        case GBooleanNot(bit: final bit):
          switch (bit.value) {
            case false:
              if (value != null) {
                value = value | 1;
              }
              break;
            case true:
              break;
            case null:
              value = null;
              break;
          }
          break;
      }
    }
    return GUInt32(value: value, bits: newBits);
  }

  /// Rotate right
  GUInt32 rotr(int by) {
    final shift = by % 32;
    // final shift = by & 31; // faster + safe

    // if (shift == 0) {
    //   return this;
    // }
    final newBits = [
      ...bits.skip(shift),
      ...bits,
    ].take(32).toList();
    final v = value;
    final rotated = v == null
        ? null
        : ((v >> shift).toU32 | (v << (32 - shift)).toU32).toU32;

    return GUInt32(bits: newBits, value: rotated);
  }

  GUInt32 shr(int by) {
    final shift = by % 32;
    final fill = GBooleanConstant(false);
    final newBits = <GBoolean>[
      ...bits.skip(shift),
      ...Iterable<GBoolean>.generate(32, (_) => fill),
    ].take(32).toList();
    return GUInt32(
        bits: newBits, value: value == null ? null : (value! >> shift));
  }

  factory GUInt32.triop(
      BellmanConstraintSystem cs,
      GUInt32 a,
      GUInt32 b,
      GUInt32 c,
      int Function(int, int, int) triFn,
      GBoolean Function(
              BellmanConstraintSystem, int, GBoolean, GBoolean, GBoolean)
          circuitFn) {
    // Compute new value if all operands are known
    int? newValue;
    if (a.value != null && b.value != null && c.value != null) {
      newValue = triFn(a.value!, b.value!, c.value!);
    }

    // Compute new bits using circuit function
    final bits = <GBoolean>[];
    for (var i = 0; i < 32; i++) {
      final bit = circuitFn(cs, i, a.bits[i], b.bits[i], c.bits[i]);
      bits.add(bit);
    }

    return GUInt32(bits: bits, value: newValue);
  }

  /// SHA256 maj: (a & b) ^ (a & c) ^ (b & c)
  static GUInt32 sha256Maj(
      BellmanConstraintSystem cs, GUInt32 a, GUInt32 b, GUInt32 c) {
    return GUInt32.triop(cs, a, b, c, (a, b, c) => (a & b) ^ (a & c) ^ (b & c),
        (cs, i, a, b, c) => GBoolean.sha256Maj(cs, a, b, c));
  }

  /// SHA256 ch: (a & b) ^ (~a & c)
  static GUInt32 sha256Ch(
      BellmanConstraintSystem cs, GUInt32 a, GUInt32 b, GUInt32 c) {
    return GUInt32.triop(cs, a, b, c, (a, b, c) => (a & b) ^ ((~a) & c),
        (cs, i, a, b, c) => GBoolean.sha256Ch(cs, a, b, c));
  }

  /// Bitwise XOR
  GUInt32 xor(BellmanConstraintSystem cs, GUInt32 other) {
    // Compute new value if both are known
    int? newValue;
    if (value != null && other.value != null) {
      newValue = (value! ^ other.value!).toU32;
    }
    // Compute new bits
    final newBits = <GBoolean>[];

    for (var i = 0; i < bits.length; i++) {
      final oBit = other.bits.elementAtOrNull(i);
      assert(oBit != null);
      if (oBit == null) {
        break;
      }

      newBits.add(GBoolean.xor(cs: cs, a: bits[i], b: oBit));
    }

    return GUInt32(bits: newBits, value: newValue);
  }

  /// Modular addition of multiple operands
  factory GUInt32.addMany(
      BellmanConstraintSystem<MultiEq> cs, List<GUInt32> operands) {
    if (operands.length < 2 || operands.length > 10) {
      throw ArgumentException.invalidOperationArguments("addMany",
          reason: "Invalid input length.");
    }

    BigInt maxValue = BigInt.from(operands.length) * BinaryOps.maskBig32;

    BigInt? resultValue = BigInt.zero;
    bool allConstants = true;

    var lhs = LinearCombination.zero();

    for (final op in operands) {
      final v = op.value;
      if (v != null) {
        if (resultValue != null) {
          resultValue = resultValue + BigInt.from(v);
        }
      } else {
        resultValue = null;
      }

      JubJubNativeFq coeff = JubJubNativeFq.one();
      for (final bit in op.bits) {
        lhs = lhs + bit.lc(cs.one(), coeff);
        allConstants &= bit.isConstant;
        coeff = coeff.double();
      }
    }
    final modularValue = resultValue?.toU32;

    if (allConstants && modularValue != null) {
      return GUInt32.constant(modularValue);
    }

    List<GBoolean> resultBits = [];
    var rhs = LinearCombination.zero();

    var coeff = JubJubNativeFq.one();
    int i = 0;

    while (maxValue != BigInt.zero) {
      final bit = GAllocatedBit.alloc(
          cs: cs,
          value: resultValue != null
              ? ((resultValue >> i) & BigInt.one) == BigInt.one
              : null);
      rhs = rhs + (coeff, bit.variable);
      resultBits.add(GBooleanIs(bit));

      maxValue >>= 1;
      coeff = coeff.double();
      i++;
    }
    cs.getRoot().enforceEqual(i, lhs, rhs);
    resultBits = resultBits.sublist(0, 32);
    return GUInt32(bits: resultBits, value: modularValue);
  }

  @override
  List<dynamic> get variables => [bits, value];
}
