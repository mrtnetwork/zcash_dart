import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/add.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/constants/fixed_bases.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';

class MulFixedBaseFieldConfig {
  final Selector qMulFixedBaseField;
  final List<Column<Advice>> canonAdvices;
  final LookupRangeCheckConfig lookupConfig;
  final MulFixedConfig superConfig;

  const MulFixedBaseFieldConfig._(
      {required this.qMulFixedBaseField,
      required this.canonAdvices,
      required this.lookupConfig,
      required this.superConfig});

  factory MulFixedBaseFieldConfig.configure(
    ConstraintSystem meta,
    List<Column<Advice>> canonAdvices,
    LookupRangeCheckConfig lookupConfig,
    MulFixedConfig superConfig,
  ) {
    for (final advice in canonAdvices) {
      meta.enableEquality(advice);
    }

    // Ensure canon_advices do not overlap with add_incomplete columns
    final addIncompleteAdvices =
        superConfig.addIncompleteConfig.adviceColumns();
    for (final canon in canonAdvices) {
      if (addIncompleteAdvices.contains(canon)) {
        throw Halo2Exception.operationFailed("configure",
            reason:
                "Deconflict canon_advices with incomplete addition columns.");
      }
    }
    final config = MulFixedBaseFieldConfig._(
        qMulFixedBaseField: meta.selector(),
        canonAdvices: canonAdvices,
        lookupConfig: lookupConfig,
        superConfig: superConfig);
    config._createGate(meta);
    return config;
  }

  void _createGate(ConstraintSystem meta) {
    meta.createGate((meta) {
      final q = meta.querySelector(qMulFixedBaseField);

      // Queries in order
      final alpha = meta.queryAdvice(canonAdvices[0], Rotation.prev());
      final z84Alpha = meta.queryAdvice(canonAdvices[2], Rotation.prev());
      final alpha1 = meta.queryAdvice(canonAdvices[1], Rotation.cur());
      final alpha2 = meta.queryAdvice(canonAdvices[2], Rotation.cur());

      final alpha0Prime = meta.queryAdvice(canonAdvices[0], Rotation.cur());
      final z13Alpha0Prime = meta.queryAdvice(canonAdvices[0], Rotation.next());
      final z44Alpha = meta.queryAdvice(canonAdvices[1], Rotation.next());
      final z43Alpha = meta.queryAdvice(canonAdvices[2], Rotation.next());

      // Derived alpha0
      final alpha0 =
          alpha - z84Alpha * PallasNativeFp(BigInt.one << 126).square();

      // Decomposition checks
      final alpha1RangeCheck = Halo2Utils.rangeCheck(alpha1, 1 << 2);
      final alpha2RangeCheck = Halo2Utils.boolCheck(alpha2);
      final z84Check =
          z84Alpha - (alpha1 + alpha2 * PallasNativeFp.from(1 << 2));

      final decompositionChecks = [
        alpha1RangeCheck,
        alpha2RangeCheck,
        z84Check
      ];

      // alpha0_prime check
      final twoPow130 =
          ExpressionConstant(PallasNativeFp(BigInt.one << 65).square());
      final tP = ExpressionConstant(PallasNativeFp(Halo2Utils.tP));
      final alpha0PrimeCheck = alpha0Prime - (alpha0 + twoPow130 - tP);

      // Canonical checks for MSB = 1
      final alpha0Hi120 = z44Alpha -
          z84Alpha *
              ExpressionConstant(PallasNativeFp(BigInt.one << 60).square());
      final a43 = z43Alpha - z44Alpha * PallasNativeFp.from(Halo2Utils.H);
      final canonChecks = [
        alpha2 * alpha1,
        alpha2 * alpha0Hi120,
        alpha2 * Halo2Utils.boolCheck(a43),
        alpha2 * z13Alpha0Prime
      ];

      return Constraints(selector: q, constraints: [
        ...canonChecks,
        ...decompositionChecks,
        alpha0PrimeCheck
      ]);
    });
  }

  /// Assigns a base-field element multiplication with fixed base and performs canonicity checks.
  EccPoint assign(
    Layouter layouter,
    AssignedCell<PallasNativeFp> scalar,
    OrchardFixedBasesNullifierK base,
  ) {
    // --- Step 1: Incomplete addition ---
    final (scalarDecomposed, acc, mulB) = layouter.assignRegion(
      (Region region) {
        final offset = 0;
        // Decompose scalar into running sum
        final runningSum = superConfig.runningSumConfig.copyDecompose(region,
            offset, scalar, true, PallasFPConst.numBits, base.numWindows);

        final eccScalar = EccBaseFieldElemFixed(
            baseFieldElem: runningSum[0], runningSum: runningSum);
        // Assign inner region
        final (acc, mulB) = superConfig.assignRegionInner(
            region,
            offset,
            ScalarFixedBaseFieldElem(eccScalar),
            base,
            superConfig.runningSumConfig.qRangeCheck);
        return (eccScalar, acc, mulB);
      },
    );

    // --- Step 2: Complete addition ---
    final result = layouter.assignRegion(
      (Region region) {
        return superConfig.addConfig.assignRegion(mulB, acc, 0, region);
      },
    );

    // --- Step 3: Canonicity checks ---
    final alpha = scalarDecomposed.baseFieldElem;
    final runningSum = scalarDecomposed.runningSum;
    final z43Alpha = runningSum[43];
    final z44Alpha = runningSum[44];
    final z84Alpha = runningSum[84];
    PallasNativeFp? alpha0;
    if (alpha.hasValue && z84Alpha.hasValue) {
      final twoPow252 = PallasNativeFp(BigInt.one << 126).square();
      alpha0 = alpha.getValue() - z84Alpha.getValue() * twoPow252;
    }
    PallasNativeFp? vAlpha0Prime;
    if (alpha0 != null) {
      final twoPow130 = PallasNativeFp(BigInt.one << 65).square();
      final tP = PallasNativeFp(Halo2Utils.tP);
      vAlpha0Prime = alpha0 + twoPow130 - tP;
    }

    // Witness 13 ten-bit lookups
    final zs = lookupConfig.witnessCheck(layouter, vAlpha0Prime, 13, false);
    final z13Alpha0Prime = zs[13];
    final alpha0Prime = zs[0];
    // Assign canonicity checks in a region
    layouter.assignRegion((Region region) {
      // Enable canonicity check gate
      qMulFixedBaseField.enable(region: region, offset: 1);

      // Offset 0: copy alpha and z_84_alpha
      var offset = 0;
      alpha.copyAdvice(region, canonAdvices[0], offset);
      z84Alpha.copyAdvice(region, canonAdvices[2], offset);

      // Offset 1: alpha_0_prime, alpha_1, alpha_2
      offset = 1;
      alpha0Prime.copyAdvice(region, canonAdvices[0], offset);

      PallasNativeFp? alpha1;
      if (alpha.hasValue) {
        alpha1 = Halo2Utils.bitrangeSubset(alpha.getValue(), 252, 254);
      }
      region.assignAdvice(canonAdvices[1], offset, () => alpha1);
      PallasNativeFp? alpha2;
      if (alpha.hasValue) {
        alpha2 = Halo2Utils.bitrangeSubset(alpha.getValue(), 254, 255);
      }
      region.assignAdvice(canonAdvices[2], offset, () => alpha2);

      // Offset 2: copy z_13_alpha_0_prime, z_44_alpha, z_43_alpha
      offset = 2;
      z13Alpha0Prime.copyAdvice(region, canonAdvices[0], offset);
      z44Alpha.copyAdvice(region, canonAdvices[1], offset);
      z43Alpha.copyAdvice(region, canonAdvices[2], offset);
    });

    return result;
  }
}

class MulFixedFullConfig {
  final Selector qMulFixedFull;
  final MulFixedConfig superConfig;

  MulFixedFullConfig._({
    required this.qMulFixedFull,
    required this.superConfig,
  });

  factory MulFixedFullConfig.configure(
      ConstraintSystem meta, MulFixedConfig superConfig) {
    final config = MulFixedFullConfig._(
        qMulFixedFull: meta.selector(), superConfig: superConfig);
    config._createGate(meta);
    return config;
  }

  void _createGate(ConstraintSystem meta) {
    meta.createGate((meta) {
      final qMulFixedFull = meta.querySelector(this.qMulFixedFull);
      final window = meta.queryAdvice(superConfig.window, Rotation.cur());

      final coordsConstraints = superConfig.coordsCheck(meta, window);

      final windowRangeCheck = Halo2Utils.rangeCheck(window, Halo2Utils.H);

      return Constraints(
          selector: qMulFixedFull,
          constraints: [...coordsConstraints, windowRangeCheck]);
    });
  }

  EccScalarFixed witness(
    Region region,
    int offset,
    VestaNativeFq? scalar,
  ) {
    final windows = decomposeScalarFixed(scalar, offset, region);
    return EccScalarFixed(value: scalar, windows: windows);
  }

  /// Witnesses the given scalar as `NUM_WINDOWS` 3-bit windows.
  /// The scalar is allowed to be non-canonical.
  List<AssignedCell<PallasNativeFp>> decomposeScalarFixed(
      VestaNativeFq? scalar, int offset, Region region) {
    // Enable `q_mul_fixed_full` selector
    for (var idx = 0; idx < Halo2Utils.numWindows; idx++) {
      qMulFixedFull.enable(region: region, offset: offset + idx);
    }

    // Decompose scalar into `k-bit` windows
    List<int>? scalarWindows;
    if (scalar != null) {
      scalarWindows = Halo2Utils.decomposeWord<VestaNativeFq>(
          scalar, VestaFQConst.numBits, Halo2Utils.fixedBaseWindowSize);
    }

    // Convert windows to Base type
    List<PallasNativeFp?> scalarWindowsBase =
        scalarWindows?.map((e) => PallasNativeFp.from(e)).toList() ??
            List.filled(Halo2Utils.numWindows, null);

    // Store the scalar decomposition
    final List<AssignedCell<PallasNativeFp>> windows = List.generate(
        scalarWindowsBase.length,
        (idx) => region.assignAdvice(
            superConfig.window, offset + idx, () => scalarWindowsBase[idx]));
    return windows;
  }

  (EccPoint, EccScalarFixed) assign(
    Layouter layouter,
    EccScalarFixed scalar,
    OrchardFixedBasesFull base,
  ) {
    // Incomplete addition (main loop)
    final (outScalar, acc, mulB) = layouter.assignRegion(
      (Region region) {
        const offset = 0;

        // Lazily witness the scalar
        final EccScalarFixed witnessedScalar;
        if (scalar.windows == null) {
          witnessedScalar = witness(region, offset, scalar.value);
        } else {
          throw Halo2Exception.operationFailed("assign",
              reason: "Unsupported operation.");
        }
        // Perform fixed-base multiplication (incomplete addition)
        final (acc, mulB) = superConfig.assignRegionInner(region, offset,
            ScalarFixedFullWidth(witnessedScalar), base, qMulFixedFull);
        return (witnessedScalar, acc, mulB);
      },
    );

    // Final complete addition
    final EccPoint result = layouter.assignRegion(
      (Region region) {
        return superConfig.addConfig.assignRegion(mulB, acc, 0, region);
      },
    );

    return (result, outScalar);
  }
}

class MulFixedShortConfig {
  // Selector used for fixed-base scalar mul with short signed exponent.
  final Selector qMulFixedShort;
  // Reference to the super configuration
  final MulFixedConfig superConfig;
  const MulFixedShortConfig._(
      {required this.qMulFixedShort, required this.superConfig});

  factory MulFixedShortConfig.configure(
      ConstraintSystem meta, MulFixedConfig superConfig) {
    final config = MulFixedShortConfig._(
        qMulFixedShort: meta.selector(), superConfig: superConfig);
    config.createGate(meta);
    return config;
  }

  void createGate(ConstraintSystem meta) {
    // Gate contains the following constraints:
    // - short fixed-base mul MSB
    // - conditional negation
    meta.createGate((meta) {
      final qMulFixedShort = meta.querySelector(this.qMulFixedShort);

      final yP = meta.queryAdvice(superConfig.addConfig.yP, Rotation.cur());
      final yA = meta.queryAdvice(superConfig.addConfig.yQr, Rotation.cur());

      // z_21 = k_21
      final lastWindow = meta.queryAdvice(superConfig.u, Rotation.cur());
      final sign = meta.queryAdvice(superConfig.window, Rotation.cur());

      final one = ExpressionConstant(PallasNativeFp.one());

      // Check that last window is either 0 or 1
      final lastWindowCheck = Halo2Utils.boolCheck(lastWindow);

      // Check that sign is either 1 or -1
      final signCheck = sign.square() - one;

      // Check that final y_p = y_a or y_p = -y_a
      final yCheck = (yP - yA) * (yP + yA);

      // Check that the correct sign is witnessed: sign * y_p = y_a
      final negationCheck = sign * yP - yA;

      return Constraints(
          selector: qMulFixedShort,
          constraints: [lastWindowCheck, signCheck, yCheck, negationCheck]);
    });
  }

  /// Multiply the point by sign, constraining `sign` to {-1, 1}.
  EccPoint assignScalarSign(
    Layouter layouter,
    AssignedCell<PallasNativeFp> sign,
    EccPoint point,
  ) {
    return layouter.assignRegion((region) {
      final int offset = 0;

      // Enable mul_fixed_short selector to check the sign logic
      qMulFixedShort.enable(region: region, offset: offset);

      // Set "last window" to 0 (irrelevant here)
      region.assignAdviceFromConstant(
          superConfig.u, offset, AssignedTrivial(PallasNativeFp.zero()));

      // Copy sign to window column
      sign.copyAdvice(region, superConfig.window, offset);

      // Assign input y-coordinate
      point.y.copyAdvice(region, superConfig.addConfig.yQr, offset);

      // Conditionally negate y-coordinate according to sign
      Assigned? signedYVal;
      final signVal = sign.value;
      final yVal = point.y.value;
      if (signVal != null && yVal != null) {
        if (signVal == -PallasNativeFp.one()) {
          signedYVal = -yVal;
        } else {
          signedYVal = yVal;
        }
      }
      // Assign output signed y-coordinate
      final signedY = region.assignAdvice(
          superConfig.addConfig.yP, offset, () => signedYVal);

      return EccPoint(point.x, signedY);
    });
  }

  /// 64-bit range constraint.
  EccScalarFixedShort decompose(
    Region region,
    int offset,
    (MagnitudeCell, SignCell) magnitudeSign,
  ) {
    final magnitude = magnitudeSign.$1;
    final sign = magnitudeSign.$2;

    // Decompose magnitude
    final runningSum = superConfig.runningSumConfig.copyDecompose(
        region,
        offset,
        magnitude,
        true,
        Halo2Utils.lScalarShort,
        Halo2Utils.numWindowShort);

    return EccScalarFixedShort(
        magnitude: magnitude, sign: sign, runningSum: runningSum);
  }

  /// Assigns a short fixed-base scalar multiplication.
  (EccPoint, EccScalarFixedShort) assign(
    Layouter layouter,
    EccScalarFixedShort scalar,
    OrchardFixedBasesValueCommitV base,
  ) {
    // Assign initial region (incomplete addition)
    final (scalarDecomposed, acc, mulB) = layouter.assignRegion(
      (Region region) {
        const offset = 0;

        // Decompose the scalar if running sum is None
        final decomposedScalar = scalar.runningSum == null
            ? decompose(region, offset, (scalar.magnitude, scalar.sign))
            : throw Halo2Exception.operationFailed("assign",
                reason: "Unsupported operation.");
        // Assign inner region for the scalar decomposition
        final (acc, mulB) = superConfig.assignRegionInner(
            region,
            offset,
            ScalarFixedShort(decomposedScalar),
            base,
            superConfig.runningSumConfig.qRangeCheck);

        return (decomposedScalar, acc, mulB);
      },
    );

    // Last window: handle MSB
    final resultPoint = layouter.assignRegion(
      (Region region) {
        int offset = 0;
        // Complete the addition to get [magnitude]B
        final magnitudeMul =
            superConfig.addConfig.assignRegion(mulB, acc, offset, region);
        offset += 1;
        // Copy the sign to the window column
        final signCell = scalarDecomposed.sign
            .copyAdvice(region, superConfig.window, offset);
        // Copy last window to `u` column
        final z21 = scalarDecomposed.runningSum![21];
        z21.copyAdvice(region, superConfig.u, offset);
        // Conditionally negate y-coordinate
        Assigned? yVal;
        if (signCell.hasValue && magnitudeMul.y.hasValue) {
          if (signCell.getValue() == -PallasNativeFp.one()) {
            yVal = -magnitudeMul.y.getValue();
          } else {
            yVal = magnitudeMul.y.value;
          }
        }
        // Enable mul_fixed_short selector
        qMulFixedShort.enable(region: region, offset: offset);
        // Assign final y-coordinate
        final yVar =
            region.assignAdvice(superConfig.addConfig.yP, offset, () => yVal);
        return EccPoint(magnitudeMul.x, yVar);
      },
    );

    // Optional test check (omitted in Dart translation, but can be implemented separately)

    return (resultPoint, scalarDecomposed);
  }
}

class MulFixedConfig {
  final RunningSumConfig runningSumConfig;

  /// Fixed Lagrange interpolation coefficients for `x_p`.
  final List<Column<Fixed>> lagrangeCoeffs;

  /// Fixed `z` for each window such that `y + z = u^2`.
  final Column<Fixed> fixedZ;

  /// Decomposition window column.
  final Column<Advice> window;

  /// y-coordinate of accumulator (used in final row).
  final Column<Advice> u;

  /// Configuration for complete addition.
  final AddConfig addConfig;

  /// Configuration for incomplete addition.
  final AddIncompleteConfig addIncompleteConfig;

  const MulFixedConfig({
    required this.runningSumConfig,
    required this.lagrangeCoeffs,
    required this.fixedZ,
    required this.window,
    required this.u,
    required this.addConfig,
    required this.addIncompleteConfig,
  });

  factory MulFixedConfig.configure(
    ConstraintSystem meta,
    List<Column<Fixed>> lagrangeCoeffs,
    Column<Advice> window,
    Column<Advice> u,
    AddConfig addConfig,
    AddIncompleteConfig addIncompleteConfig,
  ) {
    meta.enableEquality(window);
    meta.enableEquality(u);

    final qRunningSum = meta.selector();
    final runningSumConfig =
        RunningSumConfig.configure(meta, qRunningSum, window);

    final config = MulFixedConfig(
        runningSumConfig: runningSumConfig,
        lagrangeCoeffs: lagrangeCoeffs,
        fixedZ: meta.fixedColumn(),
        window: window,
        u: u,
        addConfig: addConfig,
        addIncompleteConfig: addIncompleteConfig);

    if (config.addConfig.xP != config.addIncompleteConfig.xP ||
        config.addConfig.yP != config.addIncompleteConfig.yP) {
      throw Halo2Exception.operationFailed("configure");
    }

    for (final advice in [config.window, config.u]) {
      if (advice == config.addConfig.xQr || advice == config.addConfig.yQr) {
        throw Halo2Exception.operationFailed("configure",
            reason: "Do not overlap with output columns of add.");
      }
    }

    config._runningSumCoordsGate(meta);

    return config;
  }

  void _runningSumCoordsGate(ConstraintSystem meta) {
    meta.createGate((meta) {
      final qMulFixedRunningSum =
          meta.querySelector(runningSumConfig.qRangeCheck);

      final zCur = meta.queryAdvice(window, Rotation.cur());
      final zNext = meta.queryAdvice(window, Rotation.next());

      final word = zCur - zNext * PallasNativeFp.from(Halo2Utils.H);

      return Constraints(
          selector: qMulFixedRunningSum, constraints: coordsCheck(meta, word));
    });
  }

  List<Expression> coordsCheck(VirtualCells meta, Expression window) {
    final yP = meta.queryAdvice(addConfig.yP, Rotation.cur());
    final xP = meta.queryAdvice(addConfig.xP, Rotation.cur());
    final z = meta.queryFixed(fixedZ);
    final u = meta.queryAdvice(this.u, Rotation.cur());

    // window_pow[i] = window^i
    final List<Expression> windowPow = List.generate(Halo2Utils.H, (pow) {
      Expression acc = ExpressionConstant(PallasNativeFp.one());
      for (int i = 0; i < pow; i++) {
        acc = acc * window;
      }
      return acc;
    });

    // Interpolate x-coordinate using Lagrange coefficients
    Expression interpolatedX = ExpressionConstant(PallasNativeFp.zero());
    for (int i = 0; i < Halo2Utils.H; i++) {
      interpolatedX =
          interpolatedX + windowPow[i] * meta.queryFixed(lagrangeCoeffs[i]);
    }

    // Check interpolation of x-coordinate
    final xCheck = interpolatedX - xP;

    // Check that y + z = u^2
    final yCheck = u.square() - yP - z;

    // Check that (x, y) lies on the curve: y^2 = x^3 + b
    final onCurve = yP.square() -
        xP.square() * xP -
        ExpressionConstant(PastaCurveParams.pallasNative.b);
    return [xCheck, yCheck, onCurve];
  }

  (EccPoint, EccPoint) assignRegionInner(
    Region region,
    int offset,
    ScalarFixed scalar,
    OrchardFixedBases base,
    Selector coordsCheckToggle,
  ) {
    // Assign fixed columns for the given fixed base
    assignFixedConstants(
      region,
      offset,
      base,
      coordsCheckToggle,
    );

    // Initialize accumulator
    EccPoint acc = initializeAccumulator(
      region,
      offset,
      base,
      scalar,
    );

    // Process all windows except the least and most significant ones
    acc = addIncomplete(
      region,
      offset,
      acc,
      base,
      scalar,
    );
    // Process most significant window
    final EccPoint mulB = processMsb(
      region,
      offset,
      base,
      scalar,
    );
    return (acc, mulB);
  }

  /// Adds incomplete windows to the accumulator.
  EccPoint addIncomplete(Region region, int offset, EccPoint acc,
      OrchardFixedBases base, ScalarFixed scalar) {
    final scalarWindowsField = scalar.windowsField();
    final scalarWindowsUsize = scalar.windowsUsize();

    assert(scalarWindowsField.length == base.numWindows);

    for (var w = 1; w < base.numWindows - 1; w++) {
      final k = scalarWindowsField[w];
      final kUsize = scalarWindowsUsize[w];

      // Compute [(k_w + 2) ⋅ 8^w]B
      final mulB = processLowerBits(
        region,
        offset,
        w,
        k,
        kUsize,
        base,
      );

      // AstAdd to the accumulator
      acc = addIncompleteConfig.assignRegion(
        mulB,
        acc,
        offset + w,
        region,
      );
    }

    return acc;
  }

  void assignFixedConstants(
    Region region,
    int offset,
    OrchardFixedBases base,
    Selector coordsCheckToggle,
  ) {
    int numWindows = base.numWindows;

    // Lazily build constants
    (List<List<PallasNativeFp>>, List<int>) buildConstants() {
      final lagrangeCoeffs = base.lagrangeCoeffs();
      final z = base.z();
      return (lagrangeCoeffs, z);
    }

    late (List<List<PallasNativeFp>>, List<int>) constants = buildConstants();

    // Assign fixed columns for each window
    for (int window = 0; window < numWindows; window++) {
      coordsCheckToggle.enable(region: region, offset: window + offset);

      // Assign x-coordinate Lagrange interpolation coefficients
      for (int k = 0; k < Halo2Utils.H; k++) {
        region.assignFixed(
          lagrangeCoeffs[k],
          window + offset,
          () {
            final lagrange = constants.$1;
            return lagrange[window][k];
          },
        );
      }
      // Assign z-values for each window
      region.assignFixed(
        fixedZ,
        window + offset,
        () {
          final z = constants.$2;
          return PallasNativeFp.from(z[window]);
        },
      );
    }
  }

  EccPoint processWindow(Region region, int offset, int w, int? kUsize,
      VestaNativeFq? windowScalar, OrchardFixedBases base) {
    final baseValue = base.generator();
    final baseU = base.u();
    assert(baseU.length == base.numWindows);

    // Compute [windowScalar]B
    final EccPoint mulB = (() {
      Coordinates<PallasNativeFp>? mulBAffine;
      if (windowScalar != null) {
        mulBAffine = (baseValue * windowScalar).toAffine().coordinates();
      }
      Assigned? xVal;
      if (mulBAffine != null) {
        final x = mulBAffine.x;
        if (x.isZero()) {
          throw Halo2Exception.operationFailed("processWindow",
              reason: "Zero point not allowed.");
        }
        xVal = AssignedTrivial(x);
      }
      final xCell = region.assignAdvice(addConfig.xP, offset + w, () => xVal);
      Assigned? yVal;
      if (mulBAffine != null) {
        final y = mulBAffine.y;
        if (y.isZero()) {
          throw Halo2Exception.operationFailed("processWindow",
              reason: "Zero point not allowed.");
        }
        yVal = AssignedTrivial(y);
      }
      final yCell = region.assignAdvice(addConfig.yP, offset + w, () => yVal);
      return EccPoint(xCell, yCell);
    })();
    PallasNativeFp? uVal;
    if (kUsize != null) {
      uVal = PallasNativeFp.nP(baseU[w][kUsize]);
    }
    region.assignAdvice(u, offset + w, () => uVal);
    return mulB;
  }

  EccPoint initializeAccumulator(
      Region region, int offset, OrchardFixedBases base, ScalarFixed scalar) {
    final int w = 0;
    final k0 = scalar.windowsField()[0];
    final k0Usize = scalar.windowsUsize()[0];
    return processLowerBits(region, offset, w, k0, k0Usize, base);
  }

  EccPoint processLowerBits(
    Region region,
    int offset,
    int w,
    VestaNativeFq? k,
    int? kUsize,
    OrchardFixedBases base,
  ) {
    // Compute scalar only if k is known
    VestaNativeFq? scalar;
    if (k != null) {
      scalar = (k + VestaNativeFq.from(2)) *
          VestaNativeFq.from(Halo2Utils.H).pow(BigInt.from(w));
    }

    return processWindow(region, offset, w, kUsize, scalar, base);
  }

  /// Assigns the values used to process the window containing the MSB.
  EccPoint processMsb(
    Region region,
    int offset,
    OrchardFixedBases base,
    ScalarFixed scalar,
  ) {
    final kUsize = scalar.windowsUsize()[base.numWindows - 1];
    final twoScalr = VestaNativeFq.from(2);

    final hScalar = VestaNativeFq.from(Halo2Utils.H);
    VestaNativeFq offsetAcc = VestaNativeFq.zero();
    for (var w = 0; w < base.numWindows - 1; w++) {
      offsetAcc +=
          twoScalr.pow(BigInt.from(Halo2Utils.fixedBaseWindowSize * w + 1));
    }

    final windowsField = scalar.windowsField();
    VestaNativeFq? windowScalar;
    final sc = windowsField[windowsField.length - 1];
    if (sc != null) {
      windowScalar =
          sc * hScalar.pow(BigInt.from(base.numWindows - 1)) - offsetAcc;
    }
    return processWindow(
        region, offset, base.numWindows - 1, kUsize, windowScalar, base);
  }
}

sealed class ScalarFixed {
  const ScalarFixed();

  static List<VestaNativeFq?> _windowsField(
      List<AssignedCell<PallasNativeFp>> zs) {
    final hp = PallasNativeFp.from(Halo2Utils.H);
    return List.generate(
      zs.length - 1,
      (i) {
        final zCur = zs[i].value;
        final zNext = zs[i + 1].value;
        PallasNativeFp? word;
        if (zCur != null && zNext != null) {
          word = zCur - zNext * hp;
        }
        if (word != null) {
          return VestaNativeFq.fromBytes(word.toBytes());
        }
        return null;
      },
    );
  }

  List<int?> windowsUsize() {
    final fields = windowsField();
    return fields.map((e) {
      if (e != null) {
        final size = e
            .toBits()
            .take(Halo2Utils.fixedBaseWindowSize)
            .toList()
            .reversed
            .fold(0, (p, c) => 2 * p + (c ? 1 : 0));
        return size;
      }
      return null;
    }).toList();
  }

  List<VestaNativeFq?> windowsField();
}

class ScalarFixedFullWidth extends ScalarFixed {
  final EccScalarFixed inner;
  const ScalarFixedFullWidth(this.inner);
  @override
  List<VestaNativeFq?> windowsField() {
    final windows = inner.windows;
    if (windows == null) {
      throw Halo2Exception.operationFailed("windowsField",
          reason: "Missing windows elements.");
    }
    return windows.map((e) {
      if (e.hasValue) {
        return VestaNativeFq.fromBytes(e.getValue().toBytes());
      }
      return null;
    }).toList();
  }
}

class ScalarFixedShort extends ScalarFixed {
  final EccScalarFixedShort inner;
  const ScalarFixedShort(this.inner);

  @override
  List<VestaNativeFq?> windowsField() {
    final runningSum = inner.runningSum;
    if (runningSum == null) {
      throw Halo2Exception.operationFailed("windowsField",
          reason: "Missing runningSum elements.");
    }
    return ScalarFixed._windowsField(runningSum);
  }
}

class ScalarFixedBaseFieldElem extends ScalarFixed {
  final EccBaseFieldElemFixed inner;
  const ScalarFixedBaseFieldElem(this.inner);

  @override
  List<VestaNativeFq?> windowsField() {
    return ScalarFixed._windowsField(inner.runningSum);
  }
}
