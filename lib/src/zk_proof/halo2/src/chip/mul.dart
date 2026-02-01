import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/add.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';

class MulConfig {
  final Selector qMulLsb;
  final AddConfig addConfig;
  final MulIncompleteConfig hiConfig;
  final MulIncompleteConfig loConfig;
  final MulCompleteConfig completeConfig;
  final MulOverflowConfig overflowConfig;
  final ComparableIntRange hi;
  final ComparableIntRange lo;
  final ComparableIntRange complete;

  MulConfig._(
      {required this.qMulLsb,
      required this.addConfig,
      required this.hiConfig,
      required this.loConfig,
      required this.completeConfig,
      required this.overflowConfig,
      ComparableIntRange? hi,
      ComparableIntRange? lo,
      ComparableIntRange? complete})
      : hi = hi ?? ComparableIntRange(0, 125),
        lo = lo ?? ComparableIntRange(125, 251),
        complete = complete ?? ComparableIntRange(251, 254);

  factory MulConfig.configure(
    ConstraintSystem meta,
    AddConfig addConfig,
    LookupRangeCheckConfig lookupConfig,
    List<Column<Advice>> advices,
  ) {
    assert(advices.length == 10);

    final hiConfig = MulIncompleteConfig.configure(
        meta: meta,
        z: advices[9],
        xA: advices[3],
        xP: advices[0],
        yP: advices[1],
        lambda1: advices[4],
        lambda2: advices[5],
        bitlen: 125);

    final loConfig = MulIncompleteConfig.configure(
        meta: meta,
        z: advices[6],
        xA: advices[7],
        xP: advices[0],
        yP: advices[1],
        lambda1: advices[8],
        lambda2: advices[2],
        bitlen: 126);
    final completeConfig =
        MulCompleteConfig.configure(meta, advices[9], addConfig);
    final overflowConfig =
        MulOverflowConfig.configure(meta, lookupConfig, advices.sublist(6, 9));

    final config = MulConfig._(
        qMulLsb: meta.selector(),
        addConfig: addConfig,
        hiConfig: hiConfig,
        loConfig: loConfig,
        completeConfig: completeConfig,
        overflowConfig: overflowConfig);
    if (config.hiConfig.doubleAndAdd.xP != config.loConfig.doubleAndAdd.xP ||
        config.hiConfig.yP != config.loConfig.yP) {
      throw Halo2Exception.operationFailed("configure",
          reason: "Invalid configration.");
    }
    final addConfigOutputs = addConfig.outputColumns();
    if ([
      config.hiConfig.z,
      config.hiConfig.doubleAndAdd.lambda1,
      config.loConfig.z,
      config.loConfig.doubleAndAdd.lambda1
    ].any((e) => addConfigOutputs.contains(e))) {
      throw Halo2Exception.operationFailed("configure",
          reason: "Invalid incomplete configration.");
    }
    config._createGate(meta);
    return config;
  }

  void _createGate(ConstraintSystem meta) {
    meta.createGate((meta) {
      final qMulLsb = meta.querySelector(this.qMulLsb);

      final z1 = meta.queryAdvice(completeConfig.zComplete, Rotation.cur());
      final z0 = meta.queryAdvice(completeConfig.zComplete, Rotation.next());
      final xP = meta.queryAdvice(addConfig.xP, Rotation.cur());
      final yP = meta.queryAdvice(addConfig.yP, Rotation.cur());
      final baseX = meta.queryAdvice(addConfig.xP, Rotation.next());
      final baseY = meta.queryAdvice(addConfig.yP, Rotation.next());

      // k0 = z0 - 2 * z1
      final lsb = z0 - z1 * PallasNativeFp.two();

      final boolCheck = Halo2Utils.boolCheck(lsb);

      // ternary for x and y depending on LSB
      final lsbX = Halo2Utils.ternary(lsb, xP, xP - baseX);
      final lsbY = Halo2Utils.ternary(lsb, yP, yP + baseY);

      return Constraints(
          selector: qMulLsb, constraints: [boolCheck, lsbX, lsbY]);
    });
  }

  List<bool?> decomposeForScalarMul(PallasNativeFp? scalar) {
    if (scalar == null) {
      return List.filled(PallasFPConst.numBits, null);
    }
    final v = scalar.v + Halo2Utils.tQ;
    final kBytes = v.toU256LeBytes();
    final bits = <bool>[];
    for (final byte in kBytes) {
      for (int i = 0; i < 8; i++) {
        bits.add(((byte >> i) & 1) == 1);
      }
    }
    return bits.take(PallasFPConst.numBits).toList().reversed.toList();
  }

  (EccPoint, AssignedCell<PallasNativeFp>) processLsb(Region region, int offset,
      EccPoint base, EccPoint acc, AssignedCell<PallasNativeFp> z1, bool? lsb) {
    // Enable LSB gate
    qMulLsb.enable(region: region, offset: offset);
    // Compute z_0 = 2 * z_1 + k_0
    PallasNativeFp? z0Val;
    if (z1.hasValue && lsb != null) {
      z0Val = z1.getValue() * PallasNativeFp.from(2) +
          PallasNativeFp.from(lsb ? 1 : 0);
    }
    final z0Cell =
        region.assignAdvice(completeConfig.zComplete, offset + 1, () => z0Val);

    // Copy base coordinates for LSB gate
    base.x.copyAdvice(region, addConfig.xP, offset + 1);
    base.y.copyAdvice(region, addConfig.yP, offset + 1);

    // Determine x and y for LSB handling
    Assigned? xVal;
    Assigned? yVal;

    if (lsb != null) {
      if (!lsb) {
        xVal = base.x.value;
        yVal = base.y.hasValue ? -base.y.getValue() : yVal;
      } else {
        xVal = AssignedZero();
        yVal = AssignedZero();
      }
    }
    final xCell = region.assignAdvice(addConfig.xP, offset, () => xVal);
    final yCell = region.assignAdvice(addConfig.yP, offset, () => yVal);
    final p = EccPoint(xCell, yCell);
    // Final complete addition: result = Acc + P (or Acc + (-P))
    final result = addConfig.assignRegion(p, acc, offset, region);
    return (result, z0Cell);
  }

  (EccPoint, ScalarVar) assign(
      Layouter layouter, AssignedCell<PallasNativeFp> alpha, EccPoint base) {
    final (result, zs) = layouter.assignRegion(
      (region) {
        int offset = 0;
        // Convert base into EccPoint
        final basePoint = EccPoint(base.x, base.y);

        // Decompose scalar alpha into bits (big-endian)
        final bits = decomposeForScalarMul(alpha.value);

        final bitsIncompleteHi = bits.sublist(hi.start, hi.end);
        final bitsIncompleteLo = bits.sublist(lo.start, lo.end);
        final lsb = bits[PallasFPConst.numBits - 1];
        // Initialize accumulator acc = [2]base using complete addition
        var acc = addConfig.assignRegion(basePoint, basePoint, offset, region);

        offset += 1;

        // Initialize running sum z = 0
        final zInit = region.assignAdviceFromConstant(
            hiConfig.z, offset, PallasNativeFp.zero());

        // Double-and-add (incomplete) for high half
        var (xA, yA, zsIncompleteHi) = hiConfig.doubleAdd(
            region, offset, base, bitsIncompleteHi, (acc.x, acc.y, zInit));

        // Double-and-add (incomplete) for low half
        final z = zsIncompleteHi.last;
        var (incompleteLoResult) = loConfig.doubleAdd(
          region,
          offset,
          base,
          bitsIncompleteLo,
          (xA, yA, z),
        );
        xA = incompleteLoResult.$1;
        yA = incompleteLoResult.$2;
        var zsIncompleteLo = incompleteLoResult.$3;

        // Adjust offset for complete addition
        offset += lo.length + 2;

        // Complete addition
        final zLast = zsIncompleteLo.last;
        final bitsComplete = bits.sublist(complete.start, complete.end);
        final (accComplete, zsComplete) = completeConfig.assignRegion(
            region, offset, bitsComplete, basePoint, xA, yA, zLast);
        offset += complete.length * 2;
        final z1 = zsComplete.last;
        final (result, z0) =
            processLsb(region, offset, base, accComplete, z1, lsb);

        // Collect zs
        final List<AssignedCell<PallasNativeFp>> zs = [];
        zs.add(zInit);
        zs.addAll(zsIncompleteHi);
        zs.addAll(zsIncompleteLo);
        zs.addAll(zsComplete);
        zs.add(z0);
        assert(zs.length == PallasFPConst.numBits + 1);

        return (result, zs.reversed.toList());
      },
    );
    overflowConfig.overflowCheck(layouter, alpha, zs);
    return (result, ScalarVarBaseFieldElem(alpha));
  }
}

class MulCompleteConfig {
  // Selector used to constrain the cells used in complete addition.
  final Selector qMulDecomposeVar;

  // Advice column used to decompose scalar in complete addition.
  final Column<Advice> zComplete;

  // Configuration used in complete addition
  final AddConfig addConfig;

  const MulCompleteConfig(
      {required this.qMulDecomposeVar,
      required this.zComplete,
      required this.addConfig});

  factory MulCompleteConfig.configure(
    ConstraintSystem meta,
    Column<Advice> zComplete,
    AddConfig addConfig,
  ) {
    meta.enableEquality(zComplete);
    final config = MulCompleteConfig(
        qMulDecomposeVar: meta.selector(),
        zComplete: zComplete,
        addConfig: addConfig);
    config.createGate(meta);
    return config;
  }

  /// Gate used to check scalar decomposition is correct.
  /// This is used to check the bits used in complete addition, since the incomplete
  /// addition gate already checks scalar decomposition for the other bits.
  void createGate(ConstraintSystem meta) {
    // | y_p | z_complete |
    // --------------------
    // | y_p | z_{i + 1}  |
    // |     | base_y     |
    // |     | z_i        |
    // https://p.z.cash/halo2-0.1:ecc-var-mul-complete-gate
    meta.createGate(
      (meta) {
        final qMulDecomposeVar = meta.querySelector(this.qMulDecomposeVar);

        // z_{i + 1}
        final zPrev = meta.queryAdvice(zComplete, Rotation.prev());

        // z_i
        final zNext = meta.queryAdvice(zComplete, Rotation.next());

        // k_i = z_i - 2 * z_{i+1}
        final k = zNext - ExpressionConstant(PallasNativeFp.two()) * zPrev;

        // (k_i) * (1 - k_i) = 0
        final boolCheck = Halo2Utils.boolCheck(k);

        // base_y
        final baseY = meta.queryAdvice(zComplete, Rotation.cur());

        // y_p
        final yP = meta.queryAdvice(addConfig.yP, Rotation.prev());

        // k_i = 0 => y_p = -base_y
        // k_i = 1 => y_p =  base_y
        final ySwitch = Halo2Utils.ternary(k, baseY - yP, baseY + yP);

        return Constraints(
          selector: qMulDecomposeVar,
          constraints: [boolCheck, ySwitch],
        );
      },
    );
  }

  (EccPoint, List<AssignedCell<PallasNativeFp>>) assignRegion(
    Region region,
    int offset,
    List<bool?> bits,
    EccPoint base,
    AssignedCell<Assigned> xA,
    AssignedCell<Assigned> yA,
    AssignedCell<PallasNativeFp> z,
  ) {
    assert(bits.length == 3);

    // Enable selectors for complete range
    for (int i = 0; i < bits.length; i++) {
      final row = 2 * i;
      qMulDecomposeVar.enable(region: region, offset: row + offset + 1);
    }

    // Initialize accumulator from incomplete addition
    var acc = EccPoint(xA, yA);

    // Copy running sum z
    z = z.copyAdvice(region, zComplete, offset);

    final List<AssignedCell<PallasNativeFp>> zs = [];

    // Complete addition
    for (int iter = 0; iter < bits.length; iter++) {
      final row = 2 * iter;
      final k = bits[iter];

      // Update z
      PallasNativeFp? zVal;
      if (z.hasValue && k != null) {
        zVal = z.getValue() * PallasNativeFp.from(2) +
            PallasNativeFp.from(k ? 1 : 0);
      }

      z = region.assignAdvice(zComplete, row + offset + 2, () => zVal);
      zs.add(z);

      // Assign y_p for complete addition
      final baseYCell = base.y.copyAdvice(region, zComplete, row + offset + 1);
      Assigned? yPVal;
      if (baseYCell.hasValue && k != null) {
        yPVal = k ? baseYCell.value : -baseYCell.getValue();
      }

      final yPCell =
          region.assignAdvice(addConfig.yP, row + offset, () => yPVal);

      // Compute U = P or -P depending on bit
      final U = EccPoint(base.x, yPCell);

      // Acc + U
      final tmpAcc = addConfig.assignRegion(U, acc, row + offset, region);

      // Acc + U + Acc
      acc = addConfig.assignRegion(acc, tmpAcc, row + offset + 1, region);
    }

    return (acc, zs);
  }
}

class DoubleAndAdd {
  final Column<Advice> xA;
  final Column<Advice> xP;
  final Column<Advice> lambda1;
  final Column<Advice> lambda2;

  const DoubleAndAdd({
    required this.xA,
    required this.xP,
    required this.lambda1,
    required this.lambda2,
  });

  /// Computes xR = lambda1^2 - xA - xP
  Expression xR(VirtualCells meta, Rotation rotation) {
    final xACur = meta.queryAdvice(xA, rotation);
    final xPCur = meta.queryAdvice(xP, rotation);
    final lambda1Cur = meta.queryAdvice(lambda1, rotation);
    return lambda1Cur.square() - xACur - xPCur;
  }

  /// Computes Y_A = (lambda1 + lambda2) * (xA - xR)
  /// Note: the caller should handle the 1/2 factor if needed.
  Expression yA(VirtualCells meta, Rotation rotation) {
    final xACur = meta.queryAdvice(xA, rotation);
    final lambda1Cur = meta.queryAdvice(lambda1, rotation);
    final lambda2Cur = meta.queryAdvice(lambda2, rotation);
    return (lambda1Cur + lambda2Cur) * (xACur - xR(meta, rotation));
  }
}

class MulIncompleteConfig {
  final Selector qMul1;
  final Selector qMul2;
  final Selector qMul3;
  final Column<Advice> z;
  final DoubleAndAdd doubleAndAdd;
  final Column<Advice> yP;
  final int bitlen;

  MulIncompleteConfig({
    required this.qMul1,
    required this.qMul2,
    required this.qMul3,
    required this.z,
    required this.doubleAndAdd,
    required this.yP,
    required this.bitlen,
  });

  factory MulIncompleteConfig.configure({
    required ConstraintSystem meta,
    required Column<Advice> z,
    required Column<Advice> xA,
    required Column<Advice> xP,
    required Column<Advice> yP,
    required Column<Advice> lambda1,
    required Column<Advice> lambda2,
    required int bitlen,
  }) {
    meta.enableEquality(z);
    meta.enableEquality(lambda1);

    final config = MulIncompleteConfig(
        qMul1: meta.selector(),
        qMul2: meta.selector(),
        qMul3: meta.selector(),
        bitlen: bitlen,
        z: z,
        doubleAndAdd:
            DoubleAndAdd(xA: xA, xP: xP, lambda1: lambda1, lambda2: lambda2),
        yP: yP);

    config._createGate(meta);
    return config;
  }

  void _createGate(ConstraintSystem meta) {
    Expression xR(VirtualCells metaCells, Rotation rotation) =>
        doubleAndAdd.xR(metaCells, rotation);

    Expression yA(VirtualCells metaCells, Rotation rotation) =>
        doubleAndAdd.yA(metaCells, rotation) * PallasNativeFp.twoInv();

    List<Expression> forLoop(VirtualCells metaCells, Expression yANext) {
      final one = ExpressionConstant(PallasNativeFp.one());

      final zCur = metaCells.queryAdvice(z, Rotation.cur());
      final zPrev = metaCells.queryAdvice(z, Rotation.prev());

      final xACur = metaCells.queryAdvice(doubleAndAdd.xA, Rotation.cur());
      final xANext = metaCells.queryAdvice(doubleAndAdd.xA, Rotation.next());

      final xPCur = metaCells.queryAdvice(doubleAndAdd.xP, Rotation.cur());
      final yPCur = metaCells.queryAdvice(yP, Rotation.cur());

      final lambda1Cur =
          metaCells.queryAdvice(doubleAndAdd.lambda1, Rotation.cur());
      final lambda2Cur =
          metaCells.queryAdvice(doubleAndAdd.lambda2, Rotation.cur());

      final yACur = yA(metaCells, Rotation.cur());

      final k = zCur - zPrev * PallasNativeFp.two();
      final boolCheck = Halo2Utils.boolCheck(k);

      final gradient1 = lambda1Cur * (xACur - xPCur) -
          yACur +
          (k * PallasNativeFp.two() - one) * yPCur;

      final secantLine = lambda2Cur * lambda2Cur -
          xANext -
          xR(metaCells, Rotation.cur()) -
          xACur;

      final gradient2 = lambda2Cur * (xACur - xANext) - yACur - yANext;

      return [boolCheck, gradient1, secantLine, gradient2];
    }

    // qMul1 gate
    meta.createGate((metaCells) {
      final qMul1 = metaCells.querySelector(this.qMul1);
      final yANext = yA(metaCells, Rotation.next());
      final yWitnessed =
          metaCells.queryAdvice(doubleAndAdd.lambda1, Rotation.cur());
      return Constraints(selector: qMul1, constraints: [yWitnessed - yANext]);
    });

    // qMul2 gate
    meta.createGate((metaCells) {
      final qMul2 = metaCells.querySelector(this.qMul2);
      final yANext = yA(metaCells, Rotation.next());
      final xPCur = metaCells.queryAdvice(doubleAndAdd.xP, Rotation.cur());
      final xPNext = metaCells.queryAdvice(doubleAndAdd.xP, Rotation.next());
      final yPCur = metaCells.queryAdvice(yP, Rotation.cur());
      final yPNext = metaCells.queryAdvice(yP, Rotation.next());

      final xPCheck = xPCur - xPNext;
      final yPCheck = yPCur - yPNext;

      return Constraints(
        selector: qMul2,
        constraints: [xPCheck, yPCheck, ...forLoop(metaCells, yANext)],
      );
    });

    // qMul3 gate
    meta.createGate((metaCells) {
      final qMul3 = metaCells.querySelector(this.qMul3);
      final yAFinal =
          metaCells.queryAdvice(doubleAndAdd.lambda1, Rotation.next());
      return Constraints(
        selector: qMul3,
        constraints: forLoop(metaCells, yAFinal),
      );
    });
  }

  (
    AssignedCell<Assigned>,
    AssignedCell<Assigned>,
    List<AssignedCell<PallasNativeFp>>
  ) doubleAdd(
    Region region,
    int offset,
    EccPoint base,
    List<bool?> bits,
    (
      AssignedCell<Assigned>,
      AssignedCell<Assigned>,
      AssignedCell<PallasNativeFp>
    ) acc,
  ) {
    assert(bits.length == bitlen);

    // Handle exceptional cases
    final xP = base.x.value;
    final yP = base.y.value;
    final xA = acc.$1.value;
    final yA = acc.$2.value;
    if (xA != null && yA != null && xP != null && yP != null) {
      if ((xP.isZero && yP.isZero) || (xA.isZero && yA.isZero) || (xP == xA)) {
        throw Halo2Exception.operationFailed("doubleAdd",
            reason: "Zero point not allowed.");
      }
    }
    // Set q_mul selectors
    qMul1.enable(region: region, offset: offset);
    final cOffset = offset + 1;

    for (int idx = 0; idx < bitlen - 1; idx++) {
      qMul2.enable(region: region, offset: cOffset + idx);
    }
    qMul3.enable(region: region, offset: cOffset + bitlen - 1);
    // Initialize double-and-add
    var z = acc.$3.copyAdvice(region, this.z, offset);
    var xANew = acc.$1.copyAdvice(region, doubleAndAdd.xA, offset + 1);
    var yANew = acc.$2.copyAdvice(region, doubleAndAdd.lambda1, offset).value;

    offset += 1; // row 0 used for initializing z

    final List<AssignedCell<PallasNativeFp>> zs = [];

    for (int row = 0; row < bits.length; row++) {
      final k = bits[row];

      // z_i = 2 * z_{i+1} + k_i
      PallasNativeFp? zVal;
      if (z.hasValue && k != null) {
        zVal = PallasNativeFp.from(2) * z.getValue() +
            PallasNativeFp.from(k ? 1 : 0);
      }
      z = region.assignAdvice(this.z, row + offset, () => zVal);
      zs.add(z);

      // Assign x_p, y_p
      region.assignAdvice(doubleAndAdd.xP, row + offset, () => xP);
      region.assignAdvice(this.yP, row + offset, () => yP);
      Assigned? yPAdjusted;
      // Conditionally negate y_p
      if (yP != null && k != null) {
        yPAdjusted = k ? yP : -yP;
      }
      // Compute lambda1 = (y_a - y_p) / (x_a - x_p)
      Assigned? lambda1;

      if (yANew != null &&
          yPAdjusted != null &&
          xANew.value != null &&
          xP != null) {
        lambda1 = (yANew - yPAdjusted) * (xANew.getValue() - xP).invert();
      }
      region.assignAdvice(doubleAndAdd.lambda1, row + offset, () => lambda1);

      // x_r = lambda1^2 - x_a - x_p
      Assigned? xR;
      if (lambda1 != null && xANew.hasValue && xP != null) {
        xR = lambda1.square() - xANew.getValue() - xP;
      }

      // lambda2 = 2*y_a / (x_a - x_r) - lambda1
      Assigned? lambda2;
      if (lambda1 != null && yANew != null && xANew.hasValue && xR != null) {
        lambda2 =
            yANew * PallasNativeFp.from(2) * (xANew.getValue() - xR).invert() -
                lambda1;
      }
      region.assignAdvice(doubleAndAdd.lambda2, row + offset, () => lambda2);
      Assigned? xANext;
      // // x_a for next row
      if (lambda2 != null && xANew.hasValue && xR != null) {
        xANext = lambda2.square() - xANew.getValue() - xR;
      }
      // y_a for next iteration
      if (lambda2 != null &&
          xANew.value != null &&
          xANext != null &&
          yANew != null) {
        yANew = lambda2 * (xANew.getValue() - xANext) - yANew;
      }

      xANew =
          region.assignAdvice(doubleAndAdd.xA, row + offset + 1, () => xANext);
    }

    // Witness final y_a
    final yC =
        region.assignAdvice(doubleAndAdd.lambda1, offset + bitlen, () => yANew);

    return (xANew, yC, zs);
  }
}

class MulOverflowConfig {
  // Selector to check z_0 = alpha + t_q (mod p)
  final Selector qMulOverflow;

  // 10-bit lookup table config
  final LookupRangeCheckConfig lookupConfig;

  // Advice columns
  final List<Column<Advice>> advices; // length = 3

  const MulOverflowConfig({
    required this.qMulOverflow,
    required this.lookupConfig,
    required this.advices,
  });

  factory MulOverflowConfig.configure(
    ConstraintSystem meta,
    LookupRangeCheckConfig lookupConfig,
    List<Column<Advice>> advices, // must be length 3
  ) {
    for (final advice in advices) {
      meta.enableEquality(advice);
    }
    final config = MulOverflowConfig(
        qMulOverflow: meta.selector(),
        lookupConfig: lookupConfig,
        advices: advices);

    config._createGate(meta);
    return config;
  }

  void _createGate(ConstraintSystem meta) {
    // https://p.z.cash/halo2-0.1:ecc-var-mul-overflow
    meta.createGate((meta) {
      final qMulOverflow = meta.querySelector(this.qMulOverflow);

      final one = ExpressionConstant(PallasNativeFp.one());
      final twoPow124 = ExpressionConstant(PallasNativeFp(BigInt.one << 124));
      final twoPow130 =
          twoPow124 * ExpressionConstant(PallasNativeFp(BigInt.one << 6));

      final z0 = meta.queryAdvice(advices[0], Rotation.prev());
      final z130 = meta.queryAdvice(advices[0], Rotation.cur());
      final eta = meta.queryAdvice(advices[0], Rotation.next());

      final k254 = meta.queryAdvice(advices[1], Rotation.prev());
      final alpha = meta.queryAdvice(advices[1], Rotation.cur());
      final sMinusLo130 = meta.queryAdvice(advices[1], Rotation.next());

      final s = meta.queryAdvice(advices[2], Rotation.cur());
      final sCheck = s - (alpha + k254 * twoPow130);

      final tQ = ExpressionConstant(PallasNativeFp(Halo2Utils.tQ));

      // z_0 - alpha - t_q = 0 (mod p)
      final recovery = z0 - alpha - tQ;

      // k_254 * (z_130 - 2^124) = 0
      final loZero = k254 * (z130 - twoPow124);

      // k_254 * s_minus_lo_130 = 0
      final sMinusLo130Check = k254 * sMinusLo130;

      // (1 - k_254) * (1 - z_130 * eta) * s_minus_lo_130 = 0
      final canonicity = (one - k254) * (one - z130 * eta) * sMinusLo130;

      return Constraints(selector: qMulOverflow, constraints: [
        sCheck,
        recovery,
        loZero,
        sMinusLo130Check,
        canonicity
      ]);
    });
  }

  void overflowCheck(Layouter layouter, AssignedCell<PallasNativeFp> alpha,
      List<AssignedCell<PallasNativeFp>> zs) {
    assert(zs.length >= 255);

    // Compute s = alpha + k_254 * 2^130
    final k254 = zs[254];
    PallasNativeFp? sVal;
    if (alpha.hasValue && k254.hasValue) {
      sVal = alpha.getValue() +
          k254.getValue() * PallasNativeFp(BigInt.one << 65).square();
    }

    // Assign s to a new region
    final s = layouter.assignRegion((region) {
      return region.assignAdvice(advices[0], 0, () => sVal);
    });

    // Subtract the first 130 bits of s using your decomposition logic
    final sMinusLo130 = _sMinusLo130(layouter, s);

    // Overflow check region
    layouter.assignRegion((region) {
      final offset = 0;

      // Enable overflow check gate
      qMulOverflow.enable(region: region, offset: offset + 1);

      // Copy z_0
      zs[0].copyAdvice(region, advices[0], offset);

      // Copy z_130
      zs[130].copyAdvice(region, advices[0], offset + 1);

      // η = inv0(z_130)
      Assigned? eta;
      if (zs[130].hasValue) {
        eta = AssignedTrivial(zs[130].getValue()).invert(); // 0 -> 0, else 1/x
      }
      region.assignAdvice(advices[0], offset + 2, () => eta);

      // Copy k_254
      zs[254].copyAdvice(region, advices[1], offset);

      // Copy original alpha
      alpha.copyAdvice(region, advices[1], offset + 1);

      // Copy s_minus_lo_130 decomposition
      sMinusLo130.copyAdvice(region, advices[1], offset + 2);

      // Copy witnessed s
      s.copyAdvice(region, advices[2], offset + 1);
    });
  }

  AssignedCell<PallasNativeFp> _sMinusLo130(
    Layouter layouter,
    AssignedCell<PallasNativeFp> s,
  ) {
    const int numBits = 130;
    final int numWords = numBits ~/ HashDomainConst.K; // sinsemillaK = 10
    assert(numWords * HashDomainConst.K == numBits);
    // Decompose the low 130 bits of `s` using k-bit lookups
    final zs = lookupConfig.copyCheck(layouter, s, numWords, false);
    return zs.last;
  }
}
