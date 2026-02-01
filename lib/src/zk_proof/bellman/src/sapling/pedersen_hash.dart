import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/boolean.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/lookup.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/constants.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/ecc.dart';
import 'package:zcash_dart/src/pedersen_hash/src/hash.dart';

class GPedersenHashUtils {
  static GEdwardsPoint pedersenHash(BellmanConstraintSystem cs,
      Personalization personalization, List<GBoolean> bits) {
    // Convert personalization to constant bools
    List<GBoolean> personalizationBits =
        personalization.getBits().map((bit) => GBooleanConstant(bit)).toList();
    GEdwardsPoint? edwardsResult;
    Iterator<GBoolean> allBits = [...personalizationBits, ...bits].iterator;
    final generator =
        SaplingCircuitConstants.generatePedersenCircuitGenerators();
    Iterator<List<List<(JubJubNativeFq, JubJubNativeFq)>>> segmentGenerators =
        generator.iterator;
    final booleanFalse = GBooleanConstant(false);

    while (allBits.moveNext()) {
      GMontgomeryPoint? segmentResult;
      if (!segmentGenerators.moveNext()) {
        throw BellmanException.operationFailed("pedersenHash",
            reason: "Not enough segment generators");
      }
      List<List<(JubJubNativeFq, JubJubNativeFq)>> segmentWindows =
          segmentGenerators.current;

      while (true) {
        GBoolean a = allBits.current;

        // Get next two bits or false
        GBoolean b = allBits.moveNext() ? allBits.current : booleanFalse;
        GBoolean c = allBits.moveNext() ? allBits.current : booleanFalse;

        // Perform lookup with conditional negation
        final (x, y) = GLookupUtils.lookup3XYWithConditionalNegation(
            cs, [a, b, c], segmentWindows[0]);

        // Convert Montgomery point to twisted Edwards (unchecked)
        final tmpEdwards = GMontgomeryPoint(x, y);

        // Accumulate segment result
        if (segmentResult == null) {
          segmentResult = tmpEdwards;
        } else {
          segmentResult = tmpEdwards.add(cs, segmentResult);
        }

        // Move to next window
        segmentWindows = segmentWindows.sublist(1);
        if (segmentWindows.isEmpty) break;
        // Advance iterator for next outer loop
        if (!allBits.moveNext()) break;
      }
      // Convert segment result into Edwards form
      final toEdward = segmentResult.intoEdwards(cs);

      // Accumulate into total Edwards result
      if (edwardsResult == null) {
        edwardsResult = toEdward;
      } else {
        edwardsResult = toEdward.add(cs, edwardsResult);
      }
    }

    if (edwardsResult == null) {
      throw BellmanException.operationFailed("pedersenHash",
          reason: "Pedersen hash result is null.");
    }

    return edwardsResult;
  }
}
