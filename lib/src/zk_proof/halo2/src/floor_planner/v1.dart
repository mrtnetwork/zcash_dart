import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/circuit.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/floor_planner/strategy.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

class V1Plan {
  final Assignment cs;
  List<int> regions;
  final List<(Assigned, Cell)> constants;
  final List<TableColumn> tableColumn;
  V1Plan(
      {required this.cs,
      required this.regions,
      required this.constants,
      required this.tableColumn});

  static void synthesize(
      {required Assignment cs,
      required OrchardCircuit circuit,
      required OrchardCircuitConfig config,
      required List<Column<Fixed>> constants,
      required ZCashCryptoContext context}) {
    // First pass: measure the regions within the OrchardCircuit.
    final measure = MeasurementPass([]);
    OrchardCircuit.defaultConfig().synthesize(config, V1Pass(measure));

    // Planning:
    // - LeafPosition the regions.
    final (regions, columnAllocations) =
        FloorPlannerUtils.slotInBiggestAdviceFirst(measure.regions);
    final plan =
        V1Plan(cs: cs, constants: [], regions: regions, tableColumn: []);
    // - Determine how many rows our planned OrchardCircuit will require.
    final firstUnassignedRow = columnAllocations.values
        .map((a) => a.unboundedIntervalStart())
        .fold<int>(0, (a, b) => a > b ? a : b);

    // - LeafPosition the constants within those rows.
    final fixedAllocations = constants.map((c) {
      final key = RegionColumnColumn(c.toAny());
      final allocations = columnAllocations[key] ?? AllocationsRegion();
      return (c, allocations);
    }).toList();

    Iterable<(Column<Fixed>, int)> constantPositions() sync* {
      for (final (c, a) in fixedAllocations) {
        for (final e in a.freeIntervals(0, firstUnassignedRow)) {
          final range = e.range();
          if (range != null) {
            for (int i = range.start; i < range.end; i++) {
              yield (c, i);
            }
          }
        }
      }
    }

    circuit.synthesize(config, V1Pass(AssignmentPass(plan)));

    // - Assign the constants.
    if (constantPositions().length < plan.constants.length) {
      throw Halo2Exception.operationFailed("synthesize",
          reason: "Not enough columns for constants.");
    }

    final constIter = constantPositions().iterator;
    final planConstIter = plan.constants.iterator;

    while (constIter.moveNext() && planConstIter.moveNext()) {
      final (fixedColumn, fixedRow) = constIter.current;
      final (value, advice) = planConstIter.current;
      plan.cs.assignFixed(fixedColumn, fixedRow, () => value);
      plan.cs.copy(fixedColumn.toAny(), fixedRow, advice.column,
          plan.regions[advice.regionIndex] + advice.rowOffset);
    }
  }
}

class MeasurementPass implements Pass {
  final List<RegionShape> regions;
  const MeasurementPass(this.regions);

  AR assignRegion<AR>(AR Function(Region) assignment) {
    final regionIndex = regions.length;
    final shape = RegionShape(regionIndex: regionIndex, columns: {});
    final result = assignment(Region(shape));
    regions.add(shape);
    return result;
  }
}

class AssignmentPass implements Pass {
  final V1Plan plan;

  /// Counter tracking which region we need to assign next.
  int regionIndex = 0;

  AssignmentPass(this.plan);

  /// Corresponds to `assign_region`
  AR assignRegion<AR>(
    AR Function(Region region) assignment,
  ) {
    // Get the next region we are assigning.
    final currentRegionIndex = regionIndex;
    regionIndex += 1;
    final region = V1Region(plan: plan, regionIndex: currentRegionIndex);
    final result = assignment(Region(region));
    return result;
  }

  static int computeTableLengths(
    Map<TableColumn, (Assigned?, List<bool>)> defaultAndAssigned,
  ) {
    final columnLengths = <TableColumn, int>{};

    // Compute length of each column and check all rows are assigned
    for (final entry in defaultAndAssigned.entries) {
      final col = entry.key;
      final assigned = entry.value.$2;
      if (assigned.isEmpty) {
        throw Halo2Exception.operationFailed("computeTableLengths",
            reason: "column not assigned.");
      }
      if (!assigned.every((b) => b)) {
        throw Halo2Exception.operationFailed("computeTableLengths",
            reason: "column not assigned.");
      }

      columnLengths[col] = assigned.length;
    }
    int firstLen = 0;

    // Ensure all columns have the same length
    for (final entry in columnLengths.entries) {
      final colLen = entry.value;
      if (firstLen == 0 || firstLen == colLen) {
        firstLen = colLen;
      } else {
        throw Halo2Exception.operationFailed("computeTableLengths",
            reason: "Invalid column length.");
      }
    }

    return firstLen;
  }

  /// Corresponds to `assign_table`
  AR assignTable<AR>(
    AR Function(TableLayouter table) assignment,
  ) {
    final table = SimpleTableLayouter(
      cs: plan.cs,
      usedColumns: plan.tableColumn,
    );

    final result = assignment(table);

    final defaultAndAssigned = table.defaultAndAssigned;

    // Check that all table columns have the same length `firstUnused`,
    // and all cells up to that length are assigned.
    final firstUnused = computeTableLengths(defaultAndAssigned);

    // Record these columns so that we can prevent them from being used again.
    for (final column in defaultAndAssigned.keys) {
      plan.tableColumn.add(column);
    }

    for (final entry in defaultAndAssigned.entries) {
      final col = entry.key;
      final defaultVal = entry.value.$1;

      // defaultVal must be non-null (mirrors Rust invariant)
      plan.cs.fillFromRow(col.inner, firstUnused, defaultVal);
    }

    return result;
  }

  /// Corresponds to `constrain_instance`
  void constrainInstance(
    Cell cell,
    Column<Instance> instance,
    int row,
  ) {
    plan.cs.copy(
      cell.column,
      plan.regions[cell.regionIndex] + cell.rowOffset,
      instance.toAny(),
      row,
    );
  }
}

class V1Region implements RegionLayouter {
  final V1Plan plan;

  final int regionIndex;
  const V1Region({required this.plan, required this.regionIndex});

  int _absoluteRow(int offset) {
    return plan.regions[regionIndex] + offset;
  }

  @override
  void enableSelector(Selector selector, int offset) {
    plan.cs.enableSelector(selector, _absoluteRow(offset));
  }

  @override
  Cell assignAdvice(
    Column<Advice> column,
    int offset,
    Assigned? Function() to,
  ) {
    plan.cs.assignAdvice(column, _absoluteRow(offset), to);
    return Cell(
        regionIndex: regionIndex, rowOffset: offset, column: column.toAny());
  }

  @override
  Cell assignAdviceFromConstant(
      Column<Advice> column, int offset, Assigned constant) {
    final cell = assignAdvice(column, offset, () => constant);
    constrainConstant(cell, constant);
    return cell;
  }

  @override
  (Cell, PallasNativeFp?) assignAdviceFromInstance(
    Column<Instance> instance,
    int row,
    Column<Advice> advice,
    int offset,
  ) {
    final value = plan.cs.queryInstance(instance, row);
    final cell = assignAdvice(
        advice, offset, () => value == null ? null : Assigned.from(value));
    assert(cell.regionIndex == regionIndex);
    plan.cs.copy(cell.column, plan.regions[cell.regionIndex] + cell.rowOffset,
        instance.toAny(), row);
    return (cell, value);
  }

  @override
  PallasNativeFp? instanceValue(Column<Instance> instance, int row) {
    return plan.cs.queryInstance(instance, row);
  }

  @override
  Cell assignFixed(Column<Fixed> column, int offset, Assigned? Function() to) {
    plan.cs.assignFixed(column, _absoluteRow(offset), to);
    return Cell(
        regionIndex: regionIndex, rowOffset: offset, column: column.toAny());
  }

  @override
  void constrainConstant(Cell cell, Assigned constant) {
    plan.constants.add((constant, cell));
  }

  @override
  void constrainEqual(Cell left, Cell right) {
    plan.cs.copy(left.column, plan.regions[left.regionIndex] + left.rowOffset,
        right.column, plan.regions[right.regionIndex] + right.rowOffset);
  }
}

sealed class Pass {
  const Pass();
}

class V1Pass implements Layouter {
  final Pass pass;

  const V1Pass(this.pass);

  @override
  AR assignRegion<AR>(
    AR Function(Region region) assignment,
  ) {
    switch (pass) {
      case MeasurementPass pass:
        return pass.assignRegion(assignment);

      case AssignmentPass pass:
        return pass.assignRegion(assignment);
    }
  }

  @override
  void assignTable(void Function(TableLayouter table) assignment) {
    switch (pass) {
      case MeasurementPass():
        return;

      case AssignmentPass pass:
        pass.assignTable(assignment);
        return;
    }
  }

  @override
  void constrainInstance(Cell cell, Column<Instance> instance, int row) {
    switch (pass) {
      case MeasurementPass():
        return;
      case AssignmentPass pass:
        pass.constrainInstance(cell, instance, row);
        return;
    }
  }
}
