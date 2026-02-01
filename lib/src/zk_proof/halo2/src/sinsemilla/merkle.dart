import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/mul.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/message.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/table.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/range_constrained.dart';

class MerkleConfig {
  final List<Column<Advice>> advices; // length = 5
  final Selector qDecompose;

  /// Configuration for the CondSwapChip.
  final CondSwapConfig condSwapConfig;

  /// Embedded Sinsemilla configuration.
  final SinsemillaConfig sinsemillaConfig;

  const MerkleConfig({
    required this.advices,
    required this.qDecompose,
    required this.condSwapConfig,
    required this.sinsemillaConfig,
  });
  factory MerkleConfig.configure(
      ConstraintSystem meta, SinsemillaConfig sinsemillaConfig) {
    // All five advice columns are equality-enabled by SinsemillaConfig.
    final advices = sinsemillaConfig.advices();
    final condSwapConfig = CondSwapConfig.configure(meta, advices);

    // Selector enabling the decomposition gate
    final qDecompose = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qDecompose);

      final lWhole = meta.queryAdvice(advices[4], Rotation.next());

      final twoPow5 = PallasNativeFp(BigInt.one << 5);
      final twoPow10 = twoPow5.square();

      final aWhole = meta.queryAdvice(advices[0], Rotation.cur());
      final bWhole = meta.queryAdvice(advices[1], Rotation.cur());
      final cWhole = meta.queryAdvice(advices[2], Rotation.cur());
      final leftNode = meta.queryAdvice(advices[3], Rotation.cur());
      final rightNode = meta.queryAdvice(advices[4], Rotation.cur());

      // ---- a decomposition ----
      final z1A = meta.queryAdvice(advices[0], Rotation.next());
      final a1 = z1A;
      final a0 = aWhole - a1 * twoPow10;

      // ---- b decomposition ----
      final z1B = meta.queryAdvice(advices[1], Rotation.next());
      final b1 = meta.queryAdvice(advices[2], Rotation.next());
      final b2 = meta.queryAdvice(advices[3], Rotation.next());

      final b1b2Check = z1B - (b1 + b2 * twoPow5);
      final b0 = bWhole - z1B * twoPow10;

      // ---- left reconstruction ----
      final leftCheck = () {
        final twoPow240 = PallasNativeFp(BigInt.one << 120).square();
        final reconstructed = a1 + (b0 + b1 * twoPow10) * twoPow240;
        return reconstructed - leftNode;
      }();

      // ---- right reconstruction ----
      final rightCheck = b2 + cWhole * twoPow5 - rightNode;

      return Constraints(
        selector: q,
        constraints: [a0 - lWhole, leftCheck, rightCheck, b1b2Check],
      );
    });

    return MerkleConfig(
      advices: advices,
      qDecompose: qDecompose,
      condSwapConfig: condSwapConfig,
      sinsemillaConfig: sinsemillaConfig,
    );
  }

  AssignedCell<PallasNativeFp> hashLayer(
      Layouter layouter,
      PallasAffineNativePoint Q,
      int l,
      AssignedCell<PallasNativeFp> left,
      AssignedCell<PallasNativeFp> right) {
    final SinsemillaMessagePiece a = SinsemillaMessagePiece.fromSubpieces(
      chip: sinsemillaConfig,
      layouter: layouter,
      subpieces: [
        RangeConstrained.bitrangeOf(PallasNativeFp.from(l), 0, 10),
        RangeConstrained.bitrangeOf(left.value, 0, 240),
      ],
    );

    // b_0 = bits 240..249 of left
    final b0 = RangeConstrained.bitrangeOf(left.value, 240, 250);

    // b_1 = bits 250..254 of left (5 bits)
    final b1 = sinsemillaConfig.lookupConfig
        .witnessShort(layouter, left.value, 250, PallasFPConst.numBits);

    // b_2 = bits 0..4 of right (5 bits)
    final b2 =
        sinsemillaConfig.lookupConfig.witnessShort(layouter, right.value, 0, 5);

    final b = SinsemillaMessagePiece.fromSubpieces(
      chip: sinsemillaConfig,
      layouter: layouter,
      subpieces: [b0, b1.value(), b2.value()],
    );

    // c = bits 5..254 of right
    final SinsemillaMessagePiece c = SinsemillaMessagePiece.fromSubpieces(
      chip: sinsemillaConfig,
      layouter: layouter,
      subpieces: [
        RangeConstrained.bitrangeOf(right.value, 5, PallasFPConst.numBits),
      ],
    );

    // hash = SinsemillaHash(Q, l || left || right)
    final (point, zs) = hashToPoint(layouter, Q, SinsemillaMessage([a, b, c]));

    final hash = sinsemillaConfig.extract(point);

    // Grab z1 values for decomposition checks
    final AssignedCell<PallasNativeFp> z1A = zs[0][1];
    final AssignedCell<PallasNativeFp> z1B = zs[1][1];

    // ---- Decomposition constraints ----
    layouter.assignRegion(
      (Region region) {
        // Enable selector
        qDecompose.enable(region: region, offset: 0);

        // Fixed l at offset 1
        region.assignAdviceFromConstant(advices[4], 1, PallasNativeFp.from(l));

        // Offset 0
        a.cellValue.copyAdvice(
          region,
          advices[0],
          0,
        );
        b.cellValue.copyAdvice(
          region,
          advices[1],
          0,
        );
        c.cellValue.copyAdvice(
          region,
          advices[2],
          0,
        );
        left.copyAdvice(
          region,
          advices[3],
          0,
        );
        right.copyAdvice(
          region,
          advices[4],
          0,
        );

        // Offset 1
        z1A.copyAdvice(
          region,
          advices[0],
          1,
        );
        z1B.copyAdvice(
          region,
          advices[1],
          1,
        );
        b1.inner.copyAdvice(
          region,
          advices[2],
          1,
        );
        b2.inner.copyAdvice(
          region,
          advices[3],
          1,
        );
      },
    );

    bool test() {
      final leftVal = left.value;
      final rightVal = right.value;
      final hashVal = hash.value;
      if (leftVal != null && rightVal != null && hashVal != null) {
        final lBits = IntUtils.toBinaryBool(l, bitLength: 10);
        final leftBits = leftVal.toBits().take(PallasFPConst.numBits).toList();
        final rightBits =
            rightVal.toBits().take(PallasFPConst.numBits).toList();
        final merkleCrh = HashDomainNative(
            q: Q.toCurve(), sinsemillaS: sinsemillaConfig.sinsemillaS);
        final List<bool> message = [...lBits, ...leftBits, ...rightBits];
        final expected = merkleCrh.hash(message);
        return expected == hashVal;
      }
      return true;
    }

    assert(test());
    return hash;
  }

  // Witness a message piece
  SinsemillaMessagePiece witnessMessagePiece(
    Layouter layouter,
    PallasNativeFp? value,
    int numWords,
  ) {
    // final chip = SinsemillaChip.construct(sinsemillaConfig);
    return sinsemillaConfig.witnessMessagePiece(layouter, value, numWords);
  }

  // Hash message to a point (public Q)
  (EccPoint, List<List<AssignedCell<PallasNativeFp>>>) hashToPoint(
    Layouter layouter,
    PallasAffineNativePoint Q,
    SinsemillaMessage message,
  ) {
    final (point, runningSum) =
        sinsemillaConfig.hashToPoint(layouter, Q, message);
    return (point, runningSum);
  }

  // Hash message to a point using private initialization
  (EccPoint, List<List<AssignedCell<PallasNativeFp>>>)
      hashToPointWithPrivateInit(
    Layouter layouter,
    EccPoint Q,
    SinsemillaMessage message,
  ) {
    final (point, runningSum) =
        sinsemillaConfig.hashToPointWithPrivateInit(layouter, Q, message);
    return (point, runningSum);
  }

  // Hash message to a point using private initialization
  AssignedCell<PallasNativeFp> mux(
    Layouter layouter,
    AssignedCell<PallasNativeFp> choice,
    AssignedCell<PallasNativeFp> left,
    AssignedCell<PallasNativeFp> right,
  ) {
    return condSwapConfig.mux(layouter, choice, left, right);
  }

  (AssignedCell<PallasNativeFp>, AssignedCell<PallasNativeFp>) swap(
    Layouter layouter,
    (AssignedCell<PallasNativeFp>, PallasNativeFp?) pair,
    bool? swap,
  ) {
    return condSwapConfig.swap(layouter, pair, swap);
  }
}

class HalOrchardMerklePath {
  final List<MerkleConfig> chips;
  final PallasAffineNativePoint q;
  final int? leafPosition;
  final List<PallasNativeFp>? path;
  final int pathLength;
  const HalOrchardMerklePath(
      {required this.chips,
      required this.q,
      required this.leafPosition,
      required this.path,
      this.pathLength = 32});

  AssignedCell<PallasNativeFp> calculateRoot(
      Layouter layouter, AssignedCell<PallasNativeFp> leaf) {
    final int layersPerChip =
        ((pathLength + this.chips.length - 1) ~/ this.chips.length);

    // Assign each layer to a chip
    final List<MerkleConfig> chips =
        List.generate(pathLength, (i) => this.chips[(i ~/ layersPerChip)]);

    // The Merkle path from leaf to root
    final List<PallasNativeFp?> path =
        this.path?.clone() ?? List.filled(pathLength, null);

    // Get position as a PATH_LENGTH-bit bitstring (little-endian)
    List<bool?> pos = [];
    if (leafPosition != null) {
      pos = IntUtils.toBinaryBool(leafPosition!, bitLength: pathLength);
    } else {
      pos = List.filled(pathLength, null);
    }

    AssignedCell<PallasNativeFp> node = leaf;

    for (int l = 0; l < pathLength; l++) {
      // Conditional swap: determine left/right ordering
      final pair = chips[l].swap(layouter, (node, path[l]), pos[l]);

      // Compute node at this layer
      node = chips[l].hashLayer(layouter, q, l, pair.$1, pair.$2);
    }

    return node;
  }
}

class SinsemillaConfig {
  /// Binary selector used in lookup argument and in the body of the Sinsemilla hash.
  final Selector qSinsemilla1;

  /// Non-binary selector used in lookup argument and in the body of the Sinsemilla hash.
  final Column<Fixed> qSinsemilla2;

  /// Simple selector used to constrain hash initialization to be consistent with
  /// the y-coordinate of the domain Q.
  final Selector qSinsemilla4;

  /// Fixed column used to load the y-coordinate of the domain Q.
  final Column<Fixed> fixedYQ;

  /// Logic specific to merged double-and-add.
  final DoubleAndAdd doubleAndAdd;

  /// Advice column used to load the message.
  final Column<Advice> bits;

  /// Advice column used to witness message pieces.
  final Column<Advice> witnessPieces;

  /// Generator lookup table (idx, x, y).
  final GeneratorTableConfig generatorTable;

  /// Lookup configuration for range checks.
  final LookupRangeCheckConfig lookupConfig;

  /// Whether initialization from a private point is allowed.
  final bool allowInitFromPrivatePoint;

  final List<PallasAffineNativePoint> sinsemillaS;

  const SinsemillaConfig({
    required this.qSinsemilla1,
    required this.qSinsemilla2,
    required this.qSinsemilla4,
    required this.fixedYQ,
    required this.doubleAndAdd,
    required this.bits,
    required this.witnessPieces,
    required this.generatorTable,
    required this.lookupConfig,
    required this.allowInitFromPrivatePoint,
    required this.sinsemillaS,
  });

  factory SinsemillaConfig.configure(
      {required ConstraintSystem meta,
      required List<Column<Advice>> advices, // length = 5
      required Column<Advice> witnessPieces,
      required Column<Fixed> fixedYQ,
      required (TableColumn, TableColumn, TableColumn) lookup, // (idx, x, y)
      required LookupRangeCheckConfig rangeCheck,
      required bool allowInitFromPrivatePoint,
      required ZCashCryptoContext context}) {
    for (final advice in advices) {
      meta.enableEquality(advice);
    }

    final config = SinsemillaConfig(
        qSinsemilla1: meta.complexSelector(),
        qSinsemilla2: meta.fixedColumn(),
        qSinsemilla4: meta.selector(),
        sinsemillaS: context.getSinsemillaS(),
        fixedYQ: fixedYQ,
        doubleAndAdd: DoubleAndAdd(
            xA: advices[0],
            xP: advices[1],
            lambda1: advices[3],
            lambda2: advices[4]),
        bits: advices[2],
        witnessPieces: witnessPieces,
        generatorTable: GeneratorTableConfig(
            tableIdx: lookup.$1, tableX: lookup.$2, tableY: lookup.$3),
        lookupConfig: rangeCheck,
        allowInitFromPrivatePoint: allowInitFromPrivatePoint);

    // Set up lookup argument
    GeneratorTableConfig.configure(meta, config);

    final two = PallasNativeFp.two();

    // x_r = lambda_1^2 - x_a - x_p
    Expression xR(VirtualCells meta, Rotation rotation) {
      return config.doubleAndAdd.xR(meta, rotation);
    }

    // Y_A = (lambda_1 + lambda_2) * (x_a - x_r)
    Expression yA(VirtualCells meta, Rotation rotation) {
      return config.doubleAndAdd.yA(meta, rotation);
    }

    // ---------------- Initial y_Q gate ----------------
    meta.createGate((meta) {
      final qS4 = meta.querySelector(config.qSinsemilla4);
      final yQ = allowInitFromPrivatePoint
          ? meta.queryAdvice(config.doubleAndAdd.xP, Rotation.prev())
          : meta.queryFixed(config.fixedYQ);

      final yACur = yA(meta, Rotation.cur());
      // 2 * y_q - Y_A = 0
      final initYQCheck = yQ * two - yACur;
      return Constraints(selector: qS4, constraints: [initYQCheck]);
    });

    // ---------------- Sinsemilla main gate ----------------
    meta.createGate((meta) {
      final qS1 = meta.querySelector(config.qSinsemilla1);
      final qS3 = config.qS3(meta);

      final lambda1Next =
          meta.queryAdvice(config.doubleAndAdd.lambda1, Rotation.next());
      final lambda2Cur =
          meta.queryAdvice(config.doubleAndAdd.lambda2, Rotation.cur());
      final xACur = meta.queryAdvice(config.doubleAndAdd.xA, Rotation.cur());
      final xANext = meta.queryAdvice(config.doubleAndAdd.xA, Rotation.next());

      final xRCur = xR(meta, Rotation.cur());

      final yACur = yA(meta, Rotation.cur());
      final yANext = yA(meta, Rotation.next());

      // lambda_2^2 - (x_a_next + x_r + x_a_cur) = 0
      final secantLine = lambda2Cur.square() - (xANext + xRCur + xACur);

      // lhs - rhs = 0
      final yCheck = () {
        // lhs = 4 * lambda_2 * (x_a_cur - x_a_next)
        final lhs = lambda2Cur * PallasNativeFp.from(4) * (xACur - xANext);

        // y_a_final is assigned to lambda_1 at next row
        final yAFinal = lambda1Next;

        // rhs = 2*Y_A_cur + (2 - q_s3)*Y_A_next + 2*q_s3*y_a_final
        final rhs = yACur * two +
            (ExpressionConstant(two) - qS3) * yANext +
            qS3 * two * yAFinal;

        return lhs - rhs;
      }();

      return Constraints(selector: qS1, constraints: [secantLine, yCheck]);
    });

    return config;
  }

  Expression qS3(VirtualCells meta) {
    final one = ExpressionConstant(PallasNativeFp.one());
    final qS2 = meta.queryFixed(qSinsemilla2);
    return qS2 * (qS2 - one);
  }

  /// Returns all advice columns in this config, in arbitrary order.
  List<Column<Advice>> advices() {
    return [
      doubleAndAdd.xA,
      doubleAndAdd.xP,
      bits,
      doubleAndAdd.lambda1,
      doubleAndAdd.lambda2
    ];
  }

  void load(Layouter layouter) {
    generatorTable.load(
        lookupConfig: lookupConfig,
        layouter: layouter,
        sinsemillaS: sinsemillaS);
  }

  (int, AssignedCell<Assigned>, Assigned?) privateQInitialization(
      Region region, EccPoint Q) {
    if (!allowInitFromPrivatePoint) {
      throw Halo2Exception.operationFailed("privateQInitialization",
          reason: "Operation not allowed.");
    }

    /// ---- Assign y_Q ----
    final Assigned? yA = (() {
      // Enable q_sinsemilla4 on row 1
      qSinsemilla4.enable(region: region, offset: 1);
      final q = Q.getY();
      final AssignedCell<Assigned> qY = AssignedCell(
          value: q.hasValue ? AssignedTrivial(q.getValue()) : null,
          cell: q.cell);

      final AssignedCell<Assigned> yAssigned =
          qY.copyAdvice(region, doubleAndAdd.xP, 0);

      return yAssigned.value;
    })();

    /// ---- Assign x_Q ----
    final AssignedCell<Assigned> xA = (() {
      final x = Q.getX();
      final AssignedCell<Assigned> qX = AssignedCell(
          value: x.hasValue ? AssignedTrivial(x.getValue()) : null,
          cell: x.cell);

      final AssignedCell<Assigned> xAssigned = qX.copyAdvice(
        region,
        doubleAndAdd.xA,
        1,
      );

      return xAssigned;
    })();

    // offset = 1
    return (1, xA, yA);
  }

  (EccPoint, List<List<AssignedCell<PallasNativeFp>>>)
      hashMessageWithPrivateInit(
          Region region, EccPoint Q, SinsemillaMessage message) {
    // ---- Permission gate ----
    if (!allowInitFromPrivatePoint) {
      throw Halo2Exception.operationFailed("hashMessageWithPrivateInit",
          reason: "Operation not allowed.");
    }

    // ---- Private Q initialization ----
    final (offset, xA0_, yA0_) = privateQInitialization(region, Q);

    // ---- Hash message pieces ----
    final (xA, yA, zsSum) = hashAllPieces(region, offset, message, xA0_, yA0_);

    // ---- Test-only equivalence check ----
    assert(checkHashResult(Q.toPoint(), message, xA, yA));

    // ---- Non-identity checks ----
    // final Base? xValue = xA.value;
    if (xA.hasValue && xA.getValue().isZero) {
      throw Halo2Exception.operationFailed("hashMessageWithPrivateInit",
          reason: "Invalid ECC point.");
    }

    if (yA.hasValue && yA.getValue().isZero) {
      throw Halo2Exception.operationFailed("hashMessageWithPrivateInit",
          reason: "Invalid ECC point.");
    }
    // ---- Construct result ----
    return (EccPoint(xA, yA), zsSum);
  }

  SinsemillaMessagePiece witnessMessagePiece(
      Layouter layouter, PallasNativeFp? fieldElem, int numWords) {
    final cell = layouter.assignRegion(
      (Region region) {
        return region.assignAdvice(witnessPieces, 0, () => fieldElem);
      },
    );

    return SinsemillaMessagePiece(cell, numWords);
  }

  (EccPoint, List<List<AssignedCell<PallasNativeFp>>>) hashToPoint(
    Layouter layouter,
    PallasAffineNativePoint Q,
    SinsemillaMessage message,
  ) {
    return layouter.assignRegion(
      (Region region) {
        final (p, runningSum) = hashMessage(region, Q, message);
        return (p, runningSum);
      },
    );
  }

  (EccPoint, List<List<AssignedCell<PallasNativeFp>>>)
      hashToPointWithPrivateInit(
    Layouter layouter,
    EccPoint Q,
    SinsemillaMessage message,
  ) {
    return layouter.assignRegion(
      (Region region) {
        final (p, runningSum) = hashMessageWithPrivateInit(region, Q, message);
        return (p, runningSum);
      },
    );
  }

  bool checkHashResult(
    PallasAffineNativePoint? q,
    SinsemillaMessage message,
    AssignedCell<Assigned> xA,
    AssignedCell<Assigned> yA,
  ) {
    // return true;
    List<(PallasNativeFp, int)>? fieldElems;
    if (message.messages.every((e) => e.cellValue.hasValue)) {
      fieldElems = message.messages
          .map((e) => (e.cellValue.getValue(), e.numWords))
          .toList();
    }
    // // Resolve Q to a concrete value if known
    // PallasAffineNativePoint? valueQ;
    // switch (Q) {
    //   case final EccPointQPublicPoint p:
    //     valueQ = p.inner;
    //     break;
    //   case final EccPointQPrivatePoint p:
    //     valueQ = p.inner.toPoint();
    //     break;
    // }

    final Assigned? xValue = xA.value;
    final Assigned? yValue = yA.value;

    if (fieldElems != null && xValue != null && yValue != null && q != null) {
      // final fields = fieldElems;

      /// ---- Build message bitstring ----
      final List<bool> bitstring = [];
      for (final (fe, numWords) in fieldElems) {
        final bits = fe.toBits();
        bitstring.addAll(bits.take(HashDomainConst.K * numWords));
      }
      PallasNativePoint S(List<bool> message) => PallasNativePoint.hashToCurve(
          domainPrefix: "z.cash:SinsemillaS",
          message: BitUtils.bitsToInt(message).toU32LeBytes());
      PallasAffineNativePoint expectedPoint = q;
      for (int i = 0; i < bitstring.length; i += HashDomainConst.K) {
        final bits = bitstring.sublist(i, i + HashDomainConst.K);
        expectedPoint = ((expectedPoint + S(bits)) + expectedPoint).toAffine();
      }
      final actualPoint =
          PallasAffineNativePoint(x: xValue.evaluate(), y: yValue.evaluate());
      return expectedPoint == actualPoint;
    }
    return true;
  }

  (EccPoint, List<List<AssignedCell<PallasNativeFp>>>) hashMessage(
      Region region, PallasAffineNativePoint Q, SinsemillaMessage message) {
    final (offset, xA_, yA_) = publicQInitialization(region, Q);

    final (xA, yA, zsSum) = hashAllPieces(region, offset, message, xA_, yA_);

    assert(checkHashResult(Q, message, xA, yA));

    if (xA.hasValue && yA.hasValue) {
      if (xA.getValue().isZero || yA.getValue().isZero) {
        throw Halo2Exception.operationFailed("hashMessage",
            reason: "Invalid ECC identity point.");
      }
    }

    return (EccPoint(xA, yA), zsSum);
  }

  (int, AssignedCell<Assigned>, Assigned?) publicQInitialization(
    Region region,
    PallasAffineNativePoint Q,
  ) {
    var offset = 0;

    // Get the x- and y-coordinates of the starting Q base
    final xQ = Q.x;
    final yQ = Q.y;

    // Constrain the initial x_a, lambda_1, lambda_2, x_p
    // using the q_sinsemilla4 selector.
    Assigned? yA;
    if (allowInitFromPrivatePoint) {
      // Enable q_sinsemilla4 on the second row
      qSinsemilla4.enable(region: region, offset: offset + 1);

      final yACell = region.assignAdviceFromConstant(
          doubleAndAdd.xP, offset, AssignedTrivial(yQ));

      offset += 1;
      yA = yACell.value;
    } else {
      // Enable q_sinsemilla4 on the first row
      qSinsemilla4.enable(region: region, offset: offset);

      region.assignFixed(fixedYQ, offset, () => yQ);
      yA = AssignedTrivial(yQ);
    }

    // Constrain the initial x_q to equal the x-coordinate of the domain's Q
    final xA = region.assignAdviceFromConstant(
        doubleAndAdd.xA, offset, AssignedTrivial(xQ));

    return (offset, xA, yA);
  }

  (
    AssignedCell<Assigned>,
    Assigned?,
    List<AssignedCell<PallasNativeFp>>,
  ) hashPiece(
    Region region,
    int offset,
    SinsemillaMessagePiece piece,
    AssignedCell<Assigned> xA,
    Assigned? yA,
    bool finalPiece,
  ) {
    // --- Selector assignments ---
    // Enable q_sinsemilla1 on every row
    for (var row = 0; row < piece.numWords; row++) {
      qSinsemilla1.enable(region: region, offset: offset + row);
    }

    // Set q_sinsemilla2 = 1 on every row but the last
    for (var row = 0; row < piece.numWords - 1; row++) {
      region.assignFixed(
          qSinsemilla2, offset + row, () => PallasNativeFp.one());
    }

    // Set q_sinsemilla2 on the last row
    region.assignFixed(qSinsemilla2, offset + piece.numWords - 1,
        () => finalPiece ? PallasNativeFp.from(2) : PallasNativeFp.zero());
    List<bool>? bitString;
    if (piece.cellValue.hasValue) {
      bitString = piece.cellValue
          .getValue()
          .toBits()
          .take(HashDomainConst.K * piece.numWords)
          .toList();
    }
    // // --- SinsemillaMessage bit decomposition ---

    List<int>? wordsValue;
    if (bitString != null) {
      wordsValue = <int>[];
      final chunks = CompareUtils.chunk(bitString, HashDomainConst.K);
      for (final i in chunks) {
        wordsValue.add(BitUtils.bitsToInt(i));
      }
    }
    List<(PallasNativeFp, PallasNativeFp)>? generatorsValue;
    if (wordsValue != null) {
      generatorsValue = wordsValue.map((e) {
        final s = sinsemillaS[e];
        return (s.x, s.y);
      }).toList();
    }

    List<int?> words = wordsValue ?? List.filled(piece.numWords, null);

    // --- Running sum decomposition ---
    final List<AssignedCell<PallasNativeFp>> zs = [
      piece.cellValue.copyAdvice(region, bits, offset)
    ];

    PallasNativeFp? z = piece.cellValue.value;
    final invTwoPowK = PallasNativeFp.from(1 << HashDomainConst.K).invert()!;
    for (var i = 0; i < words.length - 1; i++) {
      if (words[i] != null && z != null) {
        z = (z - PallasNativeFp.from(words[i]!)) * invTwoPowK;
      } else {
        z = null;
      }
      zs.add(region.assignAdvice(bits, offset + i + 1, () => z));
    }

    // --- Curve operations ---
    List<(PallasNativeFp, PallasNativeFp)?> generators =
        generatorsValue ?? List.filled(piece.numWords, null);
    for (var row = 0; row < generators.length; row++) {
      final gen = generators[row];
      Assigned? xP;
      Assigned? yP;
      if (gen != null) {
        xP = AssignedTrivial(gen.$1);
        yP = AssignedTrivial(gen.$2);
      }

      // Assign x_p
      region.assignAdvice(
        doubleAndAdd.xP,
        offset + row,
        () => xP,
      );

      // lambda_1
      final lambda1 = yA != null && yP != null && xA.hasValue && xP != null
          ? (yA - yP) * (xA.getValue() - xP).invert()
          : null;
      region.assignAdvice(doubleAndAdd.lambda1, offset + row, () => lambda1);

      // x_r
      final xR = lambda1 != null && xP != null
          ? lambda1.square() - xA.getValue() - xP
          : null;
      // lambda_2
      final lambda2 = yA != null && xR != null && lambda1 != null
          ? yA * PallasNativeFp.from(2) * (xA.getValue() - xR).invert() -
              lambda1
          : null;
      region.assignAdvice(doubleAndAdd.lambda2, offset + row, () => lambda2);
      // x_a next
      final xANextValue = lambda2 != null && xR != null
          ? lambda2.square() - xA.getValue() - xR
          : null;
      final xANextCell = region.assignAdvice(
        doubleAndAdd.xA,
        offset + row + 1,
        () => xANextValue,
      );
      final xANext = xANextCell;

      // y_a next
      final yANext = lambda2 != null && yA != null
          ? (lambda2 * (xA.getValue() - xANext.getValue()) - yA)
          : null;

      xA = xANext;
      yA = yANext;
    }

    return (xA, yA, zs);
  }

  (
    AssignedCell<Assigned>,
    AssignedCell<Assigned>,
    List<List<AssignedCell<PallasNativeFp>>>,
  ) hashAllPieces(Region region, int offset, SinsemillaMessage message,
      AssignedCell<Assigned> xA, Assigned? yA) {
    final List<List<AssignedCell<PallasNativeFp>>> zsSum = [];

    // Hash each piece in the message
    for (var idx = 0; idx < message.messages.length; idx++) {
      final piece = message.messages[idx];
      final finalPiece = idx == message.messages.length - 1;

      // Process one message piece
      final (x, y, zs) = hashPiece(region, offset, piece, xA, yA, finalPiece);
      // Each message word consumes one row
      offset += piece.numWords;

      // Update accumulator
      xA = x;
      yA = y;
      zsSum.add(zs);
    }
    // Assign the final y_a
    final yACell = region.assignAdvice(doubleAndAdd.lambda1, offset, () => yA);
    // Assign dummy values for lambda_2 and x_p (queried but multiplied by zero)
    region.assignAdvice(
        doubleAndAdd.lambda2, offset, () => PallasNativeFp.zero());
    region.assignAdvice(doubleAndAdd.xP, offset, () => PallasNativeFp.zero());

    return (xA, yACell, zsSum);
  }

  AssignedCell<PallasNativeFp> extract(EccPoint point) {
    return point.getX();
  }
}

class CondSwapConfig {
  final Selector qSwap;
  final Column<Advice> a;
  final Column<Advice> b;
  final Column<Advice> aSwapped;
  final Column<Advice> bSwapped;
  final Column<Advice> swapColumn;

  const CondSwapConfig({
    required this.qSwap,
    required this.a,
    required this.b,
    required this.aSwapped,
    required this.bSwapped,
    required this.swapColumn,
  });
  factory CondSwapConfig.configure(
    ConstraintSystem meta,
    List<Column<Advice>> advices, // length = 5
  ) {
    final a = advices[0];

    // Only column `a` is used in an equality constraint directly by this chip.
    meta.enableEquality(a);

    final qSwap = meta.selector();

    final config = CondSwapConfig(
        qSwap: qSwap,
        a: a,
        b: advices[1],
        aSwapped: advices[2],
        bSwapped: advices[3],
        swapColumn: advices[4]);

    meta.createGate((meta) {
      final q = meta.querySelector(qSwap);

      final aCur = meta.queryAdvice(config.a, Rotation.cur());
      final bCur = meta.queryAdvice(config.b, Rotation.cur());
      final aSwapped = meta.queryAdvice(config.aSwapped, Rotation.cur());
      final bSwapped = meta.queryAdvice(config.bSwapped, Rotation.cur());
      final swap = meta.queryAdvice(config.swapColumn, Rotation.cur());

      // a' = swap ? b : a
      final aCheck = aSwapped - Halo2Utils.ternary(swap, bCur, aCur);

      // b' = swap ? a : b
      final bCheck = bSwapped - Halo2Utils.ternary(swap, aCur, bCur);

      // swap ∈ {0,1}
      final boolCheck = Halo2Utils.boolCheck(swap);

      return Constraints(
        selector: q,
        constraints: [aCheck, bCheck, boolCheck],
      );
    });

    return config;
  }
  (AssignedCell<PallasNativeFp>, AssignedCell<PallasNativeFp>) swap(
      Layouter layouter,
      (AssignedCell<PallasNativeFp>, PallasNativeFp?) pair,
      bool? swap) {
    return layouter.assignRegion(
      (Region region) {
        // Enable q_swap selector
        qSwap.enable(region: region, offset: 0);
        // Copy in `a` value
        final AssignedCell<PallasNativeFp> a =
            pair.$1.copyAdvice(region, this.a, 0);
        // Witness `b` value
        final AssignedCell<PallasNativeFp> b =
            region.assignAdvice(this.b, 0, () => pair.$2);
        // Witness `swap` value
        PallasNativeFp? swapVal;
        if (swap != null) {
          swapVal = PallasNativeFp.from(swap ? 1 : 0);
        }
        region.assignAdvice(swapColumn, 0, () => swapVal);
        PallasNativeFp? aSwappedValue;
        if (a.hasValue && b.hasValue && swap != null) {
          if (swap) {
            aSwappedValue = b.value;
          } else {
            aSwappedValue = a.value;
          }
        }
        final AssignedCell<PallasNativeFp> aSwapped =
            region.assignAdvice(this.aSwapped, 0, () => aSwappedValue);

        PallasNativeFp? bSwappedValue;
        if (a.hasValue && b.hasValue && swap != null) {
          if (swap) {
            bSwappedValue = a.value;
          } else {
            bSwappedValue = b.value;
          }
        }
        final AssignedCell<PallasNativeFp> bSwapped =
            region.assignAdvice(this.bSwapped, 0, () => bSwappedValue);

        return (aSwapped, bSwapped);
      },
    );
  }

  AssignedCell<PallasNativeFp> mux(
      Layouter layouter,
      AssignedCell<PallasNativeFp> choice,
      AssignedCell<PallasNativeFp> left,
      AssignedCell<PallasNativeFp> right) {
    return layouter.assignRegion(
      (Region region) {
        // Enable q_swap selector
        qSwap.enable(region: region, offset: 0);

        // Copy in left and right values
        final AssignedCell<PallasNativeFp> leftCell =
            left.copyAdvice(region, this.a, 0);
        final AssignedCell<PallasNativeFp> rightCell =
            right.copyAdvice(region, this.b, 0);

        // Copy in choice
        final AssignedCell<PallasNativeFp> choiceCell =
            choice.copyAdvice(region, swapColumn, 0);
        PallasNativeFp? a;
        if (leftCell.hasValue && rightCell.hasValue && choiceCell.hasValue) {
          if (choiceCell.getValue().isZero()) {
            a = leftCell.value;
          } else {
            a = rightCell.value;
          }
        }
        PallasNativeFp? b;
        if (leftCell.hasValue && rightCell.hasValue && choiceCell.hasValue) {
          if (choiceCell.getValue().isZero()) {
            b = rightCell.value;
          } else {
            b = leftCell.value;
          }
        }
        region.assignAdvice(bSwapped, 0, () => b);

        return region.assignAdvice(aSwapped, 0, () => a);
      },
    );
  }
}
