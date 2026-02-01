import 'package:blockchain_utils/blockchain_utils.dart';

class PcztUtils {
  static Map<String, List<int>>? mergeProprietary(
    Map<String, List<int>> proprietary,
    Map<String, List<int>> other,
  ) {
    final Map<String, List<int>> newProprietary = proprietary.clone();
    for (final MapEntry(:key, :value) in other.entries) {
      if (proprietary.containsKey(key)) {
        if (!BytesUtils.bytesEqual(value, proprietary[key])) {
          return null;
        }
        continue;
      }
      newProprietary[key] = value.clone();
    }
    return newProprietary;
  }

  static Set<T>? mergeSet<T extends PartialEquality>(
    Set<T> proprietary,
    Set<T> other,
  ) {
    final Set<T> newProprietary = proprietary.clone();
    for (final i in other) {
      final s = proprietary.firstWhereNullable((e) => e == i);
      if (s != null) {
        if (!Equality.deepEqual(i.variables, s.variables)) {
          return null;
        }
        continue;
      }
      newProprietary.add(i);
    }
    return newProprietary;
  }

  static bool canMerge<T>(T? a, T? b) {
    if (b == null || a == null) return true;
    return Equality.deepEqual(a, b);
  }
}
