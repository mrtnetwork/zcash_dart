import 'dart:typed_data';
import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:blockchain_utils/helper/helper.dart';
import 'package:blockchain_utils/utils/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';

class Halo2Utils {
  static const int fixedBaseWindowSize = 3;
  static const int numWindows = 85;
  static const int lScalarShort = 64;
  static const int numWindowShort = 22;

  static const H = 1 << fixedBaseWindowSize;
  static BigInt get tQ =>
      BigInt.parse("45560315531506369815346746415080538113");
  static BigInt get tP =>
      BigInt.parse("45560315531419706090280762371685220353");

  static void parallelize<T>(List<T> v, void Function(List<T>, int) f) {
    final n = v.length;
    var numThreads = 1; // Adjust if you want to simulate threads
    var chunk = n ~/ numThreads;
    if (chunk < numThreads) {
      chunk = n;
    }

    for (var chunkNum = 0; chunkNum * chunk < n; chunkNum++) {
      final start = chunkNum * chunk;
      final end = (start + chunk > n) ? n : start + chunk;
      final sublist = v.sublist(start, end);
      f(sublist, start);
    }
  }

  static PallasNativeFp computeInnerProduct(
      List<PallasNativeFp> a, List<PallasNativeFp> b) {
    if (a.length != b.length) {
      throw Halo2Exception.operationFailed("computeInnerProduct",
          reason: "Incorrect array length.");
    }

    PallasNativeFp acc = PallasNativeFp.zero();

    for (int i = 0; i < a.length; i++) {
      acc = acc + (a[i] * b[i]);
    }

    return acc;
  }

  static List<PallasNativeFp> kateDivision(
      List<PallasNativeFp> a, PallasNativeFp b) {
    // Negate the divisor
    b = -b;

    final n = a.length;
    if (n < 2) {
      throw Halo2Exception.operationFailed("kateDivision",
          reason: "Polynomial too short for division.");
    }

    // Initialize quotient vector of length n - 1
    final q = List<PallasNativeFp>.filled(n - 1, PallasNativeFp.zero(),
        growable: true);

    PallasNativeFp tmp = PallasNativeFp.zero();

    // Iterate backwards over q and a
    for (int i = n - 2, j = n - 1; i >= 0; i--, j--) {
      // lead_coeff = r - tmp
      var leadCoeff = a[j] - tmp;

      // Store in quotient
      q[i] = leadCoeff;

      // tmp = leadCoeff * b
      tmp = leadCoeff * b;
    }

    return q;
  }

  static int log2Floor(int num) {
    assert(num > 0);

    var pow = 0;
    while ((1 << (pow + 1)) <= num) {
      pow += 1;
    }

    return pow;
  }

  static int bitReverse(int n, int l) {
    var r = 0;
    for (var i = 0; i < l; i++) {
      r = (r << 1) | (n & 1);
      n >>= 1;
    }
    return r;
  }

  static void bestFft(
      List<VestaNativePoint> a, PallasNativeFp omega, int logN) {
    final n = a.length;
    assert(n == (1 << logN));
    for (var k = 0; k < n; k++) {
      final rk = bitReverse(k, logN);
      if (k < rk) {
        final temp = a[k];
        a[k] = a[rk];
        a[rk] = temp;
      }
    }

    // Precompute twiddle factors
    final List<PallasNativeFp> twiddles = [];
    var w = PallasNativeFp.one();
    for (var i = 0; i < n ~/ 2; i++) {
      twiddles.add(w);
      w *= omega;
    }
    recursiveButterflyArithmetic(a, 0, n, 1, twiddles);
  }

  static void recursiveButterflyArithmetic(List<VestaNativePoint> a, int start,
      int n, int twiddleChunk, List<PallasNativeFp> twiddles) {
    if (n == 2) {
      final t = a[start + 1];
      a[start + 1] = a[start];
      a[start] += t;
      a[start + 1] -= t;
    } else {
      final half = n ~/ 2;
      recursiveButterflyArithmetic(a, start, half, twiddleChunk * 2, twiddles);
      recursiveButterflyArithmetic(
          a, start + half, half, twiddleChunk * 2, twiddles);
      final t = a[start + half];
      a[start + half] = a[start];
      a[start] += t;
      a[start + half] -= t;
      for (var i = 1; i < half; i++) {
        final twiddleIndex = (i) * twiddleChunk;
        var t = a[start + half + i] * twiddles[twiddleIndex];
        final aVal = a[start + i];
        a[start + i] += t;
        a[start + half + i] = aVal - t;
      }
    }
  }

  static void bestFftField(
      List<PallasNativeFp> a, PallasNativeFp omega, int logN) {
    final n = a.length;
    assert(n == (1 << logN));

    for (var k = 0; k < n; k++) {
      final rk = bitReverse(k, logN);
      if (k < rk) {
        final temp = a[k];
        a[k] = a[rk];
        a[rk] = temp;
      }
    }

    // Precompute twiddle factors
    final List<PallasNativeFp> twiddles = [];
    var w = PallasNativeFp.one();
    for (var i = 0; i < n ~/ 2; i++) {
      twiddles.add(w);
      w *= omega;
    }
    recursiveButterflyArithmeticField(a, 0, n, 1, twiddles);
  }

  static void recursiveButterflyArithmeticField(
    List<PallasNativeFp> a,
    int start,
    int n,
    int twiddleChunk,
    List<PallasNativeFp> twiddles,
  ) {
    if (n == 2) {
      final t = a[start + 1];
      a[start + 1] = a[start];
      a[start] += t;
      a[start + 1] -= t;
    } else {
      final half = n ~/ 2;
      recursiveButterflyArithmeticField(
          a, start, half, twiddleChunk * 2, twiddles);
      recursiveButterflyArithmeticField(
          a, start + half, half, twiddleChunk * 2, twiddles);
      final t = a[start + half];
      a[start + half] = a[start];
      a[start] += t;
      a[start + half] -= t;
      for (var i = 1; i < half; i++) {
        final twiddleIndex = (i) * twiddleChunk;
        var t = a[start + half + i] * twiddles[twiddleIndex];
        final aVal = a[start + i];
        a[start + i] += t;
        a[start + half + i] = aVal - t;
      }
    }
  }

  static PallasNativeFp evalPolynomial(
      List<PallasNativeFp> poly, PallasNativeFp point) {
    var acc = PallasNativeFp.zero();

    for (var i = poly.length - 1; i >= 0; i--) {
      acc = acc * point + poly[i];
    }

    return acc;
  }

  static List<PallasNativeFp> lagrangeInterpolate(
      List<PallasNativeFp> points, List<PallasNativeFp> evals) {
    if (points.length != evals.length) {
      throw Halo2Exception.operationFailed("lagrangeInterpolate",
          reason: "Invalid points length.");
    }
    final n = points.length;

    if (n == 1) {
      // Constant polynomial
      return [evals[0]];
    }

    // Compute denominators (x_j - x_k) for j != k
    final denoms = List<List<PallasNativeFp>>.generate(n, (j) {
      final list = <PallasNativeFp>[];
      for (var k = 0; k < n; k++) {
        if (k != j) {
          list.add(points[j] - points[k]);
        }
      }
      return list;
    });

    // Invert all denominators in place
    for (var denomList in denoms) {
      batchInvert(denomList); // You need to implement batchInvert
    }

    // Initialize final polynomial coefficients
    final finalPoly = List<PallasNativeFp>.filled(n, PallasNativeFp.zero());

    for (var j = 0; j < n; j++) {
      final denomList = denoms[j];
      final eval = evals[j];

      var tmp = <PallasNativeFp>[PallasNativeFp.one()];
      int denomIndex = 0;
      for (var k = 0; k < n; k++) {
        if (k == j) continue;

        final xk = points[k];
        final denom = denomList[denomIndex++];
        final nextProduct =
            List<PallasNativeFp>.filled(tmp.length + 1, PallasNativeFp.zero());

        for (var i = 0; i < tmp.length; i++) {
          nextProduct[i] += tmp[i] * (-denom * xk);
          nextProduct[i + 1] += tmp[i] * denom;
        }

        tmp = nextProduct;
      }
      if (tmp.length != n) {
        throw Halo2Exception.operationFailed("lagrangeInterpolate");
      }
      for (var i = 0; i < n; i++) {
        finalPoly[i] += tmp[i] * eval;
      }
    }

    return finalPoly;
  }

  static PallasNativeFp batchInvert(List<PallasNativeFp> values) {
    var acc = PallasNativeFp.one();
    final tmp = <MapEntry<PallasNativeFp, PallasNativeFp>>[];

    // Forward accumulation
    for (var p in values) {
      tmp.add(MapEntry(acc, p));
      acc = p.isZero() ? acc : acc * p;
    }
    final inv = acc.invert();
    if (inv == null) {
      throw Halo2Exception.operationFailed("batchInvert",
          reason: "Division by zero.");
    }
    acc = inv;
    final allInv = acc;

    // Backward propagation
    for (var entry in tmp.reversed) {
      final prevAcc = entry.key;
      final p = entry.value;
      final skip = p.isZero();
      final t = prevAcc * acc;
      acc = skip ? acc : acc * p;
      final idx = values.indexOf(p);
      values[idx] = skip ? p : t;
    }

    return allInv;
  }

  static VestaNativePoint bestMultiexp(
    List<PallasNativeFp> coeffs,
    List<VestaAffineNativePoint> bases,
  ) {
    return multiexpSerial(coeffs, bases, VestaNativePoint.identity());
  }

  static VestaNativePoint multiexpSerial(
    List<PallasNativeFp> coeffs,
    List<VestaAffineNativePoint> bases,
    VestaNativePoint acc,
  ) {
    if (coeffs.length != bases.length) {
      throw Halo2Exception.operationFailed("multiexpSerial",
          reason: "Mismatch between coeffs and bases length.");
    }
    // Convert coefficients to bytes representation
    final coeffsBytes = coeffs.map((a) => a.toBytes()).toList();
    final int c;
    if (bases.length < 4) {
      c = 1;
    } else if (bases.length < 32) {
      c = 3;
    } else {
      c = (IntUtils.log(bases.length.toDouble()) / 1.0).ceil(); // natural log
    }

    int getAt(int segment, int c, List<int> bytes) {
      final skipBits = segment * c;
      final skipBytes = skipBits ~/ 8;

      if (skipBytes >= 32) return 0;

      final v = List<int>.filled(8, 0);
      for (var i = 0; i < v.length && i + skipBytes < bytes.length; i++) {
        v[i] = bytes[i + skipBytes];
      }

      var tmp = BigintUtils.fromBytes(v, byteOrder: Endian.little);
      tmp = (tmp >> skipBits - (skipBytes * 8));
      tmp %= BigInt.one << c;
      return tmp.asU64.toIntOrThrow;
    }

    final segments = (256 ~/ c) + 1;

    for (var currentSegment = segments - 1;
        currentSegment >= 0;
        currentSegment--) {
      for (var i = 0; i < c; i++) {
        acc = acc.double();
      }

      final b = List<_Bucket>.generate((1 << c) - 1, (_) => _Bucket._());

      for (var i = 0; i < coeffsBytes.length; i++) {
        final coeff = getAt(currentSegment, c, coeffsBytes[i]);
        if (coeff != 0) {
          b[coeff - 1].addAffine(bases[i]);
        }
      }

      // Summation by parts
      var runningSum = VestaNativePoint.identity();
      for (var exp in b.reversed) {
        runningSum = exp.add(runningSum);
        acc += runningSum;
      }
    }
    return acc;
  }

  /// For each fixed base, compute its scalar multiples in 3-bit windows.
  /// Each window contains H = 8 points.
  static List<List<PallasAffineNativePoint>> computeWindowTable(
    PallasAffineNativePoint base,
    int numWindows,
  ) {
    final List<List<PallasAffineNativePoint>> windowTable = [];
    final hQ = VestaNativeFq.from(H);
    // Generate window table entries for all windows except the last
    for (int w = 0; w < numWindows - 1; w++) {
      final List<PallasAffineNativePoint> window = List.generate(H, (k) {
        final scalar = VestaNativeFq.from(k + 2) * hQ.pow(BigInt.from(w));
        return (base * scalar).toAffine();
      });
      windowTable.add(window);
    }
    final two = VestaNativeFq.from(2);
    // Compute sum = Σ_{j=0..num_windows-2} 2^{3j + 1}
    var sum = VestaNativeFq.zero();
    for (int j = 0; j < numWindows - 1; j++) {
      sum += two.pow(BigInt.from(fixedBaseWindowSize * j + 1));
    }

    // Generate window table for the last window
    final int w = numWindows - 1;
    final List<PallasAffineNativePoint> lastWindow = List.generate(H, (k) {
      // scalar = k * (8^w) - sum
      final scalar = VestaNativeFq.from(k) * hQ.pow(BigInt.from(w)) - sum;

      return (base * scalar).toAffine();
    });
    windowTable.add(lastWindow);
    return windowTable;
  }

  /// For each window, interpolate the x-coordinate.
  /// Pre-computes and stores the coefficients of the interpolation polynomial.
  static List<List<PallasNativeFp>> computeLagrangeCoeffs(
      PallasAffineNativePoint base, int numWindows) {
    // Interpolation points: k ∈ [0..H)
    final List<PallasNativeFp> points =
        List.generate(H, (i) => PallasNativeFp.from(i));

    // Compute window table
    final windowTable = computeWindowTable(base, numWindows);

    // For each window, interpolate x-coordinates
    return windowTable.map((windowPoints) {
      // Extract x-coordinates of points in this window
      final List<PallasNativeFp> xWindowPoints =
          windowPoints.map((point) => point.x).toList();

      // Compute Lagrange interpolation coefficients
      final coeffs = lagrangeInterpolate(points, xWindowPoints);

      return coeffs;
    }).toList();
  }

  static Expression boolCheck(Expression value) {
    return rangeCheck(value, 2);
  }

  /// i.e. 0 ≤ word < range.
  static Expression rangeCheck(Expression word, int range) {
    Expression acc = word;

    for (int i = 1; i < range; i++) {
      acc = acc * (ExpressionConstant(PallasNativeFp.from(i)) - word);
    }

    return acc;
  }

  static Expression ternary(Expression a, Expression b, Expression c) {
    final oneMinusA = ExpressionConstant(PallasNativeFp.one()) - a;
    return a * b + oneMinusA * c;
  }

  static PallasNativeFp bitrangeSubset(
      PallasNativeFp fieldElem, int start, int end) {
    if (end > PallasFPConst.numBits) {
      throw Halo2Exception.operationFailed("bitrangeSubset",
          reason: "Bitrange end exceeds field element size.");
    }

    final bits = fieldElem.toBits(); // List<bool> in little-endian order
    final subset = bits.sublist(start, end).reversed;
    final one = PallasNativeFp.one();
    PallasNativeFp acc = PallasNativeFp.zero();
    for (final bit in subset) {
      acc = acc.double();
      if (bit) acc += one;
    }

    return acc;
  }

  /// Decompose a word `alpha` into `windowNumBits` bits (little-endian)
  /// For a window size of `w`, this returns [k0, ..., kn] where each `ki`
  /// is a `w`-bit value, and `scalar = k0 + k1 * w + ... + kn * w^n`.
  ///
  /// Throws if `windowNumBits > 8`.
  static List<int> decomposeWord<F extends PastaNativeFieldElement<F>>(
    F word,
    int wordNumBits,
    int windowNumBits,
  ) {
    if (windowNumBits > 8) {
      throw Halo2Exception.operationFailed("decomposeWord",
          reason: "Incorrect bit length.");
    }

    // Pad bits to multiple of windowNumBits
    final padding =
        (windowNumBits - (wordNumBits % windowNumBits)) % windowNumBits;

    // Get the bits in little-endian order
    final bits = <bool>[
      ...word.toBits().take(wordNumBits),
      ...List<bool>.filled(padding, false),
    ];

    if (bits.length != wordNumBits + padding) {
      throw Halo2Exception.operationFailed("decomposeWord",
          reason: "Incorrect bit length.");
    }

    // Convert chunks to integers
    final result = <int>[];
    for (var i = 0; i < bits.length; i += windowNumBits) {
      final chunk = bits.sublist(i, i + windowNumBits);
      var value = 0;
      for (var b in chunk.reversed) {
        value = (value << 1) + (b ? 1 : 0);
      }
      result.add(value);
    }

    return result;
  }
}

class _Bucket {
  VestaAffineNativePoint? affine;
  VestaNativePoint? projective;
  _Bucket._();

  void addAffine(VestaAffineNativePoint other) {
    final affine = this.affine;
    final projective = this.projective;
    if (affine == null && projective == null) {
      this.affine = other;
    } else if (affine != null) {
      this.projective = affine + other;
      this.affine = null;
    } else if (projective != null) {
      this.projective = projective + other;
    }
  }

  VestaNativePoint add(VestaNativePoint other) {
    final affine = this.affine;
    final projective = this.projective;
    if (affine == null && projective == null) return other;
    if (affine != null) return other + affine;
    return other + projective!;
  }
}
