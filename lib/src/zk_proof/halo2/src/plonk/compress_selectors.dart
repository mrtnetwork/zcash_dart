import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:blockchain_utils/utils/numbers/utils/int_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';

class SelectorDescription {
  final int selector;
  final List<bool> activations;
  final int maxDegree;
  const SelectorDescription(
      {required this.selector,
      required this.activations,
      required this.maxDegree});
  static (List<List<PallasNativeFp>>, List<SelectorAssignment>) process(
    List<SelectorDescription> selectors,
    int maxDegree,
    Expression Function() allocateFixedColumn,
  ) {
    if (selectors.isEmpty) {
      return ([], []);
    }

    // All selectors must have the same number of rows
    final int n = selectors.first.activations.length;
    assert(selectors.every((s) => s.activations.length == n));

    final List<List<PallasNativeFp>> combinationAssignments = [];
    final List<SelectorAssignment> selectorAssignments = [];

    // Handle degree-0 selectors first
    selectors = selectors.where((selector) {
      if (selector.maxDegree == 0) {
        final expression = allocateFixedColumn();

        final combinationAssignment = selector.activations
            .map((b) => b ? PallasNativeFp.one() : PallasNativeFp.zero())
            .toList();

        final int combinationIndex = combinationAssignments.length;
        combinationAssignments.add(combinationAssignment);
        selectorAssignments.add(SelectorAssignment(
            selector: selector.selector,
            combinationIndex: combinationIndex,
            expression: expression));

        return false;
      }
      return true;
    }).toList();

    // Build exclusion matrix (lower triangular)
    final List<List<bool>> exclusionMatrix =
        List.generate(selectors.length, (i) => List<bool>.filled(i, false));

    for (int i = 0; i < selectors.length; i++) {
      final rows = selectors[i].activations;
      for (int j = 0; j < i; j++) {
        final other = selectors[j].activations;
        bool conflict = false;
        for (int k = 0; k < rows.length; k++) {
          if (rows[k] && other[k]) {
            conflict = true;
            break;
          }
        }
        if (conflict) {
          exclusionMatrix[i][j] = true;
        }
      }
    }

    // Track which selectors were already added
    final List<bool> added = List<bool>.filled(selectors.length, false);

    for (int i = 0; i < selectors.length; i++) {
      if (added[i]) continue;

      final selector = selectors[i];
      added[i] = true;

      assert(selector.maxDegree <= maxDegree);

      // Degree minus the virtual selector
      int d = selector.maxDegree - 1;

      final List<SelectorDescription> combination = [selector];
      final List<int> combinationAdded = [i];

      // Try to add more selectors
      for (int j = i + 1; j < selectors.length; j++) {
        if (d + combination.length == maxDegree) break;
        if (added[j]) continue;

        // Check exclusion
        bool excluded = false;
        for (final k in combinationAdded) {
          if (exclusionMatrix[j][k]) {
            excluded = true;
            break;
          }
        }
        if (excluded) continue;

        final candidate = selectors[j];
        final int newD = IntUtils.max(d, candidate.maxDegree - 1);
        if (newD + combination.length + 1 > maxDegree) continue;

        d = newD;
        combination.add(candidate);
        combinationAdded.add(j);
        added[j] = true;
      }

      // Compute assignments
      final List<PallasNativeFp> combinationAssignment =
          List.filled(n, PallasNativeFp.zero());
      final int combinationLen = combination.length;
      final int combinationIndex = combinationAssignments.length;
      final Expression query = allocateFixedColumn();

      PallasNativeFp assignedRoot = PallasNativeFp.one();

      for (final sel in combination) {
        // Build substitution expression:
        // q * Π (i - q), i != assignedRoot
        Expression expression = query;
        PallasNativeFp root = PallasNativeFp.one();

        for (int i = 0; i < combinationLen; i++) {
          if (root != assignedRoot) {
            expression = expression * (ExpressionConstant(root) - query);
          }
          root += PallasNativeFp.one();
        }

        // Update combination assignment
        for (int r = 0; r < n; r++) {
          if (sel.activations[r]) {
            combinationAssignment[r] = assignedRoot;
          }
        }
        selectorAssignments.add(SelectorAssignment(
            selector: sel.selector,
            combinationIndex: combinationIndex,
            expression: expression));

        assignedRoot += PallasNativeFp.one();
      }
      combinationAssignments.add(combinationAssignment);
    }

    return (combinationAssignments, selectorAssignments);
  }
}

class SelectorAssignment {
  final int selector;
  final int combinationIndex;
  final Expression expression;
  const SelectorAssignment(
      {required this.selector,
      required this.combinationIndex,
      required this.expression});
}
