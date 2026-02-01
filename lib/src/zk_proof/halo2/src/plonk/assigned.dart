import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';

sealed class Assigned with Equality {
  const Assigned();
  factory Assigned.from(Object? r) {
    return switch (r) {
      final PallasNativeFp r => AssignedTrivial(r),
      final Assigned r => r,
      final List<int> r => AssignedTrivial(PallasNativeFp.fromBytes(r)),
      _ => throw Halo2Exception.operationFailed("from",
          reason: "Unsupported convertion.")
    };
  }

  Assigned operator -() => switch (this) {
        final AssignedZero _ => const AssignedZero(),
        final AssignedTrivial r => AssignedTrivial(-r.inner),
        final AssignedRational r => AssignedRational(-r.a, r.b),
      };
  Assigned operator -(Assigned rhs) => this + (-rhs);
  Assigned operator *(Object other) {
    return switch (other) {
      final Assigned rhs => switch (this) {
          final AssignedZero _ => const AssignedZero(),
          final AssignedTrivial l => switch (rhs) {
              final AssignedZero _ => const AssignedZero(),
              final AssignedTrivial r => AssignedTrivial(l.inner * r.inner),
              final AssignedRational r => AssignedRational(r.a * l.inner, r.b),
            },
          final AssignedRational l => switch (rhs) {
              final AssignedZero _ => const AssignedZero(),
              final AssignedTrivial r => AssignedRational(l.a * r.inner, l.b),
              final AssignedRational r =>
                AssignedRational(l.a * r.a, l.b * r.b),
            },
        },
      final PallasNativeFp rhs => this * AssignedTrivial(rhs),
      _ => throw Halo2Exception.operationFailed("Multiplication",
          reason: "Unsupported object.")
    };
  }

  Assigned operator +(Assigned rhs) => switch (this) {
        final AssignedZero _ => rhs,
        final AssignedTrivial l => switch (rhs) {
            final AssignedZero _ => l,
            final AssignedTrivial r => AssignedTrivial(l.inner + r.inner),
            final AssignedRational r =>
              AssignedRational(r.a + r.b * l.inner, r.b),
          },
        final AssignedRational l => switch (rhs) {
            final AssignedZero _ => l,
            final AssignedTrivial r =>
              AssignedRational(l.a + l.b * r.inner, l.b),
            final AssignedRational r =>
              AssignedRational(l.a * r.b + l.b * r.a, l.b * r.b),
          },
      };

  /// Returns the numerator.
  PallasNativeFp get numerator => switch (this) {
        final AssignedZero _ => PallasNativeFp.zero(),
        final AssignedTrivial r => r.inner,
        final AssignedRational r => r.a
      };

  /// Returns the denominator if non-trivial.
  PallasNativeFp? get denominator =>
      switch (this) { final AssignedRational r => r.b, _ => null };

  /// Returns true if this element is zero.
  bool get isZero => switch (this) {
        final AssignedZero _ => true,
        final AssignedTrivial r => r.inner.isZero(),
        final AssignedRational r => r.a.isZero() || r.b.isZero()
      };

  /// Doubles this element.
  Assigned double() => switch (this) {
        final AssignedZero _ => const AssignedZero(),
        final AssignedTrivial r => AssignedTrivial(r.inner.double()),
        final AssignedRational r => AssignedRational(r.a.double(), r.b),
      };

  /// Squares this element.
  Assigned square() => switch (this) {
        final AssignedZero _ => const AssignedZero(),
        final AssignedTrivial r => AssignedTrivial(r.inner.square()),
        final AssignedRational r =>
          AssignedRational(r.a.square(), r.b.square()),
      };

  /// Cubes this element.
  Assigned cube() => square() * this;

  /// Inverts this assigned value.
  Assigned invert() => switch (this) {
        final AssignedZero _ => const AssignedZero(),
        final AssignedTrivial r =>
          AssignedRational(PallasNativeFp.one(), r.inner),
        final AssignedRational r => AssignedRational(r.b, r.a),
      };

  /// Evaluates this assigned value directly.
  PallasNativeFp evaluate() => switch (this) {
        final AssignedZero _ => PallasNativeFp.zero(),
        final AssignedTrivial r => r.inner,
        final AssignedRational r => r.b == PallasNativeFp.one()
            ? r.a
            : r.a *
                () {
                  return r.b.invert() ?? PallasNativeFp.zero();
                }(),
      };

  @override
  operator ==(other) {
    if (other is! Assigned) return false;
    return switch ((this, other)) {
      // (Zero, Zero)
      (AssignedZero(), AssignedZero()) => true,

      // (Zero, x) | (x, Zero)
      (AssignedZero(), final x) || (final x, AssignedZero()) => x.isZero,

      // (Rational(_, denom), x) | (x, Rational(_, denom)) if denom == 0
      (AssignedRational(b: final d), final x) when d.isZero() => x.isZero,
      (final x, AssignedRational(b: final d)) when d.isZero() => x.isZero,

      // (Trivial, Trivial)
      (AssignedTrivial(inner: final lhs), AssignedTrivial(inner: final rhs)) =>
        lhs == rhs,

      // (Trivial(x), Rational(n, d))
      (
        AssignedTrivial(inner: final x),
        AssignedRational(a: final n, b: final d)
      ) =>
        (x * d) == n,

      // (Rational(n, d), Trivial(x))
      (
        AssignedRational(a: final n, b: final d),
        AssignedTrivial(inner: final x)
      ) =>
        (x * d) == n,

      // (Rational(a,b), Rational(c,d))
      (
        AssignedRational(a: final an, b: final ad),
        AssignedRational(a: final bn, b: final bd)
      ) =>
        (an * bd) == (ad * bn),
    };
  }

  @override
  int get hashCode {
    return HashCodeGenerator.generateHashCode(variables);
  }
}

final class AssignedZero extends Assigned {
  const AssignedZero();

  @override
  String toString() {
    return "Zero()";
  }

  @override
  List<dynamic> get variables => [];
}

final class AssignedTrivial extends Assigned {
  final PallasNativeFp inner;
  const AssignedTrivial(this.inner);

  @override
  List<dynamic> get variables => [inner];
}

final class AssignedRational extends Assigned {
  final PallasNativeFp a;
  final PallasNativeFp b;
  const AssignedRational(this.a, this.b);

  @override
  List<dynamic> get variables => [a, b];
}
