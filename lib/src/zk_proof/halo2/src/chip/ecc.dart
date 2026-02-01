import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/add.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/mul.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/mul_fixed.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/witness.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/constants/fixed_bases.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

typedef MagnitudeCell = AssignedCell<PallasNativeFp>;
typedef SignCell = AssignedCell<PallasNativeFp>;

class EccConfig {
  final List<Column<Advice>> advices;

  // Incomplete addition
  final AddIncompleteConfig addIncompleteConfig;

  // Complete addition
  final AddConfig addConfig;

  // GVariable-base scalar multiplication
  final MulConfig mulConfig;

  // Fixed-base full-width scalar multiplication
  final MulFixedFullConfig mulFixedFullConfig;

  // Fixed-base short scalar multiplication
  final MulFixedShortConfig mulFixedShortConfig;

  // Fixed-base mul using a base field element as a scalar
  final MulFixedBaseFieldConfig mulFixedBaseFieldConfig;

  // Witness point
  final WitnessPointConfig witnessPointConfig;

  // Lookup range check
  final LookupRangeCheckConfig lookupConfig;

  const EccConfig._({
    required this.advices,
    required this.addIncompleteConfig,
    required this.addConfig,
    required this.mulConfig,
    required this.mulFixedFullConfig,
    required this.mulFixedShortConfig,
    required this.mulFixedBaseFieldConfig,
    required this.witnessPointConfig,
    required this.lookupConfig,
  });

  factory EccConfig.configure(
    ConstraintSystem meta,
    List<Column<Advice>> advices,
    List<Column<Fixed>> lagrangeCoeffs,
    LookupRangeCheckConfig rangeCheck,
  ) {
    assert(advices.length == 10);
    assert(lagrangeCoeffs.length == 8);

    // Create witness point gate
    final witnessPoint =
        WitnessPointConfig.configure(meta, advices[0], advices[1]);

    // Create incomplete addition gate
    final addIncomplete = AddIncompleteConfig.configure(
        meta, advices[0], advices[1], advices[2], advices[3]);

    // Create complete addition gate
    final add = AddConfig.configure(meta, advices[0], advices[1], advices[2],
        advices[3], advices[4], advices[5], advices[6], advices[7], advices[8]);

    // Create variable-base scalar multiplication gates
    final mul = MulConfig.configure(meta, add, rangeCheck, advices);

    // Shared config for fixed-base scalar multiplication
    final mulFixed = MulFixedConfig.configure(
        meta, lagrangeCoeffs, advices[4], advices[5], add, addIncomplete);

    // Full-width fixed-base scalar mul
    final mulFixedFull = MulFixedFullConfig.configure(meta, mulFixed);

    // Short fixed-base scalar mul
    final mulFixedShort = MulFixedShortConfig.configure(meta, mulFixed);

    // Fixed-base multiplication using base field element
    final mulFixedBaseField = MulFixedBaseFieldConfig.configure(
        meta, advices.sublist(6, 9), rangeCheck, mulFixed);

    return EccConfig._(
      advices: advices,
      addIncompleteConfig: addIncomplete,
      addConfig: add,
      mulConfig: mul,
      mulFixedFullConfig: mulFixedFull,
      mulFixedShortConfig: mulFixedShort,
      mulFixedBaseFieldConfig: mulFixedBaseField,
      witnessPointConfig: witnessPoint,
      lookupConfig: rangeCheck,
    );
  }

  void constrainEqual(
      {required Layouter layouter, required EccPoint a, required EccPoint b}) {
    layouter.assignRegion(
      (region) {
        region.constrainEqual(a.getX().cell, b.x.cell);
        region.constrainEqual(a.getY().cell, b.y.cell);
      },
    );
  }

  EccPoint witnessPoint(
      {required Layouter layouter, required PallasAffineNativePoint? value}) {
    final config = witnessPointConfig;
    return layouter.assignRegion(
      (region) {
        return config.point(value: value, offset: 0, region: region);
      },
    );
  }

  EccPoint witnessPointFromConstant(
      {required Layouter layouter, required PallasAffineNativePoint value}) {
    final config = witnessPointConfig;
    return layouter.assignRegion(
      (region) {
        return config.constantPoint(value: value, offset: 0, region: region);
      },
    );
  }

  EccPoint witnessPointNonId(
      {required Layouter layouter, required PallasAffineNativePoint? value}) {
    final config = witnessPointConfig;
    return layouter.assignRegion(
      (region) {
        return config.pointNonId(value: value, offset: 0, region: region);
      },
    );
  }

  EccScalarFixed witnessScalarFixed(
      {required Layouter layouter, required VestaNativeFq? value}) {
    return EccScalarFixed(value: value);
  }

  EccScalarFixedShort scalarFixedFromSignedShort(
      {required Layouter layouter,
      required (MagnitudeCell, SignCell) magnitude}) {
    return EccScalarFixedShort(magnitude: magnitude.$1, sign: magnitude.$2);
  }

  AssignedCell<PallasNativeFp> extractP(EccPoint point) {
    return point.getX();
  }

  EccPoint addIncomplete(
      {required Layouter layouter, required EccPoint a, required EccPoint b}) {
    final config = addIncompleteConfig;
    return layouter.assignRegion(
      (region) {
        return config.assignRegion(a, b, 0, region);
      },
    );
  }

  EccPoint add(
      {required Layouter layouter, required EccPoint a, required EccPoint b}) {
    final config = addConfig;
    return layouter.assignRegion(
      (region) {
        return config.assignRegion(a, b, 0, region);
      },
    );
  }

  EccPoint mulSign(
      {required Layouter layouter,
      required AssignedCell<PallasNativeFp> sign,
      required EccPoint point}) {
    final config = mulFixedShortConfig;
    return config.assignScalarSign(layouter, sign, point);
  }

  (EccPoint, ScalarVar) mul(
      {required Layouter layouter,
      required ScalarVar scalar,
      required EccPoint base}) {
    final config = mulConfig;
    return switch (scalar) {
      final ScalarVarBaseFieldElem r => config.assign(layouter, r.cell, base),
      _ => throw Halo2Exception.operationFailed("mul",
          reason: "Unsupported object.")
    };
  }

  (EccPoint, EccScalarFixed) mulFixed(
      {required Layouter layouter,
      required EccScalarFixed scalar,
      required OrchardFixedBasesFull base}) {
    final config = mulFixedFullConfig;
    return config.assign(layouter, scalar, base);
  }

  (EccPoint, EccScalarFixedShort) mulFixedShort(
      {required Layouter layouter,
      required EccScalarFixedShort scalar,
      required OrchardFixedBasesValueCommitV base}) {
    final config = mulFixedShortConfig;
    return config.assign(layouter, scalar, base);
  }

  EccPoint mulFixedBaseFieldElem(
      {required Layouter layouter,
      required AssignedCell<PallasNativeFp> baseFieldElem,
      required OrchardFixedBasesNullifierK base}) {
    final config = mulFixedBaseFieldConfig;
    return config.assign(layouter, baseFieldElem, base);
  }

  ScalarVarBaseFieldElem scalarVarFromBase(AssignedCell<PallasNativeFp> cell) {
    return ScalarVarBaseFieldElem(cell);
  }
}

sealed class ScalarVar {
  const ScalarVar();
}

class ScalarVarBaseFieldElem extends ScalarVar {
  final AssignedCell<PallasNativeFp> cell;
  const ScalarVarBaseFieldElem(this.cell);
}

class ScalarVarFullWidth extends ScalarVar {}

class EccScalarFixed extends ScalarVar {
  final VestaNativeFq? value;
  final List<AssignedCell<PallasNativeFp>>? windows;
  EccScalarFixed(
      {required this.value, List<AssignedCell<PallasNativeFp>>? windows})
      : windows = windows?.exc(
            length: 85,
            operation: "EccScalarFixed",
            reason: "Invalid windows fields length.");
}

class EccPoint {
  final AssignedCell<Assigned> x;
  final AssignedCell<Assigned> y;
  const EccPoint(this.x, this.y);
  AssignedCell<PallasNativeFp> getX() =>
      AssignedCell(value: x.value?.evaluate(), cell: x.cell);
  AssignedCell<PallasNativeFp> getY() =>
      AssignedCell(value: y.value?.evaluate(), cell: y.cell);

  PallasAffineNativePoint? toPoint() {
    if (x.hasValue && y.hasValue) {
      if (x.getValue().isZero || y.getValue().isZero) {
        throw Halo2Exception.operationFailed("toPoint",
            reason: "Invalid ECC identity point.");
      }
      return PallasAffineNativePoint(
          x: x.getValue().evaluate(), y: y.getValue().evaluate());
    }
    return null;
  }

  EccPointWithConfig withConfig(EccConfig chip) =>
      EccPointWithConfig(chip, this);
}

class EccScalarFixedShort {
  final MagnitudeCell magnitude;
  final SignCell sign;
  final List<AssignedCell<PallasNativeFp>>? runningSum;
  EccScalarFixedShort(
      {required this.magnitude,
      required this.sign,
      List<AssignedCell<PallasNativeFp>>? runningSum})
      : runningSum = runningSum?.exc(
            length: 23,
            operation: "EccScalarFixedShort",
            reason: "Invalid runningSum length.");
}

class EccBaseFieldElemFixed {
  final AssignedCell<PallasNativeFp> baseFieldElem;
  final List<AssignedCell<PallasNativeFp>> runningSum;
  EccBaseFieldElemFixed(
      {required this.baseFieldElem,
      required List<AssignedCell<PallasNativeFp>> runningSum})
      : runningSum = runningSum.exc(
            length: 86,
            operation: "EccScalarFixedShort",
            reason: "Invalid runningSum length.");
}

class EccPointWithConfig {
  final EccConfig chip;
  final EccPoint inner;
  const EccPointWithConfig(this.chip, this.inner);

  AssignedCell<PallasNativeFp> extractP() {
    return inner.getX();
  }

  EccPointWithConfig add(Layouter layouter, EccPointWithConfig other) {
    final add = chip.add(layouter: layouter, a: inner, b: other.inner);
    return EccPointWithConfig(chip, add);
  }

  (EccPointWithConfig, ScalarVar) mul(Layouter layouter, ScalarVar by) {
    final (pointInner, scalarInner) =
        chip.mul(layouter: layouter, scalar: by, base: inner);
    return (EccPointWithConfig(chip, pointInner), scalarInner);
  }

  /// Constrains this point to be equal in value to another point.
  void constrainEqual(Layouter layouter, EccPointWithConfig other) {
    chip.constrainEqual(layouter: layouter, a: inner, b: other.inner);
  }
}
