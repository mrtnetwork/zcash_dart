import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

abstract mixin class RegionLayouter {
  const RegionLayouter();

  /// Enables a selector at the given offset.
  void enableSelector(
    Selector selector,
    int offset,
  );

  /// Assign an advice column value (witness)
  Cell assignAdvice(
    Column<Advice> column,
    int offset,
    Assigned? Function() to,
  );

  /// Assigns a constant value to the column `advice` at `offset`
  Cell assignAdviceFromConstant(
    Column<Advice> column,
    int offset,
    Assigned constant,
  );

  /// Assign the value of the instance column's cell at absolute location `row`
  ///
  /// Returns the advice cell and its value if known.
  (Cell, PallasNativeFp?) assignAdviceFromInstance(
    Column<Instance> instance,
    int row,
    Column<Advice> advice,
    int offset,
  );

  /// Returns the value of the instance column's cell at absolute location `row`.
  PallasNativeFp? instanceValue(
    Column<Instance> instance,
    int row,
  );

  /// Assigns a fixed value
  Cell assignFixed(
    Column<Fixed> column,
    int offset,
    Assigned? Function() to,
  );

  /// Constrains a cell to have a constant value.
  void constrainConstant(
    Cell cell,
    Assigned constant,
  );

  /// Constraint two cells to have the same value.
  void constrainEqual(
    Cell left,
    Cell right,
  );
}

abstract mixin class Layouter {
  /// Assigns a region of gates.
  ///
  /// `name` returns the region name.
  /// `assignment` is a closure receiving a RegionLayouter.
  AR assignRegion<AR>(
    AR Function(Region region) assignment,
  );

  /// Assigns a table region.
  void assignTable(void Function(TableLayouter) assignment);

  /// Constrains a cell to equal an instance column at a row.
  void constrainInstance(
    Cell cell,
    Column<Instance> column,
    int row,
  );
}

abstract mixin class TableLayouter {
  void assignCell(
    TableColumn column,
    int offset,
    Assigned? Function() to,
  );
}

sealed class RegionColumn with Equality implements Comparable<RegionColumn> {
  const RegionColumn();

  @override
  int compareTo(RegionColumn other) {
    switch ((this, other)) {
      case (
          RegionColumnColumn(:final column),
          RegionColumnColumn(column: final other)
        ):
        return column.compareTo(other);
      case (
          RegionColumnSelector(:final selector),
          RegionColumnSelector(selector: final other)
        ):
        return selector.offset.compareTo(other.offset);
      case (RegionColumnColumn(), RegionColumnSelector()):
        return -1;
      case (RegionColumnSelector(), RegionColumnColumn()):
        return 1;
    }
  }
}

class RegionColumnColumn extends RegionColumn {
  final Column<Any> column;
  const RegionColumnColumn(this.column);

  @override
  List<dynamic> get variables => [column];
}

class RegionColumnSelector extends RegionColumn with Equality {
  final Selector selector;
  const RegionColumnSelector(this.selector);

  @override
  List<dynamic> get variables => [selector];
}

class RegionShape with RegionLayouter, Equality {
  final int regionIndex;
  final Set<RegionColumn> columns;

  int _rowCount;
  int get rowCount => _rowCount;
  @override
  String toString() {
    return "$regionIndex $columns";
  }

  RegionShape({
    required this.regionIndex,
    required this.columns,
    int rowCount = 0,
  }) : _rowCount = rowCount;

  @override
  Cell assignAdvice(
      Column<Advice> column, int offset, Assigned? Function() to) {
    final c = column.toAny();
    columns.add(RegionColumnColumn(c));
    _rowCount = IntUtils.max(_rowCount, offset + 1);

    return Cell(
      regionIndex: regionIndex,
      rowOffset: offset,
      column: c,
    );
  }

  @override
  Cell assignAdviceFromConstant(
      Column<Advice> column, int offset, Assigned constant) {
    return assignAdvice(column, offset, () => null);
  }

  @override
  (Cell, PallasNativeFp?) assignAdviceFromInstance(
      Column<Instance> instance, int row, Column<Advice> advice, int offset) {
    columns.add(RegionColumnColumn(advice.toAny()));
    _rowCount = IntUtils.max(_rowCount, offset + 1);
    return (
      Cell(regionIndex: regionIndex, rowOffset: offset, column: advice.toAny()),
      null
    );
  }

  @override
  Cell assignFixed(Column<Fixed> column, int offset, Assigned? Function() to) {
    columns.add(RegionColumnColumn(column.toAny()));
    _rowCount = IntUtils.max(_rowCount, offset + 1);
    return Cell(
        regionIndex: regionIndex, rowOffset: offset, column: column.toAny());
  }

  @override
  void constrainConstant(Cell cell, Assigned constant) {}

  @override
  void constrainEqual(Cell left, Cell right) {}

  @override
  void enableSelector(Selector selector, int offset) {
    columns.add(RegionColumnSelector(selector));
    _rowCount = IntUtils.max(_rowCount, offset + 1);
  }

  @override
  PallasNativeFp? instanceValue(Column<Instance> instance, int row) {
    return null;
  }

  @override
  List<dynamic> get variables => [regionIndex, columns, _rowCount];
}

class SimpleTableLayouter with TableLayouter {
  final Assignment cs;
  final List<TableColumn> usedColumns;

  /// Maps from a fixed column to a pair (default value, list of assigned rows)
  final Map<TableColumn, (Assigned?, List<bool>)> defaultAndAssigned = {};

  SimpleTableLayouter({
    required this.cs,
    required this.usedColumns,
  });
  @override
  void assignCell(
    TableColumn column,
    int offset,
    Assigned? Function() to,
  ) {
    if (usedColumns.contains(column)) {
      throw Halo2Exception.operationFailed("assignCell",
          reason: "Table already used.");
    }

    // Get or create entry for this column
    defaultAndAssigned.putIfAbsent(column, () => (null, []));

    // Assign value using the constraint system
    Assigned? value;
    cs.assignFixed(
      column.inner,
      offset, // tables are always assigned starting at row 0
      () {
        final res = to();
        value = res;
        return res;
      },
    );
    defaultAndAssigned.update(
      column,
      (m) {
        var (v, o) = m;
        if (v == null && offset == 0) {
          v = value;
        } else if (v != null && offset == 0) {
          throw Halo2Exception.operationFailed("assignCell",
              reason: "Incorrect offset.");
        }
        if (offset > o.length) {
          throw Halo2Exception.operationFailed("assignCell",
              reason: "Incorrect offset.");
        }
        if (offset == o.length) {
          o.add(true);
        } else {
          o[offset] = true;
        }
        return (v, o);
      },
    );
  }
}

abstract mixin class Assignment {
  void enableSelector(Selector selector, int row);
  PallasNativeFp? queryInstance(Column<Instance> column, int row);
  void assignAdvice(Column<Advice> column, int row, Assigned? Function() to);
  void assignFixed(Column<Fixed> column, int row, Assigned? Function() to);
  void copy(Column<Any> leftColumn, int leftRow, Column<Any> rightColumn,
      int rightRow);
  void fillFromRow(Column<Fixed> column, int fromRow, Assigned? to);
}

class Region {
  final RegionLayouter region;
  const Region(this.region);

  /// Enables a selector at the given offset.
  void enableSelector(
    Selector selector,
    int offset,
  ) {
    region.enableSelector(selector, offset);
  }

  AssignedCell<F> assignAdvice<F>(
    Column<Advice> column,
    int offset,
    F? Function() to,
  ) {
    F? value;
    final cell = region.assignAdvice(
      column,
      offset,
      () {
        final v = to();

        final valueF = v == null ? null : Assigned.from(v);
        value = v;
        return valueF;
      },
    );
    return AssignedCell(value: value, cell: cell);
  }

  /// Assigns a constant value to the column `advice` at `offset`
  AssignedCell<F> assignAdviceFromConstant<F>(
    Column<Advice> column,
    int offset,
    F constant,
  ) {
    final cell = region.assignAdviceFromConstant(
        column, offset, Assigned.from(constant));
    return AssignedCell(value: constant, cell: cell);
  }

  AssignedCell<PallasNativeFp> assignAdviceFromInstance(
    Column<Instance> instance,
    int row,
    Column<Advice> advice,
    int offset,
  ) {
    final (cell, value) =
        region.assignAdviceFromInstance(instance, row, advice, offset);
    return AssignedCell(value: value, cell: cell);
  }

  /// Returns the value of the instance column's cell at absolute location `row`.
  PallasNativeFp? instanceValue(
    Column<Instance> instance,
    int row,
  ) =>
      region.instanceValue(instance, row);

  /// Assigns a fixed value
  AssignedCell<F> assignFixed<F>(
    Column<Fixed> column,
    int offset,
    F? Function() to,
  ) {
    F? value;
    final cell = region.assignFixed(
      column,
      offset,
      () {
        final v = to();
        final valueF = v == null ? null : Assigned.from(v);
        value = v;
        return valueF;
      },
    );
    return AssignedCell(value: value, cell: cell);
  }

  /// Constrains a cell to have a constant value.
  void constrainConstant(
    Cell cell,
    Assigned constant,
  ) =>
      region.constrainConstant(cell, constant);

  /// Constraint two cells to have the same value.
  void constrainEqual(
    Cell left,
    Cell right,
  ) =>
      region.constrainEqual(left, right);
}
