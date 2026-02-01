import 'package:blockchain_utils/blockchain_utils.dart';

import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';

class RangeConstrained<F extends Object?> {
  final F inner;
  final int numBits;
  const RangeConstrained(this.inner, this.numBits);
  static RangeConstrained<PallasNativeFp?> bitrangeOf(
      PallasNativeFp? value, int start, int end) {
    final numBits = end - start;
    if (value == null) {
      return RangeConstrained(value, numBits);
    }
    return RangeConstrained(
        Halo2Utils.bitrangeSubset(value, start, end), numBits);
  }
}

class RangeConstrainedAssigned
    extends RangeConstrained<AssignedCell<PallasNativeFp>> {
  RangeConstrainedAssigned(super.inner, super.numBits);
  RangeConstrained<PallasNativeFp?> value() =>
      RangeConstrained(inner.value, numBits);
}
