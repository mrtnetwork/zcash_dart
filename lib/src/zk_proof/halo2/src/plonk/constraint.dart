import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/permutation.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/compress_selectors.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';

class Cell {
  final int regionIndex;
  final int rowOffset;
  final Column<Any> column;
  const Cell(
      {required this.regionIndex,
      required this.rowOffset,
      required this.column});
}

class AssignedCell<V> {
  final V? value;
  final Cell cell;
  const AssignedCell({required this.value, required this.cell});
  bool get hasValue => value != null;
  V getValue() {
    final v = value;
    if (v == null) {
      throw Halo2Exception.operationFailed("getValue",
          reason: "Value not available.");
    }
    return v;
  }

  /// Enables a selector at the given offset.
  AssignedCell<V> copyAdvice(
    Region region,
    Column<Advice> column,
    int offset,
  ) {
    final assignedCell = region.assignAdvice(column, offset, () => value);
    region.constrainEqual(assignedCell.cell, cell);
    return assignedCell;
  }
}

class Selector with Equality, ProtobufEncodableMessage {
  final int offset;
  final bool isSimple;
  const Selector(this.offset, this.isSimple);
  factory Selector.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return Selector(decode.getInt(1), decode.getBool(2));
  }
  void enable({
    required Region region,
    required int offset,
  }) {
    region.enableSelector(this, offset);
  }

  static List<ProtoFieldConfig> get _bufferFields =>
      [ProtoFieldConfig.int32(1), ProtoFieldConfig.bool(2)];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [offset, isSimple];

  @override
  List<dynamic> get variables => [offset, isSimple];
}

class VirtualCell with Equality, ProtobufEncodableMessage {
  final Column<Any> column;
  final Rotation rotation;
  const VirtualCell({required this.column, required this.rotation});
  factory VirtualCell.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return VirtualCell(
        column: Column<Any>.deserialize(decode.getBytes(1)),
        rotation: Rotation(decode.getInt(2)));
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.int32(2),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [column, rotation.location];

  @override
  List<dynamic> get variables => [column, rotation];
}

class Gate with Equality, ProtobufEncodableMessage {
  List<Expression> polys;
  final List<Selector> queriedSelectors;
  final List<VirtualCell> queriedCells;
  Gate(
      {required this.polys,
      required this.queriedSelectors,
      required this.queriedCells});
  factory Gate.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return Gate(
      polys: decode
          .getListOfBytes(1)
          .map((e) => Expression.deserialize(e))
          .toList(),
      queriedSelectors:
          decode.getListOfBytes(2).map((e) => Selector.deserialize(e)).toList(),
      queriedCells: decode
          .getListOfBytes(3)
          .map((e) => VirtualCell.deserialize(e))
          .toList(),
    );
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.repeated(
            fieldNumber: 1, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 2, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 3, elementType: ProtoFieldType.message),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [polys, queriedSelectors, queriedCells];

  @override
  List<dynamic> get variables => [polys, queriedSelectors, queriedCells];
}

class ConstraintSystem with Equality, ProtobufEncodableMessage {
  int _numFixedColumns;
  int _numAdviceColumns;
  int _numInstanceColumns;
  int _numSelectors;
  int get numFixedColumns => _numFixedColumns;
  int get numSelectors => _numSelectors;
  int get numInstanceColumns => _numInstanceColumns;
  int get numAdviceColumns => _numAdviceColumns;

  final List<Column<Fixed>> selectorMap;
  final List<Gate> gates;
  final List<ColumnWithRotation<Advice>> adviceQueries;
  final List<int> _numAdviceQueries;
  final List<ColumnWithRotation<Instance>> instanceQueries;
  final List<ColumnWithRotation<Fixed>> fixedQueries;
  final PermutationArgument permutation;
  List<LookupArgument> lookups;
  final List<Column<Fixed>> constants;
  final int? minimumDegree;
  // final ZCashCryptoContext context;

  String toDebugString() {
    String r = "";
    r += "PinnedConstraintSystem { ";
    r +=
        "num_fixed_columns: $numFixedColumns, num_advice_columns: $_numAdviceColumns, num_instance_columns: $_numInstanceColumns, num_selectors: $_numSelectors, ";
    r +=
        "gates: [${gates.expand((e) => e.polys).map((e) => e.toDebugString()).toList().join(", ")}], ";
    r +=
        "advice_queries: [${adviceQueries.map((e) => e.toDebugString()).toList().join(", ")}], ";
    r +=
        "instance_queries: [${instanceQueries.map((e) => e.toDebugString()).toList().join(", ")}], ";
    r +=
        "fixed_queries: [${fixedQueries.map((e) => e.toDebugString()).toList().join(", ")}], ";
    r += "permutation: ${permutation.toDebugString()}, ";
    r +=
        "lookups: [${lookups.map((e) => e.toDebugString()).toList().join(", ")}], ";
    r +=
        "constants: [${constants.map((e) => e.toDebugString()).toList().join(", ")}], ";
    r += "minimum_degree: ${minimumDegree ?? 'None'} }";
    return r;
  }

  ConstraintSystem({
    required int numFixedColumns,
    required int numAdviceColumns,
    required int numInstanceColumns,
    required int numSelectors,
    required this.selectorMap,
    required this.gates,
    required this.adviceQueries,
    required List<int> numAdviceQueries,
    required this.instanceQueries,
    required this.fixedQueries,
    required this.permutation,
    required this.lookups,
    required this.constants,
    required this.minimumDegree,
  })  : _numAdviceColumns = numAdviceColumns,
        _numAdviceQueries = numAdviceQueries,
        _numSelectors = numSelectors,
        _numFixedColumns = numFixedColumns,
        _numInstanceColumns = numInstanceColumns;

  ConstraintSystem clone() => ConstraintSystem(
        numFixedColumns: numFixedColumns,
        numAdviceColumns: numAdviceColumns,
        numInstanceColumns: numInstanceColumns,
        numSelectors: numSelectors,
        selectorMap: selectorMap.clone(),
        gates: gates.clone(),
        adviceQueries: adviceQueries.clone(),
        numAdviceQueries: _numAdviceQueries.clone(),
        instanceQueries: instanceQueries.clone(),
        fixedQueries: fixedQueries.clone(),
        permutation: permutation.clone(),
        lookups: lookups.clone(),
        constants: constants.clone(),
        minimumDegree: minimumDegree,
      );
  factory ConstraintSystem.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ConstraintSystem(
        numFixedColumns: decode.getInt(1),
        numAdviceColumns: decode.getInt(2),
        numInstanceColumns: decode.getInt(3),
        numSelectors: decode.getInt(4),
        selectorMap: decode
            .getListOfBytes(5, defaultValue: [])
            .map((e) => Column<Fixed>.deserialize(e))
            .toList(),
        gates: decode
            .getListOfBytes(6, defaultValue: [])
            .map((e) => Gate.deserialize(e))
            .toList(),
        adviceQueries: decode
            .getListOfBytes(7, defaultValue: [])
            .map((e) => ColumnWithRotation<Advice>.deserialize(e))
            .toList(),
        numAdviceQueries: decode.getList<int>(8),
        instanceQueries: decode
            .getListOfBytes(9, defaultValue: [])
            .map((e) => ColumnWithRotation<Instance>.deserialize(e))
            .toList(),
        fixedQueries: decode
            .getListOfBytes(10, defaultValue: [])
            .map((e) => ColumnWithRotation<Fixed>.deserialize(e))
            .toList(),
        permutation: PermutationArgument.deserialize(decode.getBytes(11)),
        lookups: decode
            .getListOfBytes(12, defaultValue: [])
            .map((e) => LookupArgument.deserialize(e))
            .toList(),
        constants: decode
            .getListOfBytes(13, defaultValue: [])
            .map((e) => Column<Fixed>.deserialize(e))
            .toList(),
        minimumDegree: decode.getInt(14));
  }

  factory ConstraintSystem.defaultConfig() => ConstraintSystem(
      numFixedColumns: 0,
      numAdviceColumns: 0,
      numInstanceColumns: 0,
      numSelectors: 0,
      selectorMap: [],
      gates: [],
      adviceQueries: [],
      numAdviceQueries: [],
      instanceQueries: [],
      fixedQueries: [],
      permutation: PermutationArgument(),
      lookups: [],
      constants: [],
      minimumDegree: null);

  void enableConstant(Column<Fixed> column) {
    if (!constants.contains(column)) {
      constants.add(column);
      enableEquality(column);
    }
  }

  void enableEquality(Column column) {
    final c = column.toAny();
    queryAnyIndex(c, Rotation.cur());
    permutation.addColumn(c);
  }

  Column<Instance> instanceColumn() {
    final c =
        Column<Instance>(index: _numInstanceColumns, columnType: Instance());
    _numInstanceColumns += 1;
    return c;
  }

  Selector complexSelector() {
    final index = _numSelectors;
    _numSelectors += 1;
    return Selector(index, false);
  }

  int queryFixedIndex(Column<Fixed> column) {
    final c = ColumnWithRotation(column, Rotation.cur());
    final index = fixedQueries.indexOf(c);
    if (!index.isNegative) return index;
    final len = fixedQueries.length;
    fixedQueries.add(c);
    return len;
  }

  int queryAdviceIndex(Column<Advice> column, Rotation at) {
    final c = ColumnWithRotation(column, at);
    final index = adviceQueries.indexOf(c);
    if (!index.isNegative) return index;
    final len = adviceQueries.length;
    adviceQueries.add(c);
    _numAdviceQueries[column.index] += 1;
    return len;
  }

  int queryInstanceIndex(Column<Instance> column, Rotation at) {
    final c = ColumnWithRotation(column, at);
    final index = instanceQueries.indexOf(c);
    if (!index.isNegative) return index;
    final len = instanceQueries.length;
    instanceQueries.add(c);
    return len;
  }

  int queryAnyIndex(Column<Any> column, Rotation at) {
    return switch (column.columnType) {
      final AnyAdvice _ =>
        queryAdviceIndex(Column(index: column.index, columnType: Advice()), at),
      final AnyFixed _ =>
        queryFixedIndex(Column(index: column.index, columnType: Fixed())),
      final AnyInstance _ => queryInstanceIndex(
          Column(index: column.index, columnType: Instance()), at),
    };
  }

  int getAdviceQueryIndex(Column<Advice> column, Rotation at) {
    final c = ColumnWithRotation(column, at);
    final index = adviceQueries.indexOf(c);
    if (!index.isNegative) return index;
    throw Halo2Exception.operationFailed("getAdviceQueryIndex",
        reason: "Query does not exists.");
  }

  int getFixedQueryIndex(Column<Fixed> column, Rotation at) {
    final c = ColumnWithRotation(column, at);
    final index = fixedQueries.indexOf(c);
    if (!index.isNegative) return index;
    throw Halo2Exception.operationFailed("getFixedQueryIndex",
        reason: "Query does not exists.");
  }

  int getInstanceQueryIndex(Column<Instance> column, Rotation at) {
    final c = ColumnWithRotation(column, at);
    final index = instanceQueries.indexOf(c);
    if (!index.isNegative) return index;
    throw Halo2Exception.operationFailed("getInstanceQueryIndex",
        reason: "Query does not exists.");
  }

  int getAnyQueryIndex(Column<Any> column) {
    final current = Rotation.cur();

    return switch (column.columnType) {
      final AnyAdvice _ => getAdviceQueryIndex(
          Column(index: column.index, columnType: Advice()), current),
      final AnyFixed _ => getFixedQueryIndex(
          Column(index: column.index, columnType: Fixed()), current),
      final AnyInstance _ => getInstanceQueryIndex(
          Column(index: column.index, columnType: Instance()), current),
    };
  }

  Column<Advice> adviceColumn() {
    final c = Column<Advice>(columnType: Advice(), index: _numAdviceColumns);
    _numAdviceColumns += 1;
    _numAdviceQueries.add(0);
    return c;
  }

  Selector selector() {
    final index = _numSelectors;
    _numSelectors += 1;
    return Selector(index, true);
  }

  void createGate(
    Constraints Function(VirtualCells meta) constraintsBuilder,
  ) {
    final cells = VirtualCells(this);
    final cs = constraintsBuilder(cells);
    final constraints = cs.getConstraints();
    final queriedSelectors = cells._queriedSelectors;
    final queriedCells = cells._queriedCells;
    if (constraints.isEmpty) {
      throw Halo2Exception.operationFailed("createGate",
          reason: "Gates must contain at least one constraint.");
    }

    gates.add(Gate(
      polys: constraints,
      queriedSelectors: queriedSelectors,
      queriedCells: queriedCells,
    ));
  }

  Column<Fixed> fixedColumn() {
    final c = Column(index: _numFixedColumns, columnType: Fixed());
    _numFixedColumns += 1;
    return c;
  }

  TableColumn lookupTableColumn() => TableColumn(fixedColumn());

  /// Compute the number of blinding factors necessary to perfectly blind
  /// each of the prover's witness polynomials.
  int blindingFactors() {
    // All of the prover's advice columns are evaluated at no more than
    int factors = _numAdviceQueries.isNotEmpty
        ? _numAdviceQueries.reduce((a, b) => a > b ? a : b)
        : 1;
    // distinct points during gate checks.

    // - The permutation argument witness polynomials are evaluated at most 3 times.
    // - Each lookup argument has independent witness polynomials, and they are
    //   evaluated at most 2 times.
    factors = factors < 3 ? 3 : factors;

    // Each polynomial is evaluated at most an additional time during
    // multiopen (at x_3 to produce q_evals):
    factors = factors + 1;

    // h(x) is derived by the other evaluations so it does not reveal
    // anything; in fact it does not even appear in the proof.

    // h(x_3) is also not revealed; the verifier only learns a single
    // evaluation of a polynomial in x_1 which has h(x_3) and another random
    // polynomial evaluated at x_3 as coefficients -- this random polynomial
    // is "randomPoly" in the vanishing argument.

    // AstAdd an additional blinding factor as a slight defense against
    // off-by-one errors.
    return factors + 1;
  }

  int lookup(
    List<(Expression, TableColumn)> Function(VirtualCells) tableMap,
  ) {
    final cells = VirtualCells(this);

    // Call the callback with the virtual cells
    final mapped = tableMap(cells).map((tuple) {
      final input = tuple.$1;
      final table = tuple.$2;

      if (input.containsSimpleSelector()) {
        throw Halo2Exception.operationFailed("lookup",
            reason:
                "Expression containing simple selector supplied to lookup argument.");
      }

      final tableQuery = cells.queryFixed(table.inner);

      return (input, tableQuery);
    }).toList();

    final index = lookups.length;

    lookups.add(LookupArgument(
        inputExpressions: mapped.map((e) => e.$1).toList(),
        tableExpressions: mapped.map((e) => e.$2).toList()));

    return index;
  }

  int degree() {
    // The permutation argument will serve alongside the gates, so must be
    // accounted for.
    int degree = permutation.requiredDegree();

    // The lookup argument also serves alongside the gates and must be accounted
    // for.
    final lookupMaxDegree = lookups.isNotEmpty
        ? lookups.map((l) => l.requiredDegree()).reduce((a, b) => a > b ? a : b)
        : 1;

    degree = degree > lookupMaxDegree ? degree : lookupMaxDegree;

    // Account for each gate to ensure our quotient polynomial is the
    // correct degree and that our extended domain is the right size.
    final gateMaxDegree = gates.isNotEmpty
        ? gates
            .expand((gate) => gate.polys.map((poly) => poly.degree()))
            .reduce((a, b) => a > b ? a : b)
        : 0;

    degree = degree > gateMaxDegree ? degree : gateMaxDegree;

    return degree > (minimumDegree ?? 1) ? degree : (minimumDegree ?? 1);
  }

  int minimumRows() => blindingFactors() + 3;

  /// Compresses selectors together based on their assignments.
  /// Do not call this twice.
  List<List<PallasNativeFp>> compressSelectors(List<List<bool>> selectors) {
    // The number of provided selector assignments must match
    assert(selectors.length == numSelectors);

    // Compute maximal degree for each selector
    final List<int> degrees = List.filled(selectors.length, 0);

    for (final gate in gates) {
      for (final expr in gate.polys) {
        final selector = expr.extractSimpleSelector();
        if (selector != null) {
          final int index = selector.offset;
          degrees[index] = IntUtils.max(degrees[index], expr.degree());
        }
      }
    }
    // Limit by the maximum allowed degree
    final int maxDegree = degree();

    final List<Column<Fixed>> newColumns = [];

    final (polys, selectorAssignment) = SelectorDescription.process(
      List.generate(selectors.length, (i) {
        return SelectorDescription(
          selector: i,
          activations: selectors[i],
          maxDegree: degrees[i],
        );
      }),
      maxDegree,
      () {
        final column = fixedColumn();
        newColumns.add(column);
        return ExpressionFixedQuery(
          ExpressionQuery(
            index: queryFixedIndex(column),
            columnIndex: column.index,
            rotation: Rotation.cur(),
          ),
        );
      },
    );

    // Build selector maps
    List<Column<Fixed>?> selectorMap =
        List.filled(selectorAssignment.length, null);
    final List<Expression?> selectorReplacements =
        List.filled(selectorAssignment.length, null);

    for (final assignment in selectorAssignment) {
      selectorReplacements[assignment.selector] = assignment.expression;
      selectorMap[assignment.selector] =
          newColumns[assignment.combinationIndex];
    }

    final List<Expression> finalSelectorReplacements =
        selectorReplacements.map((e) => e!).toList(growable: false);

    // Local helper: replace selectors in an expression
    Expression replaceSelectors(Expression expr, bool mustBeNonSimple) {
      return expr.evaluate(
          constant: (c) => ExpressionConstant(c),
          selectorColumn: (s) {
            if (mustBeNonSimple) {
              assert(!s.isSimple);
            }
            return finalSelectorReplacements[s.offset];
          },
          fixedColumn: (q) => ExpressionFixedQuery(q),
          adviceColumn: (q) => ExpressionAdviceQuery(q),
          instanceColumn: (q) => ExpressionInstanceQuery(q),
          negated: (a) => -a,
          sum: (a, b) => a + b,
          product: (a, b) => a * b,
          scaled: (a, f) => a * f);
    }

    // Substitute selectors in all gates
    for (final gate in gates) {
      gate.polys = gate.polys.map((e) => replaceSelectors(e, false)).toList();
    }
    lookups = lookups
        .map((e) => LookupArgument(
            inputExpressions: e.inputExpressions
                .map((e) => replaceSelectors(e, true))
                .toList(),
            tableExpressions: e.tableExpressions
                .map((e) => replaceSelectors(e, true))
                .toList()))
        .toList();

    return polys;
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.int32(2),
        ProtoFieldConfig.int32(3),
        ProtoFieldConfig.int32(4),
        ProtoFieldConfig.repeated(
            fieldNumber: 5, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 6, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 7, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 8, elementType: ProtoFieldType.int32),
        ProtoFieldConfig.repeated(
            fieldNumber: 9, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 10, elementType: ProtoFieldType.message),
        ProtoFieldConfig.message(11),
        ProtoFieldConfig.repeated(
            fieldNumber: 12, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 13, elementType: ProtoFieldType.message),
        ProtoFieldConfig.int32(14),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;
  @override
  List<Object?> get bufferValues => [
        numFixedColumns,
        numAdviceColumns,
        numInstanceColumns,
        numSelectors,
        selectorMap,
        gates,
        adviceQueries,
        _numAdviceQueries,
        instanceQueries,
        fixedQueries,
        permutation,
        lookups,
        constants,
        minimumDegree
      ];

  @override
  List<dynamic> get variables => [
        numFixedColumns,
        numAdviceColumns,
        numInstanceColumns,
        numSelectors,
        selectorMap,
        gates,
        adviceQueries,
        _numAdviceQueries,
        instanceQueries,
        fixedQueries,
        permutation,
        lookups,
        constants,
        minimumDegree
      ];
}

class VirtualCells {
  final ConstraintSystem meta;
  final List<Selector> _queriedSelectors;
  final List<VirtualCell> _queriedCells;
  VirtualCells(this.meta)
      : _queriedCells = [],
        _queriedSelectors = [];
  ExpressionSelector querySelector(Selector selector) {
    _queriedSelectors.add(selector);
    return ExpressionSelector(selector);
  }

  ExpressionFixedQuery queryFixed(Column<Fixed> column) {
    _queriedCells
        .add(VirtualCell(column: column.toAny(), rotation: Rotation.cur()));
    return ExpressionFixedQuery(ExpressionQuery(
        index: meta.queryFixedIndex(column),
        columnIndex: column.index,
        rotation: Rotation.cur()));
  }

  ExpressionAdviceQuery queryAdvice(Column<Advice> column, Rotation at) {
    _queriedCells.add(VirtualCell(column: column.toAny(), rotation: at));
    return ExpressionAdviceQuery(ExpressionQuery(
        index: meta.queryAdviceIndex(column, at),
        columnIndex: column.index,
        rotation: at));
  }

  ExpressionInstanceQuery queryInstance(Column<Instance> column, Rotation at) {
    _queriedCells.add(VirtualCell(column: column.toAny(), rotation: at));
    return ExpressionInstanceQuery(ExpressionQuery(
        index: meta.queryInstanceIndex(column, at),
        columnIndex: column.index,
        rotation: at));
  }

  Expression queryAny(Column<Any> column, Rotation at) {
    return switch (column.columnType) {
      final AnyAdvice _ =>
        queryAdvice(Column(index: column.index, columnType: Advice()), at),
      final AnyFixed _ => () {
          if (!at.isCurrent) {
            throw Halo2Exception.operationFailed("queryAny",
                reason:
                    "Fixed columns can only be queried at the current rotation.");
          }
          return queryFixed(Column(index: column.index, columnType: Fixed()));
        }(),
      final AnyInstance _ =>
        queryInstance(Column(index: column.index, columnType: Instance()), at),
    };
  }
}

class Constraints {
  final Expression? selector;
  final List<Expression> constraints;
  const Constraints({this.selector, required this.constraints});

  List<Expression> getConstraints() {
    final selector = this.selector;
    if (selector == null) return constraints;
    return constraints.map((e) => selector * e).toList();
  }
}
