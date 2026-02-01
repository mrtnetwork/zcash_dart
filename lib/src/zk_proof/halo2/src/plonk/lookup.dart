import 'dart:collection';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/multiopen.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/key.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/commitment/commitment.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/domain.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/evaluator.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/params.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/transcript/transcript.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';

class LookupArgument with Equality, ProtobufEncodableMessage {
  final List<Expression> inputExpressions;
  final List<Expression> tableExpressions;
  const LookupArgument(
      {required this.inputExpressions, required this.tableExpressions});
  factory LookupArgument.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return LookupArgument(
        inputExpressions: decode
            .getListOfBytes(1)
            .map((e) => Expression.deserialize(e))
            .toList(),
        tableExpressions: decode
            .getListOfBytes(2)
            .map((e) => Expression.deserialize(e))
            .toList());
  }

  String toDebugString() =>
      "Argument { input_expressions: [${inputExpressions.map((e) => e.toDebugString()).toList().join(", ")}], table_expressions: [${tableExpressions.map((e) => e.toDebugString()).toList().join(", ")}] }";
  int requiredDegree() {
    assert(inputExpressions.length == tableExpressions.length);
    int inputDegree = 1;
    for (final expr in inputExpressions) {
      final deg = expr.degree();
      if (deg > inputDegree) {
        inputDegree = deg;
      }
    }

    int tableDegree = 1;
    for (final expr in tableExpressions) {
      final deg = expr.degree();
      if (deg > tableDegree) {
        tableDegree = deg;
      }
    }

    // In practice, because inputDegree and tableDegree are initialized to 1,
    // the second argument is always ≥ 4. This max() is kept for explicitness
    // in case initialization changes in the future.
    final computedDegree = 2 + inputDegree + tableDegree;

    return computedDegree > 4 ? computedDegree : 4;
  }

  LookupPermuted commitPermuted({
    required PlonkProvingKey pk,
    required PolyParams params,
    required EvaluationDomain domain,
    required Evaluator<LagrangeCoeff> valueEvaluator,
    required Evaluator<ExtendedLagrangeCoeff> cosetEvaluator,
    required PallasNativeFp theta,
    required List<AstLeaf> adviceValues,
    required List<AstLeaf> fixedValues,
    required List<AstLeaf> instanceValues,
    required List<AstLeaf> adviceCosets,
    required List<AstLeaf> fixedCosets,
    required List<AstLeaf> instanceCosets,
    required Halo2TranscriptWriter transcript,
  }) {
    // ---------------------------------------------------------------------------
    // Closure: compress expressions (values + cosets)
    // ---------------------------------------------------------------------------
    ({
      Ast<ExtendedLagrangeCoeff> compressedCoset,
      Polynomial<PallasNativeFp, LagrangeCoeff> compressedExpression
    }) compressExpressions(List<Expression> expressions) {
      // Evaluate expressions in VALUE domain
      final unpermutedExpressions = expressions.map((expression) {
        return expression.evaluate<Ast<LagrangeCoeff>>(
          constant: (scalar) => AstConstantTerm(scalar),
          selectorColumn: (_) => throw Halo2Exception.operationFailed(
              "compressExpressions",
              reason: "virtual selectors removed during optimization."),
          fixedColumn: (query) => AstPoly(
              fixedValues[query.columnIndex].withRotation(query.rotation)),
          adviceColumn: (query) => AstPoly(
              adviceValues[query.columnIndex].withRotation(query.rotation)),
          instanceColumn: (query) => AstPoly(
              instanceValues[query.columnIndex].withRotation(query.rotation)),
          negated: (a) => -a,
          sum: (a, b) => a + b,
          product: (a, b) => a * b,
          scaled: (a, scalar) => a * scalar,
        );
      }).toList();

      // Evaluate expressions in COSET domain
      final unpermutedCosets = expressions.map((expression) {
        return expression.evaluate<Ast<ExtendedLagrangeCoeff>>(
          constant: (scalar) => AstConstantTerm(scalar),
          selectorColumn: (_) => throw Halo2Exception.operationFailed(
              "compressExpressions",
              reason: "virtual selectors removed during optimization."),
          fixedColumn: (query) => AstPoly(
              fixedCosets[query.columnIndex].withRotation(query.rotation)),
          adviceColumn: (query) => AstPoly(
              adviceCosets[query.columnIndex].withRotation(query.rotation)),
          instanceColumn: (query) => AstPoly(
              instanceCosets[query.columnIndex].withRotation(query.rotation)),
          negated: (a) => -a,
          sum: (a, b) => a + b,
          product: (a, b) => a * b,
          scaled: (a, scalar) => a * scalar,
        );
      }).toList();

      // Compress VALUE expressions
      final Ast<LagrangeCoeff> compressedExpressionAst =
          unpermutedExpressions.fold(
              AstConstantTerm<LagrangeCoeff>(PallasNativeFp.zero()),
              (acc, expr) => (acc * theta) + expr);

      // Compress COSET expressions
      final Ast<ExtendedLagrangeCoeff> compressedCosetAst =
          unpermutedCosets.fold(
        AstConstantTerm<ExtendedLagrangeCoeff>(PallasNativeFp.zero()),
        (acc, expr) =>
            (acc * AstConstantTerm<ExtendedLagrangeCoeff>(theta)) + expr,
      );

      return (
        compressedCoset: compressedCosetAst,
        compressedExpression: valueEvaluator.evaluate(
            compressedExpressionAst, domain, LagrangeCoeffOps()),
      );
    }

    // ---------------------------------------------------------------------------
    // Compress input + table expressions
    // ---------------------------------------------------------------------------
    final inputCompressed = compressExpressions(inputExpressions);
    final tableCompressed = compressExpressions(tableExpressions);
    // ---------------------------------------------------------------------------
    // Permute compressed expressions
    // ---------------------------------------------------------------------------
    final (permutedInputExpr, permutedTableExpr) = permuteExpressionPair(
      pk,
      params,
      domain,
      inputCompressed.compressedExpression,
      tableCompressed.compressedExpression,
    );
    // ---------------------------------------------------------------------------
    // Closure: commit polynomial values
    // ---------------------------------------------------------------------------
    ({
      Polynomial<PallasNativeFp, Coeff> poly,
      PallasNativeFp blind,
      VestaAffineNativePoint commitment
    }) commitValues(Polynomial<PallasNativeFp, LagrangeCoeff> values) {
      final poly = pk.vk.domain.lagrangeToCoeff(values.clone());
      final blind = PallasNativeFp.random();
      final commitment = params.commitLagrange(values, blind).toAffine();
      return (poly: poly, blind: blind, commitment: commitment);
    }

    // Commit permuted input
    final inputCommit = commitValues(permutedInputExpr);

    // Commit permuted table
    final tableCommit = commitValues(permutedTableExpr);

    // ---------------------------------------------------------------------------
    // Halo2Transcript
    // ---------------------------------------------------------------------------
    transcript.writePoint(inputCommit.commitment);
    transcript.writePoint(tableCommit.commitment);
    // ---------------------------------------------------------------------------
    // Register permuted cosets
    // ---------------------------------------------------------------------------
    final permutedInputCoset = cosetEvaluator.registerPoly(
      pk.vk.domain.coeffToExtended(inputCommit.poly.clone()),
    );

    final permutedTableCoset = cosetEvaluator.registerPoly(
      pk.vk.domain.coeffToExtended(tableCommit.poly.clone()),
    );

    // ---------------------------------------------------------------------------
    // Output
    // ---------------------------------------------------------------------------
    return LookupPermuted(
      compressedInputExpression: inputCompressed.compressedExpression,
      compressedInputCoset: inputCompressed.compressedCoset,
      permutedInputExpression: permutedInputExpr,
      permutedInputPoly: inputCommit.poly,
      permutedInputCoset: permutedInputCoset,
      permutedInputBlind: inputCommit.blind,
      compressedTableExpression: tableCompressed.compressedExpression,
      compressedTableCoset: tableCompressed.compressedCoset,
      permutedTableExpression: permutedTableExpr,
      permutedTablePoly: tableCommit.poly,
      permutedTableCoset: permutedTableCoset,
      permutedTableBlind: tableCommit.blind,
    );
  }

  static (
    Polynomial<PallasNativeFp, LagrangeCoeff>,
    Polynomial<PallasNativeFp, LagrangeCoeff>
  ) permuteExpressionPair(
    PlonkProvingKey pk,
    PolyParams params,
    EvaluationDomain domain,
    Polynomial<PallasNativeFp, LagrangeCoeff> inputExpression,
    Polynomial<PallasNativeFp, LagrangeCoeff> tableExpression,
  ) {
    final blindingFactors = pk.vk.cs.blindingFactors();

    final usableRows = params.n - (blindingFactors + 1);

    // ---------------------------------------------------------------------------
    // LookupPermuted input expression (truncate + sort)
    // ---------------------------------------------------------------------------
    final permutedInput = List<PallasNativeFp>.from(inputExpression.values)
        .sublist(0, usableRows);
    permutedInput.sort(); // relies on field element ordering
    // ---------------------------------------------------------------------------
    // Build leftover table multiset
    // ---------------------------------------------------------------------------
    final leftoverTableMap = SplayTreeMap<PallasNativeFp, int>(
      (a, b) => a.compareTo(b),
    );

    for (var i = 0; i < usableRows; i++) {
      final coeff = tableExpression.values[i];
      leftoverTableMap[coeff] = (leftoverTableMap[coeff] ?? 0) + 1;
    }

    final permutedTable = List<PallasNativeFp>.filled(
        usableRows, PallasNativeFp.zero(),
        growable: true);

    // ---------------------------------------------------------------------------
    // Track rows with repeated input values
    // ---------------------------------------------------------------------------
    final List<int> repeatedInputRows = [];

    for (var row = 0; row < usableRows; row++) {
      final inputValue = permutedInput[row];

      // First occurrence of this value
      if (row == 0 || inputValue != permutedInput[row - 1]) {
        permutedTable[row] = inputValue;

        final count = leftoverTableMap[inputValue];
        if (count == null || count == 0) {
          throw Halo2Exception.operationFailed("permuteExpressionPair",
              reason: "Constraint system failure.");
        }
        assert(count > 0);
        if (count == 1) {
          leftoverTableMap.remove(inputValue);
        } else {
          leftoverTableMap[inputValue] = count - 1;
        }
      } else {
        repeatedInputRows.add(row);
      }
    }
    // ---------------------------------------------------------------------------
    // Fill repeated rows using leftover table values
    // ---------------------------------------------------------------------------
    for (final entry in leftoverTableMap.entries) {
      final coeff = entry.key;
      final count = entry.value;

      for (var i = 0; i < count; i++) {
        if (repeatedInputRows.isEmpty) {
          throw Halo2Exception.operationFailed("permuteExpressionPair",
              reason: "Constraint system failure.");
        }
        final row = repeatedInputRows.removeLast();
        permutedTable[row] = coeff;
      }
    }

    if (repeatedInputRows.isNotEmpty) {
      throw Halo2Exception.operationFailed("permuteExpressionPair",
          reason: "Constraint system failure.");
    }

    // ---------------------------------------------------------------------------
    // AstAdd blinding factors
    // ---------------------------------------------------------------------------
    for (var i = 0; i < blindingFactors + 1; i++) {
      permutedInput.add(PallasNativeFp.random());
    }
    for (var i = 0; i < blindingFactors + 1; i++) {
      permutedTable.add(PallasNativeFp.random());
    }
    assert(permutedInput.length == params.n);
    assert(permutedTable.length == params.n);

    // ---------------------------------------------------------------------------
    // Convert back to Lagrange polynomials
    // ---------------------------------------------------------------------------
    return (
      domain.lagrangeFromVec(permutedInput),
      domain.lagrangeFromVec(permutedTable)
    );
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.repeated(
            fieldNumber: 1, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 2, elementType: ProtoFieldType.message),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [inputExpressions, tableExpressions];

  @override
  List<dynamic> get variables => [inputExpressions, tableExpressions];

  LookPermutationCommitments readPermutedCommitments(
      Halo2TranscriptRead transcript) {
    return LookPermutationCommitments(
        transcript.readPoint(), transcript.readPoint());
  }
}

class LookupPermuted {
  // ---------------------------------------------------------------------------
  // Input side
  // ---------------------------------------------------------------------------

  /// Compressed input expression (Lagrange domain)
  final Polynomial<PallasNativeFp, LagrangeCoeff> compressedInputExpression;

  /// LookupPermuted input expression (Lagrange domain)
  final Polynomial<PallasNativeFp, LagrangeCoeff> permutedInputExpression;

  /// Compressed input expression (extended coset AST)
  final Ast<ExtendedLagrangeCoeff> compressedInputCoset;

  /// LookupPermuted input polynomial (coefficient domain)
  final Polynomial<PallasNativeFp, Coeff> permutedInputPoly;

  /// LookupPermuted input coset registered in evaluator
  final AstLeaf permutedInputCoset;

  /// Blinding factor used for input commitment
  final PallasNativeFp permutedInputBlind;

  // ---------------------------------------------------------------------------
  // Table side
  // ---------------------------------------------------------------------------

  /// Compressed table expression (Lagrange domain)
  final Polynomial<PallasNativeFp, LagrangeCoeff> compressedTableExpression;

  /// Compressed table expression (extended coset AST)
  final Ast<ExtendedLagrangeCoeff> compressedTableCoset;

  /// LookupPermuted table expression (Lagrange domain)
  final Polynomial<PallasNativeFp, LagrangeCoeff> permutedTableExpression;

  /// LookupPermuted table polynomial (coefficient domain)
  final Polynomial<PallasNativeFp, Coeff> permutedTablePoly;

  /// LookupPermuted table coset registered in evaluator
  final AstLeaf permutedTableCoset;

  /// Blinding factor used for table commitment
  final PallasNativeFp permutedTableBlind;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  const LookupPermuted({
    required this.compressedInputExpression,
    required this.permutedInputExpression,
    required this.compressedInputCoset,
    required this.permutedInputPoly,
    required this.permutedInputCoset,
    required this.permutedInputBlind,
    required this.compressedTableExpression,
    required this.compressedTableCoset,
    required this.permutedTableExpression,
    required this.permutedTablePoly,
    required this.permutedTableCoset,
    required this.permutedTableBlind,
  });

  LookupCommitted commitProduct({
    required PlonkProvingKey pk,
    required PolyParams params,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required Evaluator<ExtendedLagrangeCoeff> evaluator,
    required Halo2TranscriptWriter transcript,
  }) {
    final blindingFactors = pk.vk.cs.blindingFactors();

    // Initialize denominator product
    final List<PallasNativeFp> lookupProduct = [];

    // Compute denominators using permuted input and table expressions
    for (var start = 0; start < params.n; start++) {
      final permutedInputValue = permutedInputExpression.values[start];
      final permutedTableValue = permutedTableExpression.values[start];
      lookupProduct
          .add((beta + permutedInputValue) * (gamma + permutedTableValue));
    }

    // Batch invert denominators
    Halo2Utils.batchInvert(lookupProduct);

    // Multiply by numerators (compressed expressions)
    for (var start = 0; start < params.n; start++) {
      final inputTerm = compressedInputExpression.values[start];
      final tableTerm = compressedTableExpression.values[start];
      lookupProduct[start] *= (inputTerm + beta) * (tableTerm + gamma);
    }

    // Compute cumulative product z[0..n-blindingFactors] and add random blinding factors
    final List<PallasNativeFp> zList = [];
    PallasNativeFp state = PallasNativeFp.one();
    zList.add(PallasNativeFp.one()); // z[0] = 1
    for (var cur in lookupProduct) {
      state *= cur;
      zList.add(state);
    }

    // Truncate to usable rows and add blinding factors
    final usableLength = params.n - blindingFactors;
    final zFinal = [
      ...zList.take(usableLength),
      for (var i = 0; i < blindingFactors; i++) PallasNativeFp.random(),
    ];

    // Convert to polynomial in Lagrange basis
    final z = pk.vk.domain.lagrangeFromVec(zFinal);

    // Commit with blind
    final productBlind = PallasNativeFp.random();
    final productCommitment = params.commitLagrange(z, productBlind).toAffine();

    // Convert to coefficient basis and register coset
    final zCoeff = pk.vk.domain.lagrangeToCoeff(z);
    final productCoset =
        evaluator.registerPoly(pk.vk.domain.coeffToExtended(zCoeff.clone()));

    // Hash the commitment
    transcript.writePoint(productCommitment);

    return LookupCommitted(
        permuted: this,
        productPoly: zCoeff,
        productCoset: productCoset,
        productBlind: productBlind);
  }
}

class LookupEvaluated {
  final LookupConstructed constructed;
  const LookupEvaluated(this.constructed);
  List<ProverQuery> open(PlonkProvingKey pk, PallasNativeFp x) {
    final List<ProverQuery> queries = [];

    final xInv = pk.vk.domain.rotateOmega(x, Rotation.prev());
    final xNext = pk.vk.domain.rotateOmega(x, Rotation.next());

    // Open lookup product commitments at x
    queries.add(
      ProverQuery(
          point: x,
          poly: constructed.productPoly,
          blind: constructed.productBlind),
    );

    // Open lookup input commitments at x
    queries.add(
      ProverQuery(
          point: x,
          poly: constructed.permutedInputPoly,
          blind: constructed.permutedInputBlind),
    );

    // Open lookup table commitments at x
    queries.add(
      ProverQuery(
          point: x,
          poly: constructed.permutedTablePoly,
          blind: constructed.permutedTableBlind),
    );

    // Open lookup input commitments at x_inv
    queries.add(
      ProverQuery(
        point: xInv,
        poly: constructed.permutedInputPoly,
        blind: constructed.permutedInputBlind,
      ),
    );

    // Open lookup product commitments at x_next
    queries.add(
      ProverQuery(
        point: xNext,
        poly: constructed.productPoly,
        blind: constructed.productBlind,
      ),
    );

    return queries;
  }
}

class LookupConstructed {
  final Polynomial<PallasNativeFp, Coeff> permutedInputPoly;
  final PallasNativeFp permutedInputBlind;
  final Polynomial<PallasNativeFp, Coeff> permutedTablePoly;
  final PallasNativeFp permutedTableBlind;
  final Polynomial<PallasNativeFp, Coeff> productPoly;
  final PallasNativeFp productBlind;

  const LookupConstructed({
    required this.permutedInputPoly,
    required this.permutedInputBlind,
    required this.permutedTablePoly,
    required this.permutedTableBlind,
    required this.productPoly,
    required this.productBlind,
  });
  LookupEvaluated evaluate(
      PlonkProvingKey pk, PallasNativeFp x, Halo2TranscriptWriter transcript) {
    final domain = pk.vk.domain;
    final xInv = domain.rotateOmega(x, Rotation.prev());
    final xNext = domain.rotateOmega(x, Rotation.next());

    final productEval = Halo2Utils.evalPolynomial(productPoly.values, x);
    final productNextEval =
        Halo2Utils.evalPolynomial(productPoly.values, xNext);
    final permutedInputEval =
        Halo2Utils.evalPolynomial(permutedInputPoly.values, x);
    final permutedInputInvEval =
        Halo2Utils.evalPolynomial(permutedInputPoly.values, xInv);
    final permutedTableEval =
        Halo2Utils.evalPolynomial(permutedTablePoly.values, x);
    void write(PallasNativeFp scalar) {
      transcript.writeScalar(scalar);
    }

    write(productEval);
    write(productNextEval);
    write(permutedInputEval);
    write(permutedInputInvEval);
    write(permutedTableEval);
    return LookupEvaluated(this);
  }
}

class LookupCommitted {
  final LookupPermuted permuted;
  final Polynomial<PallasNativeFp, Coeff> productPoly;
  final AstLeaf productCoset;
  final PallasNativeFp productBlind;

  const LookupCommitted({
    required this.permuted,
    required this.productPoly,
    required this.productCoset,
    required this.productBlind,
  });
  (LookupConstructed, List<Ast<ExtendedLagrangeCoeff>>) construct({
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required AstLeaf l0,
    required AstLeaf lBlind,
    required AstLeaf lLast,
  }) {
    final permuted = this.permuted;

    final activeRows = AstConstantTerm<ExtendedLagrangeCoeff>.one() -
        (AstPoly<ExtendedLagrangeCoeff>(lLast) + lBlind);
    final betaAst = AstConstantTerm<ExtendedLagrangeCoeff>(beta);
    final gammaAst = AstConstantTerm<ExtendedLagrangeCoeff>(gamma);

    Iterable<Ast<ExtendedLagrangeCoeff>> expressions() sync* {
      // l0 * (1 - z(X)) = 0
      yield (AstConstantTerm<ExtendedLagrangeCoeff>.one() - productCoset) * l0;

      // lLast * (z(X)^2 - z(X)) = 0
      yield ((AstPoly<ExtendedLagrangeCoeff>(productCoset) * productCoset) -
              productCoset) *
          lLast;

      // (1 - (lLast + lBlind)) * (z(ωX)(a'+β)(s'+γ) - z(X)(compressed_input+β)(compressed_table+γ)) = 0
      final left = AstPoly<ExtendedLagrangeCoeff>(
              productCoset.withRotation(Rotation.next())) *
          (AstPoly<ExtendedLagrangeCoeff>(permuted.permutedInputCoset) +
              betaAst) *
          (AstPoly<ExtendedLagrangeCoeff>(permuted.permutedTableCoset) +
              gammaAst);

      final right = AstPoly<ExtendedLagrangeCoeff>(productCoset) *
          (permuted.compressedInputCoset + betaAst) *
          (permuted.compressedTableCoset + gammaAst);

      yield (left - right) * activeRows;

      // l0 * (a' - s') = 0
      yield (AstPoly<ExtendedLagrangeCoeff>(permuted.permutedInputCoset) -
              permuted.permutedTableCoset) *
          l0;

      // (1 - (lLast + lBlind)) * (a' - s')(a' - a'(ω⁻¹X)) = 0
      yield (AstPoly<ExtendedLagrangeCoeff>(permuted.permutedInputCoset) -
              permuted.permutedTableCoset) *
          (AstPoly<ExtendedLagrangeCoeff>(permuted.permutedInputCoset) -
              permuted.permutedInputCoset.withRotation(Rotation.prev())) *
          activeRows;
    }

    return (
      LookupConstructed(
          permutedInputPoly: permuted.permutedInputPoly,
          permutedInputBlind: permuted.permutedInputBlind,
          permutedTablePoly: permuted.permutedTablePoly,
          permutedTableBlind: permuted.permutedTableBlind,
          productPoly: productPoly,
          productBlind: productBlind),
      expressions().toList()
    );
  }
}

class LookPermutationCommitments {
  final VestaAffineNativePoint inputCommitment;
  final VestaAffineNativePoint tableCommitment;
  const LookPermutationCommitments(this.inputCommitment, this.tableCommitment);

  LookupVerifyCommitted readProductCommitment(Halo2TranscriptRead transcript) {
    return LookupVerifyCommitted(transcript.readPoint(), this);
  }
}

class LookupVerifyCommitted {
  final LookPermutationCommitments permuted;
  final VestaAffineNativePoint commitment;
  const LookupVerifyCommitted(this.commitment, this.permuted);
  LookupVerifyEvaluated evaluate(Halo2TranscriptRead transcript) {
    return LookupVerifyEvaluated(
      committed: this,
      eval: transcript.readScalar(),
      nextEval: transcript.readScalar(),
      inputEval: transcript.readScalar(),
      inputInvEval: transcript.readScalar(),
      tableEval: transcript.readScalar(),
    );
  }
}

class LookupVerifyEvaluated {
  final LookupVerifyCommitted committed;
  final PallasNativeFp eval;
  final PallasNativeFp nextEval;
  final PallasNativeFp inputEval;
  final PallasNativeFp inputInvEval;
  final PallasNativeFp tableEval;
  const LookupVerifyEvaluated(
      {required this.committed,
      required this.eval,
      required this.nextEval,
      required this.inputEval,
      required this.inputInvEval,
      required this.tableEval});
  Iterable<PallasNativeFp> expressions({
    required PallasNativeFp l0,
    required PallasNativeFp lLast,
    required PallasNativeFp lBlind,
    required LookupArgument argument,
    required PallasNativeFp theta,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required List<PallasNativeFp> adviceEvals,
    required List<PallasNativeFp> fixedEvals,
    required List<PallasNativeFp> instanceEvals,
  }) sync* {
    final activeRows = PallasNativeFp.one() - (lLast + lBlind);

    PallasNativeFp compressExpressions(List<Expression> expressions) {
      PallasNativeFp acc = PallasNativeFp.zero();
      for (final expr in expressions) {
        final eval = expr.evaluate<PallasNativeFp>(
            constant: (s) => s,
            selectorColumn: (_) => throw Halo2Exception.operationFailed(
                "compressExpressions",
                reason: "virtual selectors are removed during optimization"),
            fixedColumn: (q) => fixedEvals[q.index],
            adviceColumn: (q) => adviceEvals[q.index],
            instanceColumn: (q) => instanceEvals[q.index],
            negated: (a) => -a,
            sum: (a, b) => a + b,
            product: (a, b) => a * b,
            scaled: (a, s) => a * s);
        acc = acc * theta + eval;
      }
      return acc;
    }

    // l_0(X) * (1 - z(X)) = 0
    yield l0 * (PallasNativeFp.one() - eval);

    // l_last(X) * (z(X)^2 - z(X)) = 0
    yield lLast * (eval.square() - eval);

    // (1 - (l_last + l_blind)) * product argument = 0
    {
      final left = nextEval * (inputEval + beta) * (tableEval + gamma);

      final right = eval *
          (compressExpressions(argument.inputExpressions) + beta) *
          (compressExpressions(argument.tableExpressions) + gamma);

      yield (left - right) * activeRows;
    }

    // l_0(X) * (a'(X) - s'(X)) = 0
    yield l0 * (inputEval - tableEval);

    // (1 - (l_last + l_blind)) * (a' - s') * (a' - a'(ω⁻¹X)) = 0
    yield (inputEval - tableEval) * (inputEval - inputInvEval) * activeRows;
  }

  List<VerifierQuery> queries(
    PlonkVerifyingKey vk,
    PallasNativeFp x,
  ) {
    final xInv = vk.domain.rotateOmega(x, Rotation.prev());
    final xNext = vk.domain.rotateOmega(x, Rotation.next());

    return [
      // Open lookup product commitment at x
      VerifierQuery(
          commitment: CommitmentReferenceCommitment(committed.commitment),
          point: x,
          eval: eval),

      // Open lookup input commitment at x
      VerifierQuery(
          commitment:
              CommitmentReferenceCommitment(committed.permuted.inputCommitment),
          point: x,
          eval: inputEval),

      // Open lookup table commitment at x
      VerifierQuery(
          commitment:
              CommitmentReferenceCommitment(committed.permuted.tableCommitment),
          point: x,
          eval: tableEval),

      // Open lookup input commitment at ω⁻¹x
      VerifierQuery(
          commitment:
              CommitmentReferenceCommitment(committed.permuted.inputCommitment),
          point: xInv,
          eval: inputInvEval),

      // Open lookup product commitment at ωx
      VerifierQuery(
          commitment: CommitmentReferenceCommitment(committed.commitment),
          point: xNext,
          eval: nextEval),
    ];
  }
}
