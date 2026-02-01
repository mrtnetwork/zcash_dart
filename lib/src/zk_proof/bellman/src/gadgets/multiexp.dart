import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';

class GMultiexpUtils {
  static BASE _multiexpInner<BASE extends Bls12NativePoint<BASE>,
          G extends Bls12NativeAffinePoint<BASE>>(GSource<BASE, G> source,
      DensityTracker? densityMap, List<Exponent> exponents, int c) {
    /// Inner closure from Rust, converted to a normal Dart function
    BASE computeChunk(
      GSource<BASE, G> source,
      DensityTracker? densityMap,
      List<ChunkedExponent> chunkedExponents,
      int chunk,
    ) {
      final baseSource = source.builder();
      // Accumulator
      BASE acc = baseSource.identity();

      // Buckets: (1 << c) - 1
      final bucketCount = (1 << c) - 1;
      final buckets = List.generate(bucketCount, (_) => baseSource.identity());

      final handleTrivial = chunk == 0;

      for (final exponent in chunkedExponents.indexed) {
        final density = densityMap?.at(exponent.$1) ?? true;
        if (density) {
          final exp = exponent.$2;
          switch (exp) {
            case ChunkedExponentZero():
              baseSource.skip(1);
              break;
            case ChunkedExponentOne():
              if (handleTrivial) {
                acc += baseSource.next();
              } else {
                baseSource.skip(1);
              }
              break;
            case ChunkedExponentChunks(:final chunks):
              final e = chunks[chunk];
              if (e != 0) {
                buckets[e - 1] += baseSource.next();
              } else {
                baseSource.skip(1);
              }
          }
        }
      }

      // Summation by parts
      BASE runningSum = baseSource.identity();
      for (final bucket in buckets.reversed) {
        runningSum += bucket;
        acc += runningSum;
      }

      return acc;
    }

    // Chunk exponents
    final chunkedExponents =
        exponents.map((e) => e.chunks(c)).toList(growable: false);

    // Compute parts (sequential; can be parallelized with isolates)
    final parts = <BASE>[];

    for (int bit = 0, chunk = 0; bit < JubJubFqConst.bits; bit += c, chunk++) {
      parts.add(
        computeChunk(source, densityMap, chunkedExponents, chunk),
      );
    }

    // Fold results (reverse order)
    BASE acc = source.identity();
    for (final part in parts.reversed) {
      for (int i = 0; i < c; i++) {
        acc = acc.double();
      }
      acc = acc + part;
    }

    return acc;
  }

  static BASE multiexp<BASE extends Bls12NativePoint<BASE>,
          G extends Bls12NativeAffinePoint<BASE>>(GSource<BASE, G> source,
      DensityTracker? densityMap, List<Exponent> exponents) {
    int c = 3;
    if (exponents.length >= 32) {
      c = IntUtils.log(exponents.length.toDouble()).ceil();
    }
    assert(densityMap == null || densityMap.length == exponents.length);
    return _multiexpInner(source, densityMap, exponents, c);
  }
}

abstract class GSource<BASE extends Bls12NativePoint<BASE>,
    AFF extends Bls12NativeAffinePoint<BASE>> {
  final List<AFF> points;
  final int start;
  const GSource({required this.points, required this.start});
  GSourceBuilder<BASE, AFF> builder();
  BASE identity();
}

class G1Source extends GSource<G1NativeProjective, G1NativeAffinePoint> {
  G1Source({required super.points, required super.start});

  @override
  GSourceBuilder<G1NativeProjective, G1NativeAffinePoint> builder() {
    return GSourceBuilder(this);
  }

  @override
  G1NativeProjective identity() {
    return G1NativeProjective.identity();
  }
}

class G2Source extends GSource<G2NativeProjective, G2NativeAffinePoint> {
  G2Source({required super.points, required super.start});
  @override
  GSourceBuilder<G2NativeProjective, G2NativeAffinePoint> builder() {
    return GSourceBuilder(this);
  }

  @override
  G2NativeProjective identity() {
    return G2NativeProjective.identity();
  }
}

class GSourceBuilder<BASE extends Bls12NativePoint<BASE>,
    AFF extends Bls12NativeAffinePoint<BASE>> {
  final GSource<BASE, AFF> source;
  int _index;
  GSourceBuilder(this.source) : _index = source.start;
  BASE identity() => source.identity();
  AFF next() {
    if (source.points.length <= _index) {
      throw BellmanException.operationFailed("next",
          reason: "GIndex out of range.");
    }
    final p = source.points[_index];
    if (p.isIdentity()) {
      throw BellmanException.operationFailed("next", reason: "Invalid point.");
    }
    _index += 1;
    return p;
  }

  void skip(int skip) {
    if (source.points.length <= _index) {
      throw BellmanException.operationFailed("next",
          reason: "GIndex out of range.");
    }

    _index += skip;
  }
}

class DensityTracker {
  final List<bool> _bv;
  DensityTracker() : _bv = [];

  factory DensityTracker.defaultValue() {
    return DensityTracker();
  }
  void addElement() {
    _bv.add(false);
  }

  void inc(int idx) {
    if (!_bv[idx]) {
      _bv[idx] = true;
    }
  }

  bool at(int index) => _bv[index];

  int getTotalDensity() {
    int count = 0;
    for (final v in _bv) {
      if (v) count++;
    }
    return count;
  }

  List<bool> toList() => _bv;
  int get length => _bv.length;
}

sealed class ChunkedExponent {
  const ChunkedExponent();
}

class ChunkedExponentZero extends ChunkedExponent {}

class ChunkedExponentOne extends ChunkedExponent {}

class ChunkedExponentChunks extends ChunkedExponent {
  final List<int> chunks;
  const ChunkedExponentChunks(this.chunks);
}

sealed class Exponent {
  const Exponent();
  factory Exponent.fromScalar(JubJubNativeFq scalar) {
    if (scalar.isZero()) {
      return ExponentZero();
    } else if (scalar == JubJubNativeFq.one()) {
      return ExponentOne();
    }
    return ExponentBits(scalar.toBits());
  }
  ChunkedExponent chunks(int c);
}

class ExponentZero extends Exponent {
  @override
  ChunkedExponent chunks(int c) {
    return ChunkedExponentZero();
  }
}

class ExponentOne extends Exponent {
  @override
  ChunkedExponent chunks(int c) {
    return ChunkedExponentOne();
  }
}

class ExponentBits extends Exponent {
  final List<bool> bits;
  const ExponentBits(this.bits);
  @override
  ChunkedExponent chunks(int c) {
    final List<int> chunkValues = [];
    for (var i = 0; i < bits.length; i += c) {
      int acc = 0;
      for (var j = 0; j < c && i + j < bits.length; j++) {
        if (bits[i + j]) {
          acc |= (1 << j);
        }
      }
      chunkValues.add(acc);
    }
    return ChunkedExponentChunks(chunkValues);
  }
}
