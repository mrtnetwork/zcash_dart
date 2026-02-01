import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/boolean.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/num.dart';

class GMultipackUtils {
  static void packIntoInputs(BellmanConstraintSystem cs, List<GBoolean> bits) {
    final int capacity = JubJubFqConst.capacity;
    final one = cs.one();
    for (int i = 0; i < bits.length; i += capacity) {
      final chunk = bits.sublist(
          i, (i + capacity <= bits.length) ? i + capacity : bits.length);

      GNum num = GNum.zero();
      JubJubNativeFq coeff = JubJubNativeFq.one();
      for (final bit in chunk) {
        num = num.addBoolWithCoeff(one, bit, coeff);
        coeff = coeff.double();
      }

      final input = cs.allocInput(() => num.getValue());
      cs.enforce((lc) => num.lcMul(JubJubNativeFq.one()), (lc) => lc + one,
          (lc) => lc + input);
    }
  }

  static List<JubJubNativeFq> computeMultipacking(List<bool> bits) {
    final List<JubJubNativeFq> result = [];
    final int capacity = JubJubFqConst.capacity;

    for (var i = 0; i < bits.length; i += capacity) {
      final chunk = bits.sublist(
          i, (i + capacity <= bits.length) ? i + capacity : bits.length);

      JubJubNativeFq cur = JubJubNativeFq.zero();
      JubJubNativeFq coeff = JubJubNativeFq.one();

      for (final bit in chunk) {
        if (bit) {
          cur = cur + coeff;
        }
        coeff = coeff.double();
      }

      result.add(cur);
    }

    return result;
  }
}
