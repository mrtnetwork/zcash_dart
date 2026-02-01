import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/table.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/assigned.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/range_constrained.dart';

class LookupRangeCheckConfig {
  final Selector qLookup;
  final Selector qRunning;
  final Selector qBitshift;
  final Column<Advice> runningSum;
  final TableColumn tableIdx;

  const LookupRangeCheckConfig({
    required this.qLookup,
    required this.qRunning,
    required this.qBitshift,
    required this.runningSum,
    required this.tableIdx,
  });
  factory LookupRangeCheckConfig.configure(ConstraintSystem meta,
      Column<Advice> runningSum, TableColumn tableIdx, int k) {
    meta.enableEquality(runningSum);
    final qLookup = meta.complexSelector();
    final qRunning = meta.complexSelector();
    final qBitshift = meta.selector();

    final config = LookupRangeCheckConfig(
        qLookup: qLookup,
        qRunning: qRunning,
        qBitshift: qBitshift,
        runningSum: runningSum,
        tableIdx: tableIdx);
    final one = ExpressionConstant(PallasNativeFp.one());

    // Lookup constraints
    meta.lookup((meta) {
      final qLookupExpr = meta.querySelector(config.qLookup);
      final qRunningExpr = meta.querySelector(config.qRunning);
      final zCur = meta.queryAdvice(config.runningSum, Rotation.cur());

      // Running sum decomposition: z_i - 2^K * z_{i+1}
      final runningSumLookup = () {
        final zNext = meta.queryAdvice(config.runningSum, Rotation.next());
        final runningSumWord =
            zCur - zNext * PallasNativeFp.from(1 << HashDomainConst.K);
        return qRunningExpr * runningSumWord;
      }();

      // Short range check: word directly witnessed
      final shortLookup = () {
        final qShort = one - qRunningExpr;
        return qShort * zCur;
      }();

      return [
        (qLookupExpr * (runningSumLookup + shortLookup), config.tableIdx)
      ];
    });

    // Short lookup bitshift gate
    meta.createGate((meta) {
      final qBitshiftExpr = meta.querySelector(config.qBitshift);
      final word = meta.queryAdvice(config.runningSum, Rotation.prev());
      final shiftedWord = meta.queryAdvice(config.runningSum, Rotation.cur());
      final invTwoPowS = meta.queryAdvice(config.runningSum, Rotation.next());

      final constraint =
          word * PallasNativeFp.from(1 << HashDomainConst.K) * invTwoPowS -
              shiftedWord;

      return Constraints(selector: qBitshiftExpr, constraints: [constraint]);
    });

    return config;
  }

  void load(
      {required GeneratorTableConfig tableConfig,
      required Layouter layouter,
      required List<PallasAffineNativePoint> sinsemillaS}) {
    layouter.assignTable(
      (table) {
        for (var index = 0; index < sinsemillaS.length; index++) {
          final x = sinsemillaS[index].x;
          final y = sinsemillaS[index].y;
          table.assignCell(tableConfig.tableIdx, index,
              () => AssignedTrivial(PallasNativeFp(BigInt.from(index))));
          table.assignCell(tableConfig.tableX, index, () => AssignedTrivial(x));
          table.assignCell(tableConfig.tableY, index, () => AssignedTrivial(y));
        }
      },
    );
  }

  List<AssignedCell<PallasNativeFp>> copyCheck(
    Layouter layouter,
    AssignedCell<PallasNativeFp> element,
    int numWords,
    bool strict,
  ) {
    return layouter.assignRegion(
      (region) {
        // Copy element and initialize running sum z_0 = element
        final z0 = element.copyAdvice(region, runningSum, 0);

        // Perform range check on z_0
        return rangeCheck(region, z0, numWords, strict);
      },
    );
  }

  List<AssignedCell<PallasNativeFp>> witnessCheck(
    Layouter layouter,
    PallasNativeFp? value,
    int numWords,
    bool strict,
  ) {
    return layouter.assignRegion(
      (region) {
        final z0 = region.assignAdvice(runningSum, 0, () => value);
        return rangeCheck(region, z0, numWords, strict);
      },
    );
  }

  List<AssignedCell<PallasNativeFp>> rangeCheck(Region region,
      AssignedCell<PallasNativeFp> element, int numWords, bool strict) {
    assert(numWords * HashDomainConst.K <= PallasFPConst.capacity);
    final numBits = numWords * HashDomainConst.K;
    // Decompose the first numBits of `element` into K-bit words
    List<PallasNativeFp?> words = [];
    if (element.hasValue) {
      final bits = element.getValue().toBits().take(numBits).toList();
      words = List.generate(numWords, (i) {
        final chunk =
            bits.skip(i * HashDomainConst.K).take(HashDomainConst.K).toList();
        final wordInt = BitUtils.bitsToBigInt(chunk);
        return PallasNativeFp(wordInt);
      });
    } else {
      words = List.filled(numWords, null);
    }

    // Initialize running sum vector
    final List<AssignedCell<PallasNativeFp>> zs = [element];

    // Compute z_{i+1} = (z_i - a_i) / 2^K
    var z = element;
    final invTwoPowK =
        PallasNativeFp(BigInt.one << HashDomainConst.K).invert()!; // 1 / 2^K
    for (final i in words.indexed) {
      final idx = i.$1;
      final word = i.$2;
      // Enable lookup and running gates
      qLookup.enable(region: region, offset: idx);
      qRunning.enable(region: region, offset: idx);

      PallasNativeFp? zNextVal;
      if (z.hasValue && word != null) {
        zNextVal = (z.getValue() - word) * invTwoPowK;
      }

      z = region.assignAdvice(runningSum, idx + 1, () => zNextVal);
      zs.add(z);
    }

    // If strict, enforce final z = 0
    if (strict) {
      region.constrainConstant(
          zs.last.cell, AssignedTrivial(PallasNativeFp.zero()));
    }

    return zs;
  }

  RangeConstrainedAssigned witnessShort(
      Layouter layouter, PallasNativeFp? value, int start, int end) {
    final int numBits = end - start;

    if (numBits >= HashDomainConst.K) {
      throw Halo2Exception.operationFailed("witnessShort",
          reason: "Invalid bit number.");
    }

    // Extract the subset of bits and witness it with a short range check
    final AssignedCell<PallasNativeFp> inner = witnessShortCheck(
        layouter,
        value != null ? Halo2Utils.bitrangeSubset(value, start, end) : null,
        numBits);

    return RangeConstrainedAssigned(inner, numBits);
  }

  void shortRangeCheck(
    Region region,
    AssignedCell<PallasNativeFp> element,
    int numBits,
  ) {
    // Enable lookup for `element` at offset 0
    qLookup.enable(region: region, offset: 0);

    // Enable lookup for shifted element at offset 1
    qLookup.enable(region: region, offset: 1);

    // Enable bitshift check at offset 1
    qBitshift.enable(region: region, offset: 1);

    Assigned? shifted;
    if (element.hasValue) {
      shifted = AssignedTrivial(element.getValue()) *
          PallasNativeFp(BigInt.one << (HashDomainConst.K - numBits));
    }
    region.assignAdvice(runningSum, 1, () => shifted);

    // Assign 2^(-numBits) from a fixed column
    final invTwoPow = PallasNativeFp(BigInt.one << numBits).invert();

    region.assignAdviceFromConstant(runningSum, 2, invTwoPow);
  }

  AssignedCell<PallasNativeFp> witnessShortCheck(
      Layouter layouter, PallasNativeFp? element, int numBits) {
    if (numBits > HashDomainConst.K) {
      throw Halo2Exception.operationFailed("witnessShortCheck",
          reason: "Invalid bit length.");
    }

    return layouter.assignRegion(
      (Region region) {
        // Witness `element` at offset 0 in running_sum
        final AssignedCell<PallasNativeFp> assignedElement =
            region.assignAdvice(runningSum, 0, () => element);

        // Apply short range check
        shortRangeCheck(region, assignedElement, numBits);

        // Return the witnessed cell
        return assignedElement;
      },
    );
  }
}

class RunningSumConfig {
  final Column<Advice> z;
  final Selector qRangeCheck;
  const RunningSumConfig({required this.z, required this.qRangeCheck});
  factory RunningSumConfig.configure(
      ConstraintSystem meta, Selector qRangeCheck, Column<Advice> z) {
    meta.enableEquality(z);
    final config = RunningSumConfig(qRangeCheck: qRangeCheck, z: z);
    // https://p.z.cash/halo2-0.1:decompose-short-range
    meta.createGate((meta) {
      final q = meta.querySelector(config.qRangeCheck);
      final zCur = meta.queryAdvice(config.z, Rotation.cur());
      final zNext = meta.queryAdvice(config.z, Rotation.next());

      // z_i = 2^K * z_{i+1} + k_i
      // k_i = z_i - 2^K * z_{i+1}
      final word = zCur -
          zNext * PallasNativeFp.from(1 << Halo2Utils.fixedBaseWindowSize);

      return Constraints(
        selector: q,
        constraints: [
          Halo2Utils.rangeCheck(word, 1 << Halo2Utils.fixedBaseWindowSize)
        ],
      );
    });

    return config;
  }

  List<AssignedCell<PallasNativeFp>> witnessDecompose({
    required Region region,
    required int offset,
    required PallasNativeFp? alpha,
    required bool strict,
    required int wordNumBits,
    required int numWindows,
  }) {
    final z0 = region.assignAdvice(z, offset, () => alpha);
    return decompose(
        region: region,
        offset: offset,
        z0: z0,
        strict: strict,
        wordNumBits: wordNumBits,
        numWindows: numWindows);
  }

  List<AssignedCell<PallasNativeFp>> copyDecompose(
      Region region,
      int offset,
      AssignedCell<PallasNativeFp> alpha,
      bool strict,
      int wordNumBits,
      int numWindows) {
    final z0 = alpha.copyAdvice(region, z, offset);
    return decompose(
        region: region,
        offset: offset,
        z0: z0,
        strict: strict,
        wordNumBits: wordNumBits,
        numWindows: numWindows);
  }

  /// Decomposes `z0` into K-bit windows and computes a running sum.
  List<AssignedCell<PallasNativeFp>> decompose({
    required Region region,
    required int offset,
    required AssignedCell<PallasNativeFp> z0,
    required bool strict,
    required int wordNumBits,
    required int numWindows,
  }) {
    // Make sure we do not have more windows than allowed
    if (Halo2Utils.fixedBaseWindowSize * numWindows >=
        wordNumBits + Halo2Utils.fixedBaseWindowSize) {
      throw Halo2Exception.operationFailed("decompose",
          reason: "Too many windows for the number of bits in the word.");
    }

    // Enable selectors
    for (var idx = 0; idx < numWindows; idx++) {
      qRangeCheck.enable(region: region, offset: offset + idx);
    }
    List<int?> words = [];
    if (z0.hasValue) {
      words = Halo2Utils.decomposeWord<PallasNativeFp>(
          z0.getValue(), wordNumBits, Halo2Utils.fixedBaseWindowSize);
    } else {
      words = List.filled(numWindows, null);
    }

    // Initialize running sum vector
    final zs = [z0];
    AssignedCell<PallasNativeFp> z = z0;

    // Precompute 1 / 2^K
    final twoPowKInv =
        PallasNativeFp(BigInt.one << Halo2Utils.fixedBaseWindowSize).invert()!;

    for (var i = 0; i < words.length; i++) {
      PallasNativeFp? zNextValue;
      if (words[i] != null && z.hasValue) {
        zNextValue =
            (z.getValue() - PallasNativeFp.from(words[i]!)) * twoPowKInv;
      }
      final zNext =
          region.assignAdvice(this.z, offset + i + 1, () => zNextValue);

      z = zNext;
      zs.add(z);
    }

    if (zs.length != numWindows + 1) {
      throw Halo2Exception.operationFailed("decompose",
          reason: "Running sum length mismatch.");
    }

    if (strict) {
      // Constrain final running sum to zero
      region.constrainConstant(
          zs.last.cell, AssignedTrivial(PallasNativeFp.zero()));
    }

    return zs;
  }
}
