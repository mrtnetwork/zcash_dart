import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/variable.dart';

class LinearCombination {
  final List<(GVariable, JubJubNativeFq)> _inner;
  List<(GVariable, JubJubNativeFq)> get inner => _inner;
  LinearCombination._(List<(GVariable, JubJubNativeFq)> inner)
      : _inner = inner.immutable;
  factory LinearCombination.zero() => LinearCombination._([]);
  LinearCombination operator +(Object other) {
    final result = <(GVariable, JubJubNativeFq)>[..._inner];
    switch (other) {
      case (JubJubNativeFq coeff, GVariable v):
        result.add((v, coeff));
        break;
      case GVariable v:
        result.add((v, JubJubNativeFq.one()));
        break;

      // LinearCombination
      case LinearCombination lc:
        for (final (v, c) in lc._inner) {
          result.add((v, c));
        }
        break;

      // (Scalar, LinearCombination)
      case (JubJubNativeFq coeff, LinearCombination lc):
        for (final (v, c) in lc._inner) {
          result.add((v, c * coeff));
        }
        break;
      default:
        throw BellmanException.operationFailed("Addition",
            reason: "Unsupported object.");
    }

    return LinearCombination._(result);
  }

  /// SUB
  LinearCombination operator -(Object other) {
    final result = <(GVariable, JubJubNativeFq)>[..._inner];

    switch (other) {
      // (Scalar, GVariable)
      case (JubJubNativeFq coeff, GVariable v):
        result.add((v, -coeff));
        break;

      // GVariable
      case GVariable v:
        result.add((v, -JubJubNativeFq.one()));
        break;

      // LinearCombination
      case LinearCombination lc:
        for (final (v, c) in lc._inner) {
          result.add((v, -c));
        }
        break;

      // (Scalar, LinearCombination)
      case (JubJubNativeFq coeff, LinearCombination lc):
        for (final (v, c) in lc._inner) {
          result.add((v, -(c * coeff)));
        }
        break;

      default:
        throw BellmanException.operationFailed("Subtraction",
            reason: "Unsupported object.");
    }

    return LinearCombination._(result);
  }
}

abstract class BellmanConstraintSystem<CS extends BellmanConstraintSystem<CS>> {
  CS getRoot();

  /// Return the "one" input variable
  GVariable one() => GVariable(GIndexInput(0));

  /// Allocate a private variable
  GVariable alloc(JubJubNativeFq Function() f);

  /// Allocate a public input variable
  GVariable allocInput(JubJubNativeFq Function() f);

  /// Enforce that a * b = c
  void enforce(
      LinearCombination Function(LinearCombination lc) a,
      LinearCombination Function(LinearCombination lc) b,
      LinearCombination Function(LinearCombination lc) c);
}

class MultiEq extends BellmanConstraintSystem<MultiEq> {
  final BellmanConstraintSystem cs;
  MultiEq(this.cs);

  int _bitsUsed = 0;

  LinearCombination _lhs = LinearCombination.zero();
  LinearCombination _rhs = LinearCombination.zero();

  /// Emit a batched equality constraint
  void _accumulate() {
    final lhsSnapshot = _lhs;
    final rhsSnapshot = _rhs;

    cs.enforce((_) => lhsSnapshot, (lc) => lc + cs.one(), (_) => rhsSnapshot);

    _lhs = LinearCombination.zero();
    _rhs = LinearCombination.zero();
    _bitsUsed = 0;
  }

  void enforceEqual(int numBits, LinearCombination lhs, LinearCombination rhs) {
    final capacity = JubJubFqConst.capacity;
    if (capacity <= _bitsUsed + numBits) {
      _accumulate();
    }
    assert(capacity > _bitsUsed + numBits);
    final coeff = JubJubNativeFq.from(2).pow(BigInt.from(_bitsUsed));
    _lhs = _lhs + (coeff, lhs);
    _rhs = _rhs + (coeff, rhs);
    _bitsUsed += numBits;
  }

  void close() {
    if (_bitsUsed > 0) {
      _accumulate();
    }
  }

  @override
  GVariable alloc(JubJubNativeFq Function() f) {
    return cs.alloc(f);
  }

  @override
  GVariable allocInput(JubJubNativeFq Function() f) {
    return cs.allocInput(f);
  }

  @override
  void enforce(
      LinearCombination Function(LinearCombination) a,
      LinearCombination Function(LinearCombination) b,
      LinearCombination Function(LinearCombination) c) {
    cs.enforce(a, b, c);
  }

  @override
  MultiEq getRoot() {
    return this;
  }
}

abstract mixin class BellmanCircuit {
  void synthesize(BellmanConstraintSystem cs);
}
