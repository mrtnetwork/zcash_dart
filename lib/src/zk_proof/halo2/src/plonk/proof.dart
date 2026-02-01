import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/key.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/evaluator.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

class PolyInstanceSingle {
  final List<Polynomial<PallasNativeFp, LagrangeCoeff>> instanceValues;
  final List<Polynomial<PallasNativeFp, Coeff>> instancePolys;
  final List<Polynomial<PallasNativeFp, ExtendedLagrangeCoeff>> instanceCosets;

  const PolyInstanceSingle(
      {required this.instanceValues,
      required this.instancePolys,
      required this.instanceCosets});
}

class PolyAdviceSingle {
  final List<Polynomial<PallasNativeFp, LagrangeCoeff>> adviceValues;
  final List<Polynomial<PallasNativeFp, Coeff>> advicePolys;
  final List<Polynomial<PallasNativeFp, ExtendedLagrangeCoeff>> adviceCosets;
  final List<PallasNativeFp> adviceBlinds;
  const PolyAdviceSingle(
      {required this.adviceValues,
      required this.advicePolys,
      required this.adviceCosets,
      required this.adviceBlinds});
}

class PlonkWitnessCollection extends Assignment {
  final int k;
  final List<Polynomial<Assigned, LagrangeCoeff>> advice;
  final List<List<PallasNativeFp>> instances;
  final ComparableIntRange usableRows;

  PlonkWitnessCollection({
    required this.k,
    required this.advice,
    required this.instances,
    required this.usableRows,
  });

  @override
  void enableSelector(Selector selector, int row) {}

  @override
  PallasNativeFp? queryInstance(Column<Instance> column, int row) {
    if (!usableRows.contains(row)) {
      throw Halo2Exception.operationFailed("queryInstance",
          reason: "Not enough rows available.");
    }

    try {
      final colData = instances[column.index];
      return colData[row];
    } catch (_) {
      throw Halo2Exception.operationFailed("queryInstance",
          reason: "Bounds failure.");
    }
  }

  @override
  void assignAdvice(Column<Advice> column, int row, Assigned? Function() to) {
    if (!usableRows.contains(row)) {
      throw Halo2Exception.operationFailed("assignAdvice",
          reason: "Not enough rows available.");
    }
    final t = to();
    if (t != null) {
      advice[column.index].values[row] = t;
      return;
    }
    throw Halo2Exception.operationFailed("assignAdvice",
        reason: "Bounds failure.");
  }

  @override
  void assignFixed(Column<Fixed> column, int row, Assigned? Function() to) {}

  @override
  void copy(
      Column<Any> srcColumn, int srcRow, Column<Any> dstColumn, int dstRow) {
    // Only advice columns are relevant; do nothing
  }

  @override
  void fillFromRow(Column<Fixed> column, int fromRow, Assigned? to) {}
}

class AstLeaves {
  final List<PolyAdviceSingle> advice;
  final List<PolyInstanceSingle> instance;
  final Evaluator<LagrangeCoeff> valueEvaluator;
  final Evaluator<ExtendedLagrangeCoeff> cosetEvaluator;
  final List<AstLeaf> fixedValues;
  final List<List<AstLeaf>> adviceValues;
  final List<List<AstLeaf>> instanceValues;
  final List<AstLeaf> fixedCosets;
  final List<List<AstLeaf>> adviceCosets;
  final List<List<AstLeaf>> instanceCosets;
  final List<AstLeaf> permutationCosets;
  final AstLeaf l0;
  final AstLeaf lBlind;
  final AstLeaf lLast;
  const AstLeaves(
      {required this.valueEvaluator,
      required this.cosetEvaluator,
      required this.fixedValues,
      required this.adviceValues,
      required this.instanceValues,
      required this.fixedCosets,
      required this.adviceCosets,
      required this.instanceCosets,
      required this.permutationCosets,
      required this.l0,
      required this.lBlind,
      required this.lLast,
      required this.advice,
      required this.instance});
  factory AstLeaves.build(
      {required PlonkProvingKey pk,
      required List<PolyAdviceSingle> advice,
      required List<PolyInstanceSingle> instance}) {
    final valueEvaluator = Evaluator<LagrangeCoeff>();

    final List<AstLeaf> fixedValues = pk.fixedValues
        .map((poly) => valueEvaluator.registerPoly(poly.clone()))
        .toList();

    final List<List<AstLeaf>> adviceValues = advice
        .map((adviceColumn) => adviceColumn.adviceValues
            .map((poly) => valueEvaluator.registerPoly(poly.clone()))
            .toList())
        .toList();

    final List<List<AstLeaf>> instanceValues = instance
        .map((instanceColumn) => instanceColumn.instanceValues
            .map((poly) => valueEvaluator.registerPoly(poly.clone()))
            .toList())
        .toList();
    final cosetEvaluator = Evaluator<ExtendedLagrangeCoeff>();

    final List<AstLeaf> fixedCosets = pk.fixedCosets
        .map((poly) => cosetEvaluator.registerPoly(poly.clone()))
        .toList();

    final List<List<AstLeaf>> adviceCosets = advice
        .map((adviceColumn) => adviceColumn.adviceCosets
            .map((poly) => cosetEvaluator.registerPoly(poly.clone()))
            .toList())
        .toList();

    final List<List<AstLeaf>> instanceCosets = instance
        .map((instanceColumn) => instanceColumn.instanceCosets
            .map((poly) => cosetEvaluator.registerPoly(poly.clone()))
            .toList())
        .toList();

    final List<AstLeaf> permutationCosets = pk.permutation.cosets
        .map((poly) => cosetEvaluator.registerPoly(poly.clone()))
        .toList();

    final AstLeaf l0 = cosetEvaluator.registerPoly(pk.l0.clone());
    final AstLeaf lBlind = cosetEvaluator.registerPoly(pk.lBlind.clone());
    final AstLeaf lLast = cosetEvaluator.registerPoly(pk.lLast.clone());
    return AstLeaves(
        valueEvaluator: valueEvaluator,
        cosetEvaluator: cosetEvaluator,
        fixedValues: fixedValues,
        adviceValues: adviceValues,
        instanceValues: instanceValues,
        fixedCosets: fixedCosets,
        adviceCosets: adviceCosets,
        instanceCosets: instanceCosets,
        permutationCosets: permutationCosets,
        l0: l0,
        lBlind: lBlind,
        lLast: lLast,
        advice: advice,
        instance: instance);
  }
}
