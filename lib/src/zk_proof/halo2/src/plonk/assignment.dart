import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/permutation.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

class PlonkAssembly with Assignment {
  final int k;
  final List<Polynomial<Assigned, LagrangeCoeff>> fixed;
  final PermutationAssembly permutation;
  final List<List<bool>> selectors;
  final ComparableIntRange usableRows;
  const PlonkAssembly(
      {required this.k,
      required this.fixed,
      required this.permutation,
      required this.selectors,
      required this.usableRows});

  @override
  void enableSelector(Selector selector, int row) {
    if (!usableRows.contains(row)) {
      throw Halo2Exception.operationFailed("enableSelector",
          reason: "Not enough rows available.");
    }
    selectors[selector.offset][row] = true;
  }

  @override
  PallasNativeFp? queryInstance(Column<Instance> column, int row) {
    if (!usableRows.contains(row)) {
      throw Halo2Exception.operationFailed("queryInstance",
          reason: "Not enough rows available.");
    }

    // There is no instance in this context.
    return null;
  }

  @override
  void assignAdvice(Column<Advice> column, int row, Assigned? Function() to) {}

  @override
  void assignFixed(Column<Fixed> column, int row, Assigned? Function() to) {
    if (!usableRows.contains(row)) {
      throw Halo2Exception.operationFailed("assignFixed",
          reason: "Not enough rows available.");
    }

    final col = fixed.elementAtOrNull(column.index);
    if (col == null) {
      throw Halo2Exception.operationFailed("assignFixed",
          reason: "Bounds failure.");
    }
    final assign = to();
    if (assign == null) {
      throw Halo2Exception.operationFailed("assignFixed");
    }
    col.values[row] = assign;
  }

  @override
  void copy(
    Column<Any> leftColumn,
    int leftRow,
    Column<Any> rightColumn,
    int rightRow,
  ) {
    if (!usableRows.contains(leftRow) || !usableRows.contains(rightRow)) {
      throw Halo2Exception.operationFailed("copy",
          reason: "Not enough rows available.");
    }

    permutation.copy(leftColumn, leftRow, rightColumn, rightRow);
  }

  @override
  void fillFromRow(Column<Fixed> column, int fromRow, Assigned? to) {
    if (!usableRows.contains(fromRow)) {
      throw Halo2Exception.operationFailed("fillFromRow",
          reason: "Not enough rows available.");
    }

    final col = fixed.elementAtOrNull(column.index);
    if (col == null) {
      throw Halo2Exception.operationFailed("fillFromRow",
          reason: "Bounds failure.");
    }
    if (to == null) {
      throw Halo2Exception.operationFailed("fillFromRow");
    }
    final filler = to;
    for (final row in usableRows.skip(fromRow)) {
      col.values[row] = filler;
    }
  }
}
