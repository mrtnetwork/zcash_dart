import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/domain.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/multiopen.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/key.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/commitment/commitment.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/evaluator.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/params.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/transcript/transcript.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

class PermutationAssembly {
  final List<Column<Any>> columns;
  final List<List<(int, int)>> mapping;
  final List<List<(int, int)>> aux;
  final List<List<int>> sizes;
  const PermutationAssembly(
      {required this.columns,
      required this.mapping,
      required this.aux,
      required this.sizes});

  /// Equivalent of Rust's `new` method.
  factory PermutationAssembly.newAssembly(int n, PermutationArgument p) {
    // Initialize the copy vector to keep track of copy constraints.
    final List<List<(int, int)>> columnsList = [];

    for (var i = 0; i < p.columns.length; i++) {
      // Compute [(i, 0), (i, 1), ..., (i, n-1)]
      final column = List.generate(n, (j) => (i, j));
      columnsList.add(column);
    }

    // Before any equality constraints, every cell is in a 1-cycle.
    return PermutationAssembly(
      columns: p.getColumns(),
      mapping: columnsList,
      aux: columnsList.map((e) => e.clone()).toList(),
      sizes: List.generate(p.columns.length, (_) => List.filled(n, 1)),
    );
  }

  void copy(Column<Any> leftColumn, int leftRow, Column<Any> rightColumn,
      int rightRow) {
    // Find column indices
    final leftColIndex = columns.indexOf(leftColumn);
    if (leftColIndex == -1) {
      throw Halo2Exception.operationFailed("copy",
          reason: "Column not in permutation");
    }

    final rightColIndex = columns.indexOf(rightColumn);
    if (rightColIndex == -1) {
      throw Halo2Exception.operationFailed("copy",
          reason: "Column not in permutation");
    }

    // Bounds check
    if (leftRow >= mapping[leftColIndex].length ||
        rightRow >= mapping[rightColIndex].length) {
      throw Halo2Exception.operationFailed("copy", reason: "Bounds failure.");
    }

    // Equivalent to:
    var leftCycle = aux[leftColIndex][leftRow];
    var rightCycle = aux[rightColIndex][rightRow];

    // If both are in the same cycle, do nothing
    if (leftCycle == rightCycle) {
      return;
    }

    // Union-by-size heuristic
    if (sizes[leftCycle.$1][leftCycle.$2] <
        sizes[rightCycle.$1][rightCycle.$2]) {
      final tmp = leftCycle;
      leftCycle = rightCycle;
      rightCycle = tmp;
    }

    // Merge right cycle into left cycle
    sizes[leftCycle.$1][leftCycle.$2] += sizes[rightCycle.$1][rightCycle.$2];
    var i = rightCycle;
    while (true) {
      aux[i.$1][i.$2] = leftCycle;
      i = mapping[i.$1][i.$2];
      if (i == rightCycle) {
        break;
      }
    }

    // Swap mapping entries
    final tmp = mapping[leftColIndex][leftRow];
    mapping[leftColIndex][leftRow] = mapping[rightColIndex][rightRow];
    mapping[rightColIndex][rightRow] = tmp;
  }

  PermutationVerifyingKey buildVk(
      PolyParams params, EvaluationDomain domain, PermutationArgument p) {
    final List<PallasNativeFp> omegaPowers =
        List<PallasNativeFp>.filled(params.n, PallasNativeFp.zero());

    {
      PallasNativeFp cur = PallasNativeFp.one();
      final PallasNativeFp omega = domain.omega;
      for (int i = 0; i < params.n; i++) {
        omegaPowers[i] = cur;
        cur *= omega;
      }
    }

    // Compute [omega_powers * delta^0, ..., omega_powers * delta^m]
    final List<List<PallasNativeFp>> deltaOmega = [];

    {
      final delta = PallasNativeFp.delta();
      PallasNativeFp cur = PallasNativeFp.one();
      for (int i = 0; i < p.columns.length; i++) {
        final List<PallasNativeFp> scaled =
            List<PallasNativeFp>.from(omegaPowers);
        for (int j = 0; j < scaled.length; j++) {
          scaled[j] *= cur;
        }
        deltaOmega.add(scaled);
        cur *= delta;
      }
    }
    // Pre-compute commitments
    final List<VestaAffineNativePoint> commitments = [];

    for (int i = 0; i < p.columns.length; i++) {
      final permutationPoly = domain.emptyLagrange();

      for (int j = 0; j < permutationPoly.values.length; j++) {
        final (permutedI, permutedJ) = mapping[i][j];
        permutationPoly.values[j] = deltaOmega[permutedI][permutedJ];
      }

      // Commit to polynomial
      final commitment = params
          .commitLagrange(permutationPoly, PallasNativeFp.one())
          .toAffine();

      commitments.add(commitment);
    }
    return PermutationVerifyingKey(commitments);
  }

  PermutationProvingKey buildPk(
      PolyParams params, EvaluationDomain domain, PermutationArgument p) {
    final List<PallasNativeFp> omegaPowers = [];

    {
      PallasNativeFp cur = PallasNativeFp.one();
      final PallasNativeFp omega = domain.omega;
      for (int i = 0; i < params.n; i++) {
        omegaPowers.add(cur);
        cur *= omega;
      }
    }

    // Compute [omega_powers * delta^0, ..., omega_powers * delta^m]
    final List<List<PallasNativeFp>> deltaOmega = [];

    {
      final delta = PallasNativeFp.delta();
      PallasNativeFp cur = PallasNativeFp.one();
      for (int i = 0; i < p.columns.length; i++) {
        final List<PallasNativeFp> scaled =
            List<PallasNativeFp>.from(omegaPowers);
        for (int j = 0; j < scaled.length; j++) {
          scaled[j] *= cur;
        }

        deltaOmega.add(scaled);
        cur *= delta;
      }
    }
    // Pre-compute commitments
    final List<PolynomialScalar<LagrangeCoeff>> permutations = [];
    final List<PolynomialScalar<Coeff>> polys = [];
    final List<PolynomialScalar<ExtendedLagrangeCoeff>> cosets = [];

    for (int i = 0; i < p.columns.length; i++) {
      final permutationPoly = domain.emptyLagrange();

      for (int j = 0; j < permutationPoly.values.length; j++) {
        final (permutedI, permutedJ) = mapping[i][j];

        permutationPoly.values[j] = deltaOmega[permutedI][permutedJ];
      }
      permutations.add(permutationPoly.clone());
      final poly = domain.lagrangeToCoeff(permutationPoly);
      polys.add(poly.clone());
      cosets.add(domain.coeffToExtended(poly));
    }
    return PermutationProvingKey(
        cosets: cosets, permutations: permutations, polys: polys);
  }
}

class PermutationVerifyingKey with Equality, ProtobufEncodableMessage {
  final List<VestaAffineNativePoint> commitments;
  PermutationVerifyingKey(this.commitments);
  factory PermutationVerifyingKey.deserialize(List<int> bytes) {
    final dec = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return PermutationVerifyingKey(dec
        .getListOfBytes(1)
        .map((e) => VestaAffineNativePoint.fromBytes(e))
        .toList());
  }
  // PermutationVerifyingKey clone() =>
  //     PermutationVerifyingKey(commitments.clone());
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.repeated(
            fieldNumber: 1,
            elementType: ProtoFieldType.bytes,
            encoding: ProtoRepeatedEncoding.unpacked),
      ];
  @override
  List<Object?> get bufferValues => [
        commitments.map((e) => e.toBytes()).toList(),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  PermutationVerifyCommonEvaluated evaluate(Halo2TranscriptRead transcript) {
    return PermutationVerifyCommonEvaluated(
        transcript.readNScalars(commitments.length));
  }

  String toDebugString() =>
      "VerifyingKey { commitments: [${commitments.map((e) => "(${BytesUtils.toHexString(e.x.toBytes().reversed.toList(), prefix: "0x")}, ${BytesUtils.toHexString(e.y.toBytes().reversed.toList(), prefix: "0x")})").toList().join(", ")}] }";

  @override
  List<dynamic> get variables => [commitments];
}

class PermutationProvingKey with Equality, ProtobufEncodableMessage {
  final List<PolynomialScalar<LagrangeCoeff>> permutations;
  final List<PolynomialScalar<Coeff>> polys;
  final List<PolynomialScalar<ExtendedLagrangeCoeff>> cosets;
  PermutationProvingKey(
      {required this.permutations, required this.polys, required this.cosets});

  factory PermutationProvingKey.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return PermutationProvingKey(
      permutations: decode
          .getListOfBytes(1)
          .map((e) => PolynomialScalar<LagrangeCoeff>.deserialize(e))
          .toList(),
      polys: decode
          .getListOfBytes(2)
          .map((e) => PolynomialScalar<Coeff>.deserialize(e))
          .toList(),
      cosets: decode
          .getListOfBytes(3)
          .map((e) => PolynomialScalar<ExtendedLagrangeCoeff>.deserialize(e))
          .toList(),
    );
  }

  void evaluate(PallasNativeFp x, Halo2TranscriptWriter transcript) {
    for (final poly in polys) {
      final eval = Halo2Utils.evalPolynomial(poly.values, x);
      transcript.writeScalar(eval);
    }
  }

  List<ProverQuery> open(PallasNativeFp x) {
    return polys
        .map((e) => ProverQuery(point: x, poly: e, blind: PallasNativeFp.one()))
        .toList();
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
  List<Object?> get bufferValues => [permutations, polys, cosets];

  @override
  List<dynamic> get variables => [permutations, polys, cosets];
}

class PermutationArgument with Equality, ProtobufEncodableMessage {
  final List<Column<Any>> _columns;
  PermutationArgument({List<Column<Any>>? columns}) : _columns = columns ?? [];
  List<Column<Any>> get columns => _columns;
  factory PermutationArgument.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return PermutationArgument(
        columns: decode
            .getListOfBytes(1)
            .map((e) => Column<Any>.deserialize(e))
            .toList());
  }

  PermutationArgument clone() => PermutationArgument(columns: _columns.clone());

  void addColumn(Column<Any> column) {
    if (!_columns.contains(column)) {
      _columns.add(column);
    }
  }

  String toDebugString() =>
      "Argument { columns: [${_columns.map((e) => e.toDebugString()).toList().join(", ")}] }";
  List<Column<Any>> getColumns() => _columns.clone();

  int requiredDegree() => 3;

  PermutationCommitted commit({
    required PolyParams params,
    required PlonkProvingKey pk,
    required PermutationProvingKey pkey,
    required List<Polynomial<PallasNativeFp, LagrangeCoeff>> advice,
    required List<Polynomial<PallasNativeFp, LagrangeCoeff>> fixed,
    required List<Polynomial<PallasNativeFp, LagrangeCoeff>> instance,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required Evaluator<ExtendedLagrangeCoeff> evaluator,
    required Halo2TranscriptWriter transcript,
  }) {
    final domain = pk.vk.domain;

    // cs_degree >= 3 is required for permutation argument
    assert(pk.vk.csDegree >= 3);

    // Number of columns per permutation polynomial
    final chunkLen = pk.vk.csDegree - 2;
    final blindingFactors = pk.vk.cs.blindingFactors();

    // δ^j ω^i accumulator
    var deltaOmega = PallasNativeFp.one();

    // Last value from previous permutation set
    var lastZ = PallasNativeFp.one();

    final List<PermutationCommittedSet> sets = [];
    // CompareUtils.constantTimeBigIntEquals(a, b)
    final columnChunks = CompareUtils.chunk(columns, chunkLen);
    final permutationChunks = CompareUtils.chunk(pkey.permutations, chunkLen);

    for (var k = 0; k < columnChunks.length; k++) {
      final columns = columnChunks[k];
      final permutations = permutationChunks[k];

      // Initialize product accumulator
      final modifiedValues =
          List<PallasNativeFp>.filled(params.n, PallasNativeFp.one());

      // -----------------------------------------------------------------------
      // Compute denominators
      // -----------------------------------------------------------------------
      for (var i = 0; i < columns.length; i++) {
        final column = columns[i];
        final permutedColumn = permutations[i];

        final values = switch (column.columnType) {
          final AnyAdvice _ => advice,
          final AnyFixed _ => fixed,
          final AnyInstance _ => instance,
        };
        for (var j = 0; j < modifiedValues.length; j++) {
          final value = values[column.index].values[j];
          final permuted = permutedColumn.values[j];

          modifiedValues[j] *= beta * permuted + gamma + value;
        }
      }

      // Invert denominators
      Halo2Utils.batchInvert(modifiedValues);

      // -----------------------------------------------------------------------
      // Compute numerators
      // -----------------------------------------------------------------------
      for (final column in columns) {
        final omega = domain.omega;

        final values = switch (column.columnType) {
          final AnyAdvice _ => advice,
          final AnyFixed _ => fixed,
          final AnyInstance _ => instance,
        };
        var localDeltaOmega = deltaOmega * omega.pow(BigInt.zero);

        for (var j = 0; j < modifiedValues.length; j++) {
          final value = values[column.index].values[j];
          modifiedValues[j] *= localDeltaOmega * beta + gamma + value;
          localDeltaOmega *= omega;
        }
        deltaOmega *= PallasNativeFp.delta();
      }

      // -----------------------------------------------------------------------
      // Build permutation product polynomial z(X)
      // -----------------------------------------------------------------------
      final zValues = <PallasNativeFp>[lastZ];

      for (var row = 1; row < params.n; row++) {
        zValues.add(zValues[row - 1] * modifiedValues[row - 1]);
      }

      var z = domain.lagrangeFromVec(zValues);

      // Apply blinding
      for (var i = params.n - blindingFactors; i < params.n; i++) {
        z.values[i] = PallasNativeFp.random();
      }

      lastZ = z.values[params.n - (blindingFactors + 1)];

      final blind = PallasNativeFp.random();

      final commitmentProjective = params.commitLagrange(z, blind);
      final commitment = commitmentProjective.toAffine();

      final coeffPoly = domain.lagrangeToCoeff(z.clone());
      final coset =
          evaluator.registerPoly(domain.coeffToExtended(coeffPoly.clone()));

      transcript.writePoint(commitment);

      sets.add(
        PermutationCommittedSet(
          permutationProductPoly: coeffPoly,
          permutationProductCoset: coset,
          permutationProductBlind: blind,
        ),
      );
    }

    return PermutationCommitted(sets: sets);
  }

  PermutationVerifyCommitted readProductCommitments(
      PlonkVerifyingKey vk, Halo2TranscriptRead transcript) {
    final chunkLen = vk.csDegree - 2;
    final commitments = <VestaAffineNativePoint>[];

    // Read points for each chunk
    for (var i = 0; i < columns.length; i += chunkLen) {
      final point = transcript.readPoint();
      commitments.add(point);
    }

    return PermutationVerifyCommitted(commitments);
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.repeated(
            fieldNumber: 1,
            elementType: ProtoFieldType.message,
            encoding: ProtoRepeatedEncoding.unpacked)
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [_columns];

  @override
  List<dynamic> get variables => [_columns];
}

class PermutationCommittedSet {
  final Polynomial<PallasNativeFp, Coeff> permutationProductPoly;
  final AstLeaf permutationProductCoset;
  final PallasNativeFp permutationProductBlind;

  const PermutationCommittedSet({
    required this.permutationProductPoly,
    required this.permutationProductCoset,
    required this.permutationProductBlind,
  });
}

class PermutationEvaluated {
  final PermutationConstructed constructed;
  const PermutationEvaluated(this.constructed);
  List<ProverQuery> open(PlonkProvingKey pk, PallasNativeFp x) {
    final List<ProverQuery> queries = [];

    final blindingFactors = pk.vk.cs.blindingFactors();
    final xNext = pk.vk.domain.rotateOmega(x, Rotation.next());
    final xLast = pk.vk.domain.rotateOmega(
      x,
      Rotation(-(blindingFactors + 1)),
    );

    // For each permutation set:
    // open permutation product poly at x and omega * x
    for (var set in constructed.sets) {
      queries.add(
        ProverQuery(
          point: x,
          poly: set.permutationProductPoly,
          blind: set.permutationProductBlind,
        ),
      );

      queries.add(
        ProverQuery(
          point: xNext,
          poly: set.permutationProductPoly,
          blind: set.permutationProductBlind,
        ),
      );
    }

    // Open at omega^{last} * x for all but the last set
    // (iterate in reverse, skip first = original last)
    for (var i = constructed.sets.length - 2; i >= 0; i--) {
      final set = constructed.sets[i];

      queries.add(
        ProverQuery(
          point: xLast,
          poly: set.permutationProductPoly,
          blind: set.permutationProductBlind,
        ),
      );
    }

    return queries;
  }
}

class PermutationConstructed {
  final List<PermutationConstructedSet> sets;
  const PermutationConstructed({required this.sets});

  PermutationEvaluated evaluate(
      PlonkProvingKey pk, PallasNativeFp x, Halo2TranscriptWriter transcript) {
    final domain = pk.vk.domain;
    final blindingFactors = pk.vk.cs.blindingFactors();

    var index = 0;

    while (index < sets.length) {
      final set = sets[index];

      final permutationProductEval =
          Halo2Utils.evalPolynomial(set.permutationProductPoly.values, x);

      final permutationProductNextEval = Halo2Utils.evalPolynomial(
        set.permutationProductPoly.values,
        domain.rotateOmega(x, Rotation.next()),
      );

      // Hash permutation product evaluations
      transcript.writeScalar(permutationProductEval);
      transcript.writeScalar(permutationProductNextEval);

      // If more sets remain, chain last value to next set
      if (index < sets.length - 1) {
        final rotation = Rotation(-((blindingFactors + 1)));
        final permutationProductLastEval = Halo2Utils.evalPolynomial(
          set.permutationProductPoly.values,
          domain.rotateOmega(x, rotation),
        );

        transcript.writeScalar(permutationProductLastEval);
      }

      index++;
    }

    return PermutationEvaluated(this);
  }
}

class PermutationConstructedSet {
  final Polynomial<PallasNativeFp, Coeff> permutationProductPoly;
  final PallasNativeFp permutationProductBlind;

  const PermutationConstructedSet({
    required this.permutationProductPoly,
    required this.permutationProductBlind,
  });
}

class PermutationCommitted {
  final List<PermutationCommittedSet> sets;

  const PermutationCommitted({required this.sets});

  (PermutationConstructed, List<Ast<ExtendedLagrangeCoeff>>) construct({
    required PlonkProvingKey pk,
    required PermutationArgument p,
    required List<AstLeaf> adviceCosets,
    required List<AstLeaf> fixedCosets,
    required List<AstLeaf> instanceCosets,
    required List<AstLeaf> permutationCosets,
    required AstLeaf l0,
    required AstLeaf lBlind,
    required AstLeaf lLast,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
  }) {
    final chunkLen = pk.vk.csDegree - 2;
    final blindingFactors = pk.vk.cs.blindingFactors();
    final lastRotation = Rotation(-(blindingFactors + 1));

    final constructed = PermutationConstructed(
      sets: sets
          .map((set) => PermutationConstructedSet(
                permutationProductPoly: set.permutationProductPoly.clone(),
                permutationProductBlind: set.permutationProductBlind,
              ))
          .toList(),
    );

    // Build all AST expressions
    final List<Ast<ExtendedLagrangeCoeff>> expressions = [];

    // Enforce first set: l0 * (1 - z0)
    if (sets.isNotEmpty) {
      expressions.add((AstConstantTerm<ExtendedLagrangeCoeff>.one() -
              sets.first.permutationProductCoset) *
          l0);
    }

    // Enforce last set: lLast * (z_l^2 - z_l)
    if (sets.isNotEmpty) {
      final lastSet = sets.last;
      expressions.add(
        ((AstPoly<ExtendedLagrangeCoeff>(lastSet.permutationProductCoset) *
                    lastSet.permutationProductCoset) -
                lastSet.permutationProductCoset) *
            lLast,
      );
    }

    // Enforce sequential sets: z_i - z_{i-1} rotated
    for (var i = 1; i < sets.length; i++) {
      final set = sets[i];
      final lastSet = sets[i - 1];
      expressions.add(
        (AstPoly<ExtendedLagrangeCoeff>(set.permutationProductCoset) -
                lastSet.permutationProductCoset.withRotation(lastRotation)) *
            l0,
      );
    }
    int chunkCount(int len, int chunkLen) => (len + chunkLen - 1) ~/ chunkLen;
    final columnChunkCount = chunkCount(p.columns.length, chunkLen);
    final cosetChunkCount = chunkCount(permutationCosets.length, chunkLen);
    final setCount = sets.length;
    // zip behavior
    final loopCount = [setCount, columnChunkCount, cosetChunkCount]
        .reduce((a, b) => a < b ? a : b);

    // Enforce all sets with permutation products
    for (var chunkIndex = 0; chunkIndex < loopCount; chunkIndex++) {
      final start = chunkIndex * chunkLen;
      final endCols = (start + chunkLen).clamp(0, p.columns.length);
      final endCosets = (start + chunkLen).clamp(0, permutationCosets.length);

      final columns = p.columns.sublist(start, endCols);
      final cosets = permutationCosets.sublist(start, endCosets);
      final set = sets[chunkIndex];

      // Left-hand side
      Ast<ExtendedLagrangeCoeff> left =
          AstPoly(set.permutationProductCoset.withRotation(Rotation.next()));
      for (var j = 0; j < columns.length; j++) {
        final column = columns[j];
        final values = switch (column.columnType) {
          final AnyAdvice _ => adviceCosets[column.index],
          final AnyFixed _ => fixedCosets[column.index],
          final AnyInstance _ => instanceCosets[column.index],
        };
        left *= AstPoly<ExtendedLagrangeCoeff>(values) +
            (AstConstantTerm<ExtendedLagrangeCoeff>(beta) *
                AstPoly<ExtendedLagrangeCoeff>(cosets[j])) +
            AstConstantTerm<ExtendedLagrangeCoeff>(gamma);
      }

      // Right-hand side
      Ast<ExtendedLagrangeCoeff> right = AstPoly(set.permutationProductCoset);
      var currentDelta =
          beta * PallasNativeFp.delta().pow(BigInt.from(chunkIndex * chunkLen));
      for (var j = 0; j < columns.length; j++) {
        final column = columns[j];
        final values = switch (column.columnType) {
          final AnyAdvice _ => adviceCosets[column.index],
          final AnyFixed _ => fixedCosets[column.index],
          final AnyInstance _ => instanceCosets[column.index],
        };
        right *= AstPoly<ExtendedLagrangeCoeff>(values) +
            LinearTerm<ExtendedLagrangeCoeff>(currentDelta) +
            AstConstantTerm<ExtendedLagrangeCoeff>(gamma);
        currentDelta *= PallasNativeFp.delta();
      }

      expressions.add((left - right) *
          (AstConstantTerm<ExtendedLagrangeCoeff>.one() -
              (AstPoly<ExtendedLagrangeCoeff>(lLast) + lBlind)));
    }

    return (constructed, expressions);
  }
}

class PermutationVerifyEvaluatedSet {
  final VestaAffineNativePoint productCommitment;
  final PallasNativeFp productEval;
  final PallasNativeFp productNextEval;
  final PallasNativeFp? productLastEval;
  const PermutationVerifyEvaluatedSet(
      {required this.productCommitment,
      required this.productEval,
      required this.productNextEval,
      this.productLastEval});
}

class PermutationVerifyEvaluated {
  final List<PermutationVerifyEvaluatedSet> sets;
  const PermutationVerifyEvaluated(this.sets);

  Iterable<PallasNativeFp> expressions({
    required PlonkVerifyingKey vk,
    required PermutationArgument p,
    required PermutationVerifyCommonEvaluated common,
    required List<PallasNativeFp> adviceEvals,
    required List<PallasNativeFp> fixedEvals,
    required List<PallasNativeFp> instanceEvals,
    required PallasNativeFp l0,
    required PallasNativeFp lLast,
    required PallasNativeFp lBlind,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required PallasNativeFp x,
  }) sync* {
    final chunkLen = vk.csDegree - 2;

    // Enforce only for the first set: l0 * (1 - z0)
    if (sets.isNotEmpty) {
      yield l0 * (PallasNativeFp.one() - sets.first.productEval);
    }

    // Enforce only for the last set: lLast * (z_l^2 - z_l)
    if (sets.isNotEmpty) {
      final lastSet = sets.last;
      yield (lastSet.productEval.square() - lastSet.productEval) * lLast;
    }

    // Except for the first set, enforce l0 * (z_i - z_{i-1,last})
    for (var i = 1; i < sets.length; i++) {
      final set = sets[i];
      final prevSet = sets[i - 1];
      final prevLastEval = prevSet.productLastEval!;
      yield (set.productEval - prevLastEval) * l0;
    }

    // For all sets enforce permutation product consistency
    for (var chunkIndex = 0; chunkIndex < sets.length; chunkIndex++) {
      final set = sets[chunkIndex];
      final columns = p.columns.sublist(
          chunkIndex * chunkLen,
          (chunkIndex + 1) * chunkLen > p.columns.length
              ? p.columns.length
              : (chunkIndex + 1) * chunkLen);
      final permutationEvals = common.evals.sublist(
          chunkIndex * chunkLen,
          (chunkIndex + 1) * chunkLen > common.evals.length
              ? common.evals.length
              : (chunkIndex + 1) * chunkLen);

      // Compute left = z_i(\omega X) * product(...)
      var left = set.productNextEval;
      for (var j = 0; j < columns.length; j++) {
        final column = columns[j];
        final eval = switch (column.columnType) {
          final AnyAdvice _ => adviceEvals[vk.cs.getAnyQueryIndex(column)],
          final AnyFixed _ => fixedEvals[vk.cs.getAnyQueryIndex(column)],
          final AnyInstance _ => instanceEvals[vk.cs.getAnyQueryIndex(column)],
        };
        left *= (eval + (beta * permutationEvals[j]) + gamma);
      }

      // Compute right = z_i(X) * product(...)
      var right = set.productEval;
      var currentDelta = beta *
          x *
          PallasNativeFp.delta().pow(BigInt.from((chunkIndex * chunkLen)));
      for (final column in columns) {
        final eval = switch (column.columnType) {
          final AnyAdvice _ => adviceEvals[vk.cs.getAnyQueryIndex(column)],
          final AnyFixed _ => fixedEvals[vk.cs.getAnyQueryIndex(column)],
          final AnyInstance _ => instanceEvals[vk.cs.getAnyQueryIndex(column)],
        };
        right *= (eval + currentDelta + gamma);
        currentDelta *= PallasNativeFp.delta();
      }

      yield (left - right) * (PallasNativeFp.one() - (lLast + lBlind));
    }
  }

  List<VerifierQuery> queries(
    PlonkVerifyingKey vk,
    PallasNativeFp x,
  ) {
    final blindingFactors = vk.cs.blindingFactors();

    final xNext = vk.domain.rotateOmega(x, Rotation.next());
    final xLast = vk.domain.rotateOmega(x, Rotation(-(blindingFactors + 1)));
    final result = <VerifierQuery>[];
    for (final set in sets) {
      result.add(
        VerifierQuery(
            commitment: CommitmentReferenceCommitment(set.productCommitment),
            point: x,
            eval: set.productEval),
      );

      result.add(
        VerifierQuery(
            commitment: CommitmentReferenceCommitment(set.productCommitment),
            point: xNext,
            eval: set.productNextEval),
      );
    }
    for (int i = sets.length - 2; i >= 0; i--) {
      final set = sets[i];
      result.add(
        VerifierQuery(
            commitment: CommitmentReferenceCommitment(set.productCommitment),
            point: xLast,
            eval: set.productLastEval!),
      );
    }

    return result;
  }
}

class PermutationVerifyCommitted {
  final List<VestaAffineNativePoint> productCommitments;
  const PermutationVerifyCommitted(this.productCommitments);

  PermutationVerifyEvaluated evaluate(Halo2TranscriptRead transcript) {
    List<PermutationVerifyEvaluatedSet> sets = [];
    final iter = List<VestaAffineNativePoint>.from(productCommitments);

    while (iter.isNotEmpty) {
      final permutationProductCommitment = iter.removeAt(0);
      final permutationProductEval = transcript.readScalar();
      final permutationProductNextEval = transcript.readScalar();

      final permutationProductLastEval =
          iter.isNotEmpty ? transcript.readScalar() : null;

      sets.add(PermutationVerifyEvaluatedSet(
        productCommitment: permutationProductCommitment,
        productEval: permutationProductEval,
        productNextEval: permutationProductNextEval,
        productLastEval: permutationProductLastEval,
      ));
    }

    return PermutationVerifyEvaluated(sets);
  }
}

class PermutationVerifyCommonEvaluated {
  final List<PallasNativeFp> evals;
  const PermutationVerifyCommonEvaluated(this.evals);

  List<VerifierQuery> queries(
    PermutationVerifyingKey vkey,
    PallasNativeFp x,
  ) {
    final result = <VerifierQuery>[];

    for (int i = 0; i < vkey.commitments.length; i++) {
      result.add(VerifierQuery(
          commitment: CommitmentReferenceCommitment(vkey.commitments[i]),
          point: x,
          eval: evals[i]));
    }

    return result;
  }
}
