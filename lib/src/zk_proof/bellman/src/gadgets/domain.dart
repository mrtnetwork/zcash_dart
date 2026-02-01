import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/utils/arithmetic.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';

class AssignableFq {
  JubJubNativeFq _scalar;
  AssignableFq(JubJubNativeFq scalar) : _scalar = scalar;
  factory AssignableFq.groupZero() => AssignableFq(JubJubNativeFq.zero());
  AssignableFq clone() => AssignableFq(scalar);
  JubJubNativeFq get scalar => _scalar;

  AssignableFq operator *(JubJubNativeFq scalar) {
    _scalar *= scalar;
    return this;
  }

  AssignableFq operator +(AssignableFq rhs) {
    _scalar += rhs.scalar;
    return this;
  }

  AssignableFq operator -(AssignableFq rhs) {
    _scalar -= rhs.scalar;
    return this;
  }
}

class SaplingEvaluationDomain {
  final List<AssignableFq> coeffs;
  final int exp;
  final JubJubNativeFq omega;
  final JubJubNativeFq omegaInv;
  final JubJubNativeFq genInv;
  final JubJubNativeFq minV;
  const SaplingEvaluationDomain(
      {required this.coeffs,
      required this.exp,
      required this.omega,
      required this.omegaInv,
      required this.genInv,
      required this.minV});
  factory SaplingEvaluationDomain.fromCoeffs(List<AssignableFq> coeffs) {
    int m = 1;
    int exp = 0;

    while (m < coeffs.length) {
      m *= 2;
      exp += 1;

      if (exp >= JubJubFqConst.S) {
        throw ArgumentException.invalidOperationArguments("fromCoeffs",
            reason: 'Polynomial degree too large.');
      }
    }

    // Compute omega
    JubJubNativeFq omega = JubJubNativeFq.rootOfUnity();
    for (int i = exp; i < JubJubFqConst.S; i++) {
      omega = omega.square();
    }

    // Extend coeffs with zeroes if needed
    List<AssignableFq> extendedCoeffs = List<AssignableFq>.from(coeffs);
    final zero = JubJubNativeFq.zero();
    while (extendedCoeffs.length < m) {
      extendedCoeffs.add(AssignableFq(zero));
    }
    final omegaInv = omega.invert();
    final mInv = JubJubNativeFq.from(m).invert();
    final genInv = JubJubNativeFq.generator().invert();
    if (omegaInv == null || mInv == null || genInv == null) {
      throw BellmanException.operationFailed("fromCoeffs",
          reason: "Division by zero.");
    }
    return SaplingEvaluationDomain(
        coeffs: extendedCoeffs,
        exp: exp,
        omega: omega,
        omegaInv: omegaInv,
        genInv: genInv,
        minV: mInv);
  }

  void fft() {
    BellmanUtils.bestFFT(coeffs, omega, exp);
  }

  void ifft() {
    BellmanUtils.bestFFT(coeffs, omegaInv, exp);
    for (final v in coeffs) {
      v * minV;
    }
  }

  void distributePowers(JubJubNativeFq g) {
    JubJubNativeFq u = g.pow(BigInt.from(0)); // g^0 = 1

    for (int i = 0; i < coeffs.length; i++) {
      coeffs[i] * u;
      u = u * g;
    }
  }

  void cosetFFT() {
    distributePowers(JubJubNativeFq.generator());
    fft();
  }

  void icosetFFT() {
    ifft();
    distributePowers(genInv);
  }

  /// Evaluate t(tau) = tau^m - 1
  JubJubNativeFq z(JubJubNativeFq tau) {
    final tmp = tau.pow(BigInt.from(coeffs.length)) - JubJubNativeFq.one();
    return tmp;
  }

  /// Divide all coeffs by z on coset
  void divideByZOnCoset() {
    final i = z(JubJubNativeFq.generator()).invert();
    if (i == null) {
      throw BellmanException.operationFailed("divideByZOnCoset",
          reason: "Division by zero.");
    }
    for (final v in coeffs) {
      v * i;
    }
  }

  /// Multiply domain element-wise by another
  void mulAssign(SaplingEvaluationDomain other) {
    assert(coeffs.length == other.coeffs.length);

    for (int i = 0; i < coeffs.length; i++) {
      coeffs[i] * other.coeffs[i].scalar;
    }
  }

  /// Subtract another domain element-wise
  void subAssign(SaplingEvaluationDomain other) {
    assert(coeffs.length == other.coeffs.length);

    for (int i = 0; i < coeffs.length; i++) {
      coeffs[i] - other.coeffs[i];
    }
  }
}
