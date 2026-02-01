import 'package:blockchain_utils/crypto/crypto/ec/cdsa.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';

class WitnessPointConfig {
  final Selector qPoint;
  final Selector qPointNonId;
  final Column<Advice> x;
  final Column<Advice> y;
  const WitnessPointConfig._(
      {required this.qPoint,
      required this.qPointNonId,
      required this.x,
      required this.y});

  factory WitnessPointConfig.configure(
      ConstraintSystem meta, Column<Advice> x, Column<Advice> y) {
    final config = WitnessPointConfig._(
        qPoint: meta.selector(), qPointNonId: meta.selector(), x: x, y: y);
    config._createGate(meta);
    return config;
  }

  void _createGate(ConstraintSystem meta) {
    Expression curveEqn(VirtualCells meta) {
      final xExpr = meta.queryAdvice(x, Rotation.cur());
      final yExpr = meta.queryAdvice(y, Rotation.cur());
      // y^2 = x^3 + b
      return yExpr.square() -
          xExpr.square() * xExpr -
          ExpressionConstant(PastaCurveParams.pallasNative.b);
    }

    // Witness point gate
    meta.createGate((meta) {
      final qPointExpr = meta.querySelector(qPoint);
      final xExpr = meta.queryAdvice(x, Rotation.cur());
      final yExpr = meta.queryAdvice(y, Rotation.cur());

      return Constraints(constraints: [
        qPointExpr * xExpr * curveEqn(meta),
        qPointExpr * yExpr * curveEqn(meta)
      ]);
    });

    // Witness non-identity point gate
    meta.createGate((meta) {
      final qPointNonIdExpr = meta.querySelector(qPointNonId);
      return Constraints(
          selector: qPointNonIdExpr, constraints: [curveEqn(meta)]);
    });
  }

  EccPoint point({
    required PallasAffineNativePoint? value,
    required int offset,
    required Region region,
  }) {
    qPoint.enable(region: region, offset: offset);

    Coordinates<AssignedCell<Assigned>> x;
    if (value == null) {
      x = assignXY(null, offset, region);
    } else {
      if (value.isIdentity()) {
        x = assignXY((AssignedZero(), AssignedZero()), offset, region);
      } else {
        x = assignXY((AssignedTrivial(value.x), AssignedTrivial(value.y)),
            offset, region);
      }
    }
    return EccPoint(x.x, x.y);
  }

  EccPoint pointNonId(
      {required PallasAffineNativePoint? value,
      required int offset,
      required Region region}) {
    qPointNonId.enable(region: region, offset: offset);

    if (value != null && value.isIdentity()) {
      throw Halo2Exception.operationFailed("pointNonId",
          reason: "Zero point not allowed.");
    }
    final x = assignXY(() {
      if (value != null) {
        // final p = value.assign();
        return (AssignedTrivial(value.x), AssignedTrivial(value.y));
      }
      return null;
    }(), offset, region);
    return EccPoint(x.x, x.y);
  }

  EccPoint constantPoint({
    required PallasAffineNativePoint value,
    required int offset,
    required Region region,
  }) {
    qPoint.enable(region: region, offset: offset);
    Coordinates<AssignedCell<Assigned>> x;
    if (value.isIdentity()) {
      x = assignXY((AssignedZero(), AssignedZero()), offset, region);
    } else {
      x = assignXY(
          (AssignedTrivial(value.x), AssignedTrivial(value.y)), offset, region);
    }
    return EccPoint(x.x, x.y);
  }

  Coordinates<AssignedCell<Assigned>> assignXY(
    (Assigned, Assigned)? value,
    int offset,
    Region region,
  ) {
    // Assign `x` value
    final xVar = region.assignAdvice(x, offset, () => value?.$1);
    final yVar = region.assignAdvice(y, offset, () => value?.$2);
    return Coordinates(xVar, yVar);
  }
}
