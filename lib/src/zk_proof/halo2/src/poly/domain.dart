import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';

class EvaluationDomain with Equality, ProtobufEncodableMessage {
  final int n;
  final int k;
  final int extendedK;
  final PallasNativeFp omega;
  final PallasNativeFp omegaInv;
  final PallasNativeFp extendedOmega;
  final PallasNativeFp extendedOmegaInv;
  final PallasNativeFp gCoset;
  final PallasNativeFp gCosetInv;
  final int quotientPolyDegree;
  final PallasNativeFp ifftDivisor;
  final PallasNativeFp extendedIfftDivisor;
  final List<PallasNativeFp> tEvaluations;
  final PallasNativeFp barycentricWeight;
  factory EvaluationDomain.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return EvaluationDomain(
        n: decode.getInt(1),
        k: decode.getInt(2),
        extendedK: decode.getInt(3),
        omega: PallasNativeFp.fromBytes(decode.getBytes(4)),
        omegaInv: PallasNativeFp.fromBytes(decode.getBytes(5)),
        extendedOmega: PallasNativeFp.fromBytes(decode.getBytes(6)),
        extendedOmegaInv: PallasNativeFp.fromBytes(decode.getBytes(7)),
        gCoset: PallasNativeFp.fromBytes(decode.getBytes(8)),
        gCosetInv: PallasNativeFp.fromBytes(decode.getBytes(9)),
        quotientPolyDegree: decode.getInt(10),
        ifftDivisor: PallasNativeFp.fromBytes(decode.getBytes(11)),
        extendedIfftDivisor: PallasNativeFp.fromBytes(decode.getBytes(12)),
        tEvaluations: decode
            .getListOfBytes(13)
            .map((e) => PallasNativeFp.fromBytes(e))
            .toList(),
        barycentricWeight: PallasNativeFp.fromBytes(decode.getBytes(14)));
  }

  String toDebugString() =>
      "PinnedEvaluationDomain { k: $k, extended_k: $extendedK, omega: ${BytesUtils.toHexString(omega.toBytes().reversed.toList(), prefix: "0x")} }";

  EvaluationDomain(
      {required this.n,
      required this.k,
      required this.extendedK,
      required this.omega,
      required this.omegaInv,
      required this.extendedOmega,
      required this.extendedOmegaInv,
      required this.gCoset,
      required this.gCosetInv,
      required this.quotientPolyDegree,
      required this.ifftDivisor,
      required this.extendedIfftDivisor,
      required List<PallasNativeFp> tEvaluations,
      required this.barycentricWeight})
      : tEvaluations = tEvaluations.immutable;

  factory EvaluationDomain.newDomain(int j, int k) {
    final int quotientPolyDegree = (j - 1);

    // n = 2^k
    final int n = 1 << k;

    // Compute extended_k
    int extendedK = k;
    while ((1 << extendedK) < (n * quotientPolyDegree)) {
      extendedK += 1;
    }

    // Get extended_omega
    PallasNativeFp extendedOmega = PallasNativeFp.rootOfUnity();
    for (int i = extendedK; i < PallasFPConst.S; i++) {
      extendedOmega = extendedOmega.square();
    }
    PallasNativeFp extendedOmegaInv = extendedOmega; // Inversion computed later

    PallasNativeFp omega = extendedOmega;
    for (int i = k; i < extendedK; i++) {
      omega = omega.square();
    }
    PallasNativeFp omegaInv = omega;

    // Coset generator
    final PallasNativeFp gCoset = PallasNativeFp.zeta();
    final PallasNativeFp gCosetInv = gCoset.square();
    final e = BigInt.from(n);
    List<PallasNativeFp> tEvaluations = [];
    final PallasNativeFp orig = PallasNativeFp.zeta().pow(BigInt.from(n));
    final PallasNativeFp step = extendedOmega.pow(e);
    PallasNativeFp cur = orig;
    do {
      tEvaluations.add(cur);
      cur *= step;
    } while (cur != orig);

    assert(tEvaluations.length == (1 << (extendedK - k)));

    for (int i = 0; i < tEvaluations.length; i++) {
      tEvaluations[i] -= PallasNativeFp.one();
    }
    int tLength = tEvaluations.length;

    PallasNativeFp ifftDivisor = PallasNativeFp.from(1 << k);
    PallasNativeFp extendedIfftDivisor = PallasNativeFp.from(1 << extendedK);
    PallasNativeFp barycentricWeight = PallasNativeFp.from(n);
    tEvaluations = [
      ...tEvaluations,
      ifftDivisor,
      extendedIfftDivisor,
      barycentricWeight,
      extendedOmegaInv,
      omegaInv
    ];
    Halo2Utils.batchInvert(tEvaluations);
    return EvaluationDomain(
        n: n,
        k: k,
        extendedK: extendedK,
        omega: omega,
        omegaInv: tEvaluations[tLength + 4],
        extendedOmega: extendedOmega,
        extendedOmegaInv: tEvaluations[tLength + 3],
        gCoset: gCoset,
        gCosetInv: gCosetInv,
        quotientPolyDegree: quotientPolyDegree,
        ifftDivisor: tEvaluations[tLength],
        extendedIfftDivisor: tEvaluations[tLength + 1],
        tEvaluations: tEvaluations.sublist(0, tLength),
        barycentricWeight: tEvaluations[tLength + 2]);
  }

  PolynomialScalar<LagrangeCoeff> emptyLagrange() {
    return PolynomialScalar<LagrangeCoeff>(
        List.filled(n, PallasNativeFp.zero()));
  }

  Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> emptyExtended() {
    return Polynomial<PallasNativeFp, ExtendedLagrangeCoeff>(
        List.filled(extendedLen(), PallasNativeFp.zero()));
  }

  Polynomial<PallasNativeFp, Coeff> emptyCoeff() {
    return Polynomial<PallasNativeFp, Coeff>(
        List.filled(n, PallasNativeFp.zero()));
  }

  Polynomial<Assigned, LagrangeCoeff> emptyLagrangeAssigned() {
    return Polynomial<Assigned, LagrangeCoeff>(
        List.filled(n, AssignedTrivial(PallasNativeFp.zero())));
  }

  PolynomialScalar<LagrangeCoeff> lagrangeFromVec(List<PallasNativeFp> values) {
    assert(values.length == n);
    return PolynomialScalar<LagrangeCoeff>(values);
  }

  Polynomial<PallasNativeFp, Coeff> coeffFromVec(List<PallasNativeFp> values) {
    assert(values.length == n);
    return Polynomial<PallasNativeFp, Coeff>(values);
  }

  PolynomialScalar<Coeff> lagrangeToCoeff(
      Polynomial<PallasNativeFp, LagrangeCoeff> a) {
    assert(a.values.length == 1 << k);
    ifft(a.values, omegaInv, k, ifftDivisor);
    return PolynomialScalar<Coeff>(a.values);
  }

  void ifft(List<PallasNativeFp> a, PallasNativeFp omegaInv, int logN,
      PallasNativeFp divisor) {
    Halo2Utils.bestFftField(a, omegaInv, logN);
    for (int i = 0; i < a.length; i++) {
      a[i] *= divisor;
    }
  }

  void distributePowersZeta(List<PallasNativeFp> a, bool intoCoset) {
    final List<PallasNativeFp> cosetPowers =
        intoCoset ? [gCoset, gCosetInv] : [gCosetInv, gCoset];

    final int cycle = cosetPowers.length + 1; // = 3

    for (int index = 0; index < a.length; index++) {
      final int i = index % cycle;
      if (i != 0) {
        a[index] = a[index] * cosetPowers[i - 1];
      }
    }
  }

  /// Get the size of the extended domain
  int extendedLen() {
    return 1 << extendedK;
  }

  PolynomialScalar<ExtendedLagrangeCoeff> coeffToExtended(
      Polynomial<PallasNativeFp, Coeff> ax) {
    List<PallasNativeFp> values = ax.values;
    assert(values.length == (1 << k));
    distributePowersZeta(values, true);
    final int targetLen = extendedLen();
    final zero = PallasNativeFp.zero();
    if (values.length < targetLen) {
      values = [
        ...values,
        ...List<PallasNativeFp>.filled(targetLen - values.length, zero)
      ];
    } else if (values.length > targetLen) {
      values = values.sublist(0, targetLen);
    }

    // best_fft(&mut a.values, self.extended_omega, self.extended_k);
    Halo2Utils.bestFftField(values, extendedOmega, extendedK);

    return PolynomialScalar<ExtendedLagrangeCoeff>(values);
  }

  List<PallasNativeFp> getChunkOfRotatedExtended(
      Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> poly,
      Rotation rotation,
      int chunkSize,
      int chunkIndex) {
    // Compute scaled rotation
    final newRotation = (1 << (extendedK - k)) * rotation.location.abs();
    return poly.getChunkOfRotatedHelper(
        rotationIsNegative: rotation.location < 0,
        rotationAbs: newRotation,
        chunkSize: chunkSize,
        chunkIndex: chunkIndex);
  }

  Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> divideByVanishingPoly(
      Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> a) {
    assert(a.values.length == extendedLen());
    // Multiply each value by the corresponding t(X) evaluation
    for (var i = 0; i < a.values.length; i++) {
      final tEval = tEvaluations[i % tEvaluations.length];
      a.values[i] = a.values[i] * tEval;
    }

    return Polynomial<PallasNativeFp, ExtendedLagrangeCoeff>(a.values);
  }

  /// Converts an extended Lagrange representation to coefficient form
  List<PallasNativeFp> extendedToCoeff(
      Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> a) {
    assert(a.values.length == extendedLen());
    // Inverse FFT
    ifft(a.values, extendedOmegaInv, extendedK, extendedIfftDivisor);

    // Distribute powers (undo coset transformation)
    distributePowersZeta(a.values, false);

    // Truncate to match quotient polynomial size
    final truncatedLength = n * quotientPolyDegree;
    if (a.values.length > truncatedLength) {
      a.values.removeRange(truncatedLength, a.values.length);
    }

    return a.values;
  }

  PallasNativeFp rotateOmega(PallasNativeFp value, Rotation rotation) {
    PallasNativeFp point = value;
    if (rotation.location >= 0) {
      point *= omega.pow(BigInt.from(rotation.location));
    } else {
      point *= omegaInv.pow(BigInt.from(rotation.location).abs());
    }
    return point;
  }

  List<PallasNativeFp> lIRange(
      PallasNativeFp x, PallasNativeFp xn, List<int> rotations) {
    final results = <PallasNativeFp>[];

    // Step 1: Compute x - omega^rotation for each rotation
    for (final rot in rotations) {
      final rotation = Rotation(rot);
      final result = x - rotateOmega(PallasNativeFp.one(), rotation);
      results.add(result);
    }

    // Step 2: Batch invert all results
    Halo2Utils.batchInvert(results);

    // Step 3: Apply the barycentric weight scaling and rotate back
    final common = (xn - PallasNativeFp.one()) * barycentricWeight;
    for (int i = 0; i < results.length; i++) {
      final rotation = Rotation(rotations[i]);
      results[i] = rotateOmega(results[i] * common, rotation);
    }

    return results;
  }

  @override
  List<Object?> get bufferValues => [
        n,
        k,
        extendedK,
        omega.toBytes(),
        omegaInv.toBytes(),
        extendedOmega.toBytes(),
        extendedOmegaInv.toBytes(),
        gCoset.toBytes(),
        gCosetInv.toBytes(),
        quotientPolyDegree,
        ifftDivisor.toBytes(),
        extendedIfftDivisor.toBytes(),
        tEvaluations.map((e) => e.toBytes()).toList(),
        barycentricWeight.toBytes(),
      ];
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.int32(2),
        ProtoFieldConfig.int32(3),
        ProtoFieldConfig.bytes(4),
        ProtoFieldConfig.bytes(5),
        ProtoFieldConfig.bytes(6),
        ProtoFieldConfig.bytes(7),
        ProtoFieldConfig.bytes(8),
        ProtoFieldConfig.bytes(9),
        ProtoFieldConfig.int32(10),
        ProtoFieldConfig.bytes(11),
        ProtoFieldConfig.bytes(12),
        ProtoFieldConfig.repeated(
            fieldNumber: 13,
            elementType: ProtoFieldType.bytes,
            encoding: ProtoRepeatedEncoding.unpacked),
        ProtoFieldConfig.bytes(14),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<dynamic> get variables => [
        n,
        k,
        extendedK,
        omega,
        omegaInv,
        extendedOmega,
        extendedOmegaInv,
        gCoset,
        gCosetInv,
        quotientPolyDegree,
        ifftDivisor,
        extendedIfftDivisor,
        tEvaluations,
        barycentricWeight
      ];
}
