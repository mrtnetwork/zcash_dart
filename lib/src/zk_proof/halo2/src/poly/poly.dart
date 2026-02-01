import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';

class Rotation with Equality {
  final int location;
  const Rotation(this.location);
  factory Rotation.cur() => Rotation(0);
  factory Rotation.prev() => Rotation(-1);
  factory Rotation.next() => Rotation(1);
  bool get isCurrent => location == 0;
  @override
  List<dynamic> get variables => [location];

  String toDebugString() => "Rotation($location)";
}

abstract class Basis {}

class Coeff extends Basis {}

class ExtendedLagrangeCoeff extends Basis {}

class LagrangeCoeff extends Basis {}

class Polynomial<F extends Object, B extends Basis> {
  final List<F> _values;
  Polynomial(List<F> values) : _values = values;
  List<F> get values => _values;
  int get length => values.length;
  Polynomial<F, B> clone() => Polynomial(values.clone());

  static PolynomialScalar<LagrangeCoeff> invert(
      Polynomial<Assigned, LagrangeCoeff> poly,
      List<PallasNativeFp> invDenoms) {
    return PolynomialScalar<LagrangeCoeff>(
      List<PallasNativeFp>.generate(
        poly.values.length,
        (i) {
          return poly.values[i].numerator * invDenoms[i];
        },
      ),
    );
  }

  static List<PolynomialScalar<LagrangeCoeff>> batchInvertAssigned(
    List<Polynomial<Assigned, LagrangeCoeff>> assigned,
  ) {
    // Collect denominators
    final List<List<PallasNativeFp?>> assignedDenominators =
        assigned.map((poly) {
      return poly.values.map((value) => value.denominator).toList();
    }).toList();
    // Gather all non-null denominators for batch inversion
    final List<PallasNativeFp> toInvert = [];
    for (final polyDenoms in assignedDenominators) {
      for (final d in polyDenoms) {
        if (d != null) {
          toInvert.add(d);
        }
      }
    }

    // Batch invert in-place
    Halo2Utils.batchInvert(toInvert);

    // Write inverted values back
    int invertIndex = 0;
    for (final polyDenoms in assignedDenominators) {
      for (int i = 0; i < polyDenoms.length; i++) {
        if (polyDenoms[i] != null) {
          polyDenoms[i] = toInvert[invertIndex++];
        }
      }
    }

    // Apply inverses (use F.ONE for trivial denominators)
    final List<PolynomialScalar<LagrangeCoeff>> result = [];
    final one = PallasNativeFp.one();
    for (int i = 0; i < assigned.length; i++) {
      result.add(invert(
          assigned[i],
          assignedDenominators[i]
              .map<PallasNativeFp>((e) => e ?? one)
              .toList()));
    }

    return result;
  }

  List<F> getChunkOfRotatedHelper({
    required bool rotationIsNegative,
    required int rotationAbs,
    required int chunkSize,
    required int chunkIndex,
  }) {
    final n = values.length;

    // Compute mid and k depending on rotation direction
    final int mid;
    final int k;
    if (rotationIsNegative) {
      k = rotationAbs;
      assert(k <= n);
      mid = n - k;
    } else {
      mid = rotationAbs;
      assert(mid <= n);
      k = n - mid;
    }

    final chunkStart = chunkSize * chunkIndex;
    final chunkEnd = (chunkSize * (chunkIndex + 1)).clamp(0, n);

    if (chunkEnd <= k) {
      // Chunk entirely in last `k` coefficients
      return values.sublist(mid + chunkStart, mid + chunkEnd).toList();
    } else if (chunkStart >= k) {
      // Chunk entirely in first `mid` coefficients
      return values.sublist(chunkStart - k, chunkEnd - k).toList();
    } else {
      // Chunk spans the boundary between last `k` and first `mid`
      final firstHalf = values.sublist(mid + chunkStart);
      final secondHalf = values.sublist(0, chunkEnd - k);
      final chunk = [...firstHalf, ...secondHalf];
      assert(chunk.length <= chunkSize);
      return chunk;
    }
  }

  /// Extract a chunk of the polynomial after rotation
  List<F> getChunkOfRotated(Rotation rotation, int chunkSize, int chunkIndex) {
    final rotationIsNegative = rotation.location < 0;
    final rotationAbs = rotation.location.abs();

    return getChunkOfRotatedHelper(
      rotationIsNegative: rotationIsNegative,
      rotationAbs: rotationAbs,
      chunkSize: chunkSize,
      chunkIndex: chunkIndex,
    );
  }

  Polynomial<PallasNativeFp, B> operator *(PallasNativeFp rhs) {
    switch (this) {
      case final Polynomial<PallasNativeFp, B> r:
        for (var i = 0; i < r.values.length; i++) {
          r.values[i] = r.values[i] * rhs;
        }
        return r;
      default:
        throw Halo2Exception.operationFailed("Multiplication",
            reason: "Unsupported object.");
    }
  }

  Polynomial<PallasNativeFp, B> operator +(
      Polynomial<PallasNativeFp, B> other) {
    switch (this) {
      case final Polynomial<PallasNativeFp, B> r:
        for (var i = 0; i < r.values.length; i++) {
          r.values[i] = r.values[i] + other.values[i];
        }
        return r;
      default:
        throw Halo2Exception.operationFailed("Addition",
            reason: "Unsupported object.");
    }
  }
}

class PolynomialScalar<B extends Basis> extends Polynomial<PallasNativeFp, B>
    with Equality, ProtobufEncodableMessage {
  PolynomialScalar(super.values);
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.repeated(
            fieldNumber: 1, elementType: ProtoFieldType.bytes)
      ];
  factory PolynomialScalar.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return PolynomialScalar(decode
        .getListOfBytes(1)
        .map((e) => PallasNativeFp.fromBytes(e))
        .toList());
  }
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [values.map((e) => e.toBytes()).toList()];

  PolynomialScalar<C> cast<C extends Basis>() {
    if (this is PolynomialScalar<C>) return this as PolynomialScalar<C>;
    throw CastFailedException(value: this);
  }

  @override
  PolynomialScalar<B> clone() => PolynomialScalar(values.clone());
  @override
  List<dynamic> get variables => [values];
}
