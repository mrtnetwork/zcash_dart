import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/domain.dart';

class BellmanUtils {
  static void bestFFT(List<AssignableFq> a, JubJubNativeFq omega, int logN) {
    // Dart: ignore parallelism for now
    serialFFT(a, omega, logN);
  }

  static void serialFFT(List<AssignableFq> a, JubJubNativeFq omega, int logN) {
    int bitReverse(int n, int l) {
      int r = 0;
      for (int i = 0; i < l; i++) {
        r = (r << 1) | (n & 1);
        n >>= 1;
      }
      return r;
    }

    final n = a.length;
    assert(n == (1 << logN));

    // Bit-reversal permutation
    for (int k = 0; k < n; k++) {
      final rk = bitReverse(k, logN);
      if (k < rk) {
        final tmp = a[k];
        a[k] = a[rk];
        a[rk] = tmp;
      }
    }

    int m = 1;
    for (int s = 0; s < logN; s++) {
      final wM = omega.pow(BigInt.from(n ~/ (2 * m)));

      int k = 0;
      while (k < n) {
        JubJubNativeFq w = JubJubNativeFq.one();
        for (int j = 0; j < m; j++) {
          final t = a[k + j + m];
          t * w;
          final tmp = a[k + j].clone();
          tmp - t;
          a[k + j + m] = tmp;
          a[k + j] + t;
          w = w * wM;
        }
        k += 2 * m;
      }
      m *= 2;
    }
  }
}
