import 'dart:async';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/halo2.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/proof/verifier.dart';

class PlonkProver {
  final PolyParams params;
  final PlonkProvingKey provingKey;
  final OrchardCircuitConfig config;
  PlonkVerifier toVerifier() =>
      PlonkVerifier(params: params, vk: provingKey.vk.clone());
  factory PlonkProver.build(ZCashCryptoContext context,
      {PolyParams? params, PlonkProvingKey? pk, PlonkVerifyingKey? vk}) {
    final circuit = OrchardCircuit.defaultConfig();
    params ??= PolyParams.newParams(11);
    pk ??= PlonkKeyGenerator.keygenPk(
        circuit: circuit,
        context: context,
        params: params,
        vk: vk ??=
            PlonkKeyGenerator.keygenVk(circuit, k: 11, p: params, context));
    return PlonkProver(params: params, provingKey: pk, context: context);
  }

  PlonkProver(
      {required this.params,
      required this.provingKey,
      required ZCashCryptoContext context,
      OrchardCircuitConfig? config})
      : config = config ??
            OrchardCircuitConfig.configure(
                ConstraintSystem.defaultConfig(), context);

  List<int> createProof({
    required List<OrchardCircuit> circuits,
    required List<List<List<PallasNativeFp>>> instances,
  }) {
    final transcript = Halo2TranscriptWriter();
    final pk = provingKey.clone();
    final queries = buildQueriesSync(
        circuits: circuits,
        instances: instances,
        pk: pk,
        transcript: transcript);
    final open =
        multiOpenSync(queries: queries, pk: pk, transcript: transcript);
    return commitmentSync(
        poly: open.poly,
        blind: open.blind,
        x3: open.x3,
        pk: pk,
        transcript: transcript);
  }

  List<ProverQuery> buildQueriesSync({
    required List<OrchardCircuit> circuits,
    required List<List<List<PallasNativeFp>>> instances,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    pk.vk.hashInto(transcript);
    final instance = buildInstancesSync(
        circuits: circuits,
        instances: instances,
        pk: pk,
        transcript: transcript);
    final advice = buildAdviceSync(
        circuits: circuits,
        instances: instances,
        pk: pk,
        transcript: transcript);
    final leaves = AstLeaves.build(pk: pk, advice: advice, instance: instance);
    final PallasNativeFp theta = transcript.squeezeChallenge();
    final lookups = buildLookupsSync(
        leaves: leaves, theta: theta, pk: pk, transcript: transcript);
    final beta = transcript.squeezeChallenge();
    final gamma = transcript.squeezeChallenge();
    final permutations = buildPermutationsSync(
        leaves: leaves,
        beta: beta,
        gamma: gamma,
        pk: pk,
        transcript: transcript);
    final lookupsCommitted = buildLookupsCommittedSync(
        lookups: lookups,
        leaves: leaves,
        beta: beta,
        gamma: gamma,
        pk: pk,
        transcript: transcript);
    final vanishing = vanishingCommitSync(pk: pk, transcript: transcript);
    final y = transcript.squeezeChallenge();
    final permutationsAndExpressions = buildPermutationsAndExpressionsSync(
        permutations: permutations,
        leaves: leaves,
        beta: beta,
        gamma: gamma,
        pk: pk,
        transcript: transcript);
    final lookupsAndExpressions = buildLookupsAndExpressionsSync(
        lookupsCommitted: lookupsCommitted,
        leaves: leaves,
        beta: beta,
        gamma: gamma);
    final expressions = buildExpressionsSync(
        leaves: leaves,
        permutationsAndExpressions: permutationsAndExpressions,
        lookupsAndExpressions: lookupsAndExpressions,
        pk: pk,
        transcript: transcript);
    final constructedVanishing = constructVanishingSync(
        vanishing: vanishing,
        y: y,
        leaves: leaves,
        expressions: expressions,
        pk: pk,
        transcript: transcript);
    final x = transcript.squeezeChallenge();
    final evaluatedVanishing = evaluatedVanishingSync(
        leaves: leaves,
        x: x,
        vanishing: constructedVanishing,
        pk: pk,
        transcript: transcript);
    final evaluatedPermutations = evaluatePermutationsSync(
        x: x,
        permutationsAndExpressions: permutationsAndExpressions,
        pk: pk,
        transcript: transcript);
    final evaluatedLookups = evaluateLookupsSync(
        lookupsAndExpressions: lookupsAndExpressions,
        x: x,
        pk: pk,
        transcript: transcript);
    return evaluateQueriesSync(
        leaves: leaves,
        x: x,
        evaluatedPermutations: evaluatedPermutations,
        evaluatedLookups: evaluatedLookups,
        evaluatedVanishing: evaluatedVanishing,
        pk: pk,
        transcript: transcript);
  }

  List<PolyInstanceSingle> buildInstancesSync({
    required List<OrchardCircuit> circuits,
    required List<List<List<PallasNativeFp>>> instances,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return instances.map((instance) {
      final List<Polynomial<PallasNativeFp, LagrangeCoeff>> instanceValues = [];

      for (final values in instance) {
        final poly = pk.vk.domain.emptyLagrange();
        if (values.length > (poly.length - (pk.vk.cs.blindingFactors() + 1))) {
          throw Halo2Exception.operationFailed("create",
              reason: "Invalid instances length.");
        }
        for (int i = 0; i < values.length; i++) {
          poly.values[i] = values[i];
        }
        instanceValues.add(poly);
      }
      final instanceCommitments = instanceValues
          .map((poly) =>
              params.commitLagrange(poly, PallasNativeFp.one()).toAffine())
          .toList();
      for (final commitment in instanceCommitments) {
        transcript.commonPoint(commitment);
      }
      final instancePolys = instanceValues.map((poly) {
        final lagrangeVec = pk.vk.domain.lagrangeFromVec(poly.values.clone());
        return pk.vk.domain.lagrangeToCoeff(lagrangeVec);
      }).toList();
      final instanceCosets = instancePolys
          .map((poly) => pk.vk.domain.coeffToExtended(poly.clone()))
          .toList();
      return PolyInstanceSingle(
          instanceValues: instanceValues,
          instancePolys: instancePolys,
          instanceCosets: instanceCosets);
    }).toList();
  }

  List<PolyAdviceSingle> buildAdviceSync({
    required List<OrchardCircuit> circuits,
    required List<List<List<PallasNativeFp>>> instances,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return circuits.indexed.map((e) {
      final circuit = e.$2;
      final instance = instances[e.$1];

      // Compute unusable rows
      final int unusableRowsStart = params.n - (pk.vk.cs.blindingFactors() + 1);

      // Create witness collection
      final witness = PlonkWitnessCollection(
        k: params.k,
        advice: List.generate(pk.vk.cs.numAdviceColumns,
            (_) => pk.vk.domain.emptyLagrangeAssigned()),
        instances: instance,
        usableRows: ComparableIntRange(0, unusableRowsStart),
      );

      V1Plan.synthesize(
          cs: witness,
          circuit: circuit,
          config: config,
          constants: pk.vk.cs.constants.clone(),
          context: config.context);
      final adviceValues = Polynomial.batchInvertAssigned(witness.advice);
      for (var col in adviceValues) {
        for (var i = unusableRowsStart; i < col.length; i++) {
          col.values[i] = PallasNativeFp.random();
        }
      }
      final adviceBlinds =
          List.generate(adviceValues.length, (_) => PallasNativeFp.random());
      final adviceCommitmentsProjective = List.generate(adviceValues.length,
          (i) => params.commitLagrange(adviceValues[i], adviceBlinds[i]));
      final adviceCommitments =
          adviceCommitmentsProjective.map((e) => e.toAffine()).toList();
      for (var commitment in adviceCommitments) {
        transcript.writePoint(commitment);
      }
      final advicePolys = adviceValues
          .map((poly) => pk.vk.domain.lagrangeToCoeff(poly.clone()))
          .toList();
      final adviceCosets = advicePolys
          .map((poly) => pk.vk.domain.coeffToExtended(poly.clone()))
          .toList();
      return PolyAdviceSingle(
          adviceValues: adviceValues,
          advicePolys: advicePolys,
          adviceCosets: adviceCosets,
          adviceBlinds: adviceBlinds);
    }).toList();
  }

  AstLeaves buildLeavesSync({
    required List<PolyAdviceSingle> advice,
    required List<PolyInstanceSingle> instance,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return AstLeaves.build(pk: pk, advice: advice, instance: instance);
  }

  List<List<LookupPermuted>> buildLookupsSync({
    required AstLeaves leaves,
    required PallasNativeFp theta,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return leaves.instanceValues.indexed.map((e) {
      final instVals = e.$2;
      final instCosets = leaves.instanceCosets[e.$1];
      final advVals = leaves.adviceValues[e.$1];
      final advCosets = leaves.adviceCosets[e.$1];
      final List<LookupPermuted> permutedSet = pk.vk.cs.lookups.map((e) {
        return e.commitPermuted(
          pk: pk,
          params: params,
          domain: pk.vk.domain,
          valueEvaluator: leaves.valueEvaluator,
          cosetEvaluator: leaves.cosetEvaluator,
          theta: theta,
          adviceValues: advVals,
          fixedValues: leaves.fixedValues,
          instanceValues: instVals,
          adviceCosets: advCosets,
          fixedCosets: leaves.fixedCosets,
          instanceCosets: instCosets,
          transcript: transcript,
        );
      }).toList();
      return permutedSet;
    }).toList();
  }

  List<PermutationCommitted> buildPermutationsSync({
    required AstLeaves leaves,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return leaves.instance.indexed.map((e) {
      final inst = e.$2;
      final adv = leaves.advice[e.$1];
      return pk.vk.cs.permutation.commit(
        params: params,
        pk: pk,
        pkey: pk.permutation,
        advice: adv.adviceValues,
        fixed: pk.fixedValues,
        instance: inst.instanceValues,
        beta: beta,
        gamma: gamma,
        evaluator: leaves.cosetEvaluator,
        transcript: transcript,
      );
    }).toList();
  }

  List<List<LookupCommitted>> buildLookupsCommittedSync({
    required List<List<LookupPermuted>> lookups,
    required AstLeaves leaves,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return lookups.map((lookupList) {
      return lookupList.map((lookup) {
        return lookup.commitProduct(
            pk: pk,
            params: params,
            beta: beta,
            gamma: gamma,
            evaluator: leaves.cosetEvaluator,
            transcript: transcript);
      }).toList();
    }).toList();
  }

  VanishingCommitted vanishingCommitSync({
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return VanishingCommitted.commit(
        params: params, domain: pk.vk.domain, transcript: transcript);
  }

  List<(PermutationConstructed, List<Ast<ExtendedLagrangeCoeff>>)>
      buildPermutationsAndExpressionsSync({
    required List<PermutationCommitted> permutations,
    required AstLeaves leaves,
    required PallasNativeFp beta,
    required PallasNativeFp gamma,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return permutations.indexed
        .map((e) => e.$2.construct(
              pk: pk,
              p: pk.vk.cs.permutation,
              adviceCosets: leaves.adviceCosets[e.$1],
              fixedCosets: leaves.fixedCosets,
              instanceCosets: leaves.instanceCosets[e.$1],
              permutationCosets: leaves.permutationCosets,
              l0: leaves.l0,
              lBlind: leaves.lBlind,
              lLast: leaves.lLast,
              beta: beta,
              gamma: gamma,
            ))
        .toList();
  }

  List<(List<LookupConstructed>, List<List<Ast<ExtendedLagrangeCoeff>>>)>
      buildLookupsAndExpressionsSync(
          {required List<List<LookupCommitted>> lookupsCommitted,
          required AstLeaves leaves,
          required PallasNativeFp beta,
          required PallasNativeFp gamma}) {
    return lookupsCommitted.map((lookupGroup) {
      final result = lookupGroup
          .map((p) => p.construct(
              beta: beta,
              gamma: gamma,
              l0: leaves.l0,
              lBlind: leaves.lBlind,
              lLast: leaves.lLast))
          .toList();
      return (
        result.map((e) => e.$1).toList(),
        result.map((e) => e.$2).toList(),
      );
    }).toList();
  }

  List<Ast<ExtendedLagrangeCoeff>> buildExpressionsSync({
    required AstLeaves leaves,
    required List<(PermutationConstructed, List<Ast<ExtendedLagrangeCoeff>>)>
        permutationsAndExpressions,
    required List<
            (List<LookupConstructed>, List<List<Ast<ExtendedLagrangeCoeff>>>)>
        lookupsAndExpressions,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return leaves.adviceCosets.indexed
        .map((e) {
          final advice = e.$2;
          final instance = leaves.instanceCosets[e.$1];
          final permExprs = permutationsAndExpressions[e.$1].$2;
          final lookupExprs = lookupsAndExpressions[e.$1].$2;
          return pk.vk.cs.gates
              .map((g) => g.polys.map(
                    (expr) => expr.evaluate<Ast<ExtendedLagrangeCoeff>>(
                        constant: (scalar) =>
                            AstConstantTerm<ExtendedLagrangeCoeff>(scalar),
                        selectorColumn: (_) => throw Halo2Exception.operationFailed("create",
                            reason:
                                "Virtual selectors are removed during optimization."),
                        fixedColumn: (query) => AstPoly(leaves
                            .fixedCosets[query.columnIndex]
                            .withRotation(query.rotation)),
                        adviceColumn: (query) => AstPoly(advice[query.columnIndex]
                            .withRotation(query.rotation)),
                        instanceColumn: (query) =>
                            AstPoly(instance[query.columnIndex].withRotation(query.rotation)),
                        negated: (a) => -a,
                        sum: (a, b) => a + b,
                        product: (a, b) => a * b,
                        scaled: (a, scalar) => a * scalar),
                  ))
              .expand((e) => e)
              .followedBy(permExprs)
              .followedBy(lookupExprs.expand((e) => e));
        })
        .expand((e) => e)
        .toList();
  }

  List<AstContext<Basis>> buildVanishingContextSync(
      {required VanishingCommitted vanishing,
      required List<Ast<ExtendedLagrangeCoeff>> expressions,
      required PallasNativeFp y,
      required AstLeaves leaves,
      required PlonkProvingKey pk,
      required Halo2TranscriptWriter transcript,
      int numThreads = 4}) {
    return vanishing.buildContext(
        leaves.cosetEvaluator, pk.vk.domain, y, expressions,
        numThreads: numThreads);
  }

  AstContextResult buildVanishingResultSync(List<AstContext<Basis>> context) {
    return AstContextResult(
        polyLen: context[0].polyLen,
        chunkSize: context[0].chunkSize,
        numThreads: context[0].numThreads,
        values: context.map((e) => Evaluator.runRecurse(e)).toList());
  }

  VanishingConstructed constructVanishingSync({
    required VanishingCommitted vanishing,
    required PallasNativeFp y,
    required AstLeaves leaves,
    required List<Ast<ExtendedLagrangeCoeff>> expressions,
    AstContextResult? result,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return vanishing.construct(
        params, pk.vk.domain, leaves.cosetEvaluator, expressions, y, transcript,
        result: result);
  }

  VanishingEvaluated evaluatedVanishingSync({
    required AstLeaves leaves,
    required PallasNativeFp x,
    required VanishingConstructed vanishing,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    final meta = pk.vk.cs;
    final domain = pk.vk.domain;

    final xn = x.pow(BigInt.from(params.n));
    for (var inst in leaves.instance) {
      for (var q in meta.instanceQueries) {
        final column = q.column;
        final at = q.rotation;

        final eval = Halo2Utils.evalPolynomial(
            inst.instancePolys[column.index].values, domain.rotateOmega(x, at));
        transcript.writeScalar(eval);
      }
    }
    for (var adv in leaves.advice) {
      for (var q in meta.adviceQueries) {
        final column = q.column;
        final at = q.rotation;

        final eval = Halo2Utils.evalPolynomial(
          adv.advicePolys[column.index].values,
          domain.rotateOmega(x, at),
        );
        transcript.writeScalar(eval);
      }
    }
    for (var q in meta.fixedQueries) {
      final column = q.column;
      final at = q.rotation;

      final eval = Halo2Utils.evalPolynomial(
          pk.fixedPolys[column.index].values, domain.rotateOmega(x, at));
      transcript.writeScalar(eval);
    }
    return vanishing.evaluate(x, xn, domain, transcript);
  }

  List<PermutationEvaluated> evaluatePermutationsSync({
    required PallasNativeFp x,
    required List<(PermutationConstructed, List<Ast<ExtendedLagrangeCoeff>>)>
        permutationsAndExpressions,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    pk.permutation.evaluate(x, transcript);
    return permutationsAndExpressions
        .map((e) => e.$1.evaluate(pk, x, transcript))
        .toList();
  }

  List<List<LookupEvaluated>> evaluateLookupsSync({
    required List<
            (List<LookupConstructed>, List<List<Ast<ExtendedLagrangeCoeff>>>)>
        lookupsAndExpressions,
    required PallasNativeFp x,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    return lookupsAndExpressions
        .map((e) => e.$1.map((e) => e.evaluate(pk, x, transcript)).toList())
        .toList();
  }

  List<ProverQuery> evaluateQueriesSync({
    required AstLeaves leaves,
    required PallasNativeFp x,
    required List<PermutationEvaluated> evaluatedPermutations,
    required List<List<LookupEvaluated>> evaluatedLookups,
    required VanishingEvaluated evaluatedVanishing,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    final List<ProverQuery> proverQueries = <ProverQuery>[];

    for (var i = 0; i < leaves.instance.length; i++) {
      final inst = leaves.instance[i];
      final adv = leaves.advice[i];
      final perm = evaluatedPermutations[i];
      final lookupSet = evaluatedLookups[i];

      // Instance queries
      for (var q in pk.vk.cs.instanceQueries) {
        proverQueries.add(
          ProverQuery(
            point: pk.vk.domain.rotateOmega(x, q.rotation),
            poly: inst.instancePolys[q.column.index],
            blind: PallasNativeFp.one(),
          ),
        );
      }

      // Advice queries
      for (var q in pk.vk.cs.adviceQueries) {
        proverQueries.add(
          ProverQuery(
            point: pk.vk.domain.rotateOmega(x, q.rotation),
            poly: adv.advicePolys[q.column.index],
            blind: adv.adviceBlinds[q.column.index],
          ),
        );
      }

      // Permutation queries
      proverQueries.addAll(perm.open(pk, x));

      // Lookup queries
      for (var p in lookupSet) {
        proverQueries.addAll(p.open(pk, x));
      }
    }
    // Fixed queries (shared across instances)
    for (var q in pk.vk.cs.fixedQueries) {
      proverQueries.add(
        ProverQuery(
          point: pk.vk.domain.rotateOmega(x, q.rotation),
          poly: pk.fixedPolys[q.column.index],
          blind: PallasNativeFp.one(),
        ),
      );
    }
    proverQueries.addAll(pk.permutation.open(x));
    proverQueries.addAll(evaluatedVanishing.open(x));
    return proverQueries;
  }

  ({
    Polynomial<PallasNativeFp, Coeff> poly,
    PallasNativeFp blind,
    PallasNativeFp x3
  }) multiOpenSync({
    required List<ProverQuery> queries,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    final x1 = transcript.squeezeChallenge();
    final x2 = transcript.squeezeChallenge();
    final intermediateSets = PolyMultiopen.constructIntermediateSets<
        PolynomialPointer, PallasNativeFp?>(queries);
    if (intermediateSets == null) {
      throw Halo2Exception.operationFailed("createProof",
          reason: "Queries iterator contains mismatching evaluations.");
    }

    final polyMap = intermediateSets.$1;
    final pointSets = intermediateSets.$2;

// Collapse openings at same point sets into single openings
    final qPolys =
        List<Polynomial<PallasNativeFp, Coeff>?>.filled(pointSets.length, null);
    final qBlinds =
        List<PallasNativeFp>.filled(pointSets.length, PallasNativeFp.zero());

    void accumulate(int setIdx, Polynomial<PallasNativeFp, Coeff> newPoly,
        PallasNativeFp blind) {
      if (qPolys[setIdx] != null) {
        // qPolys[setIdx] = qPolys[setIdx] * x1 + newPoly
        final existing = qPolys[setIdx]!;
        qPolys[setIdx] = Polynomial(
          List.generate(existing.values.length,
              (i) => existing.values[i] * x1 + newPoly.values[i]),
        );
      } else {
        qPolys[setIdx] = Polynomial(List.from(newPoly.values));
      }

      // Accumulate blind
      qBlinds[setIdx] = qBlinds[setIdx] * x1 + blind;
    }

// Fold all commitment polynomials into their sets
    for (var commitmentData in polyMap) {
      accumulate(commitmentData.setIndex, commitmentData.commitment.poly,
          commitmentData.commitment.blind);
    }

// Compute q_prime_poly via Kate-style division over all point sets
    Polynomial<PallasNativeFp, Coeff>? qPrimePoly;

    for (var i = 0; i < pointSets.length; i++) {
      final points = pointSets[i];
      var poly = List<PallasNativeFp>.from(qPolys[i]!.values);

      for (final point in points) {
        poly = Halo2Utils.kateDivision(poly, point);
      }

      // Resize poly to domain size (assume params.n)
      while (poly.length < params.n) {
        poly.add(PallasNativeFp.zero());
      }

      final polyObj = Polynomial<PallasNativeFp, Coeff>(poly);

      if (qPrimePoly == null) {
        qPrimePoly = polyObj;
      } else {
        final old = qPrimePoly;
        qPrimePoly = Polynomial(List.generate(
            old.values.length, (j) => old.values[j] * x2 + polyObj.values[j]));
      }
    }

// Random blind for q_prime
    final qPrimeBlind = PallasNativeFp.random();
    final qPrimeCommitment = params.commit(qPrimePoly!, qPrimeBlind).toAffine();

    transcript.writePoint(qPrimeCommitment);

// Challenge X3 for evaluation of each Q_i at x3
    final x3 = transcript.squeezeChallenge();
    for (final qPoly in qPolys) {
      final eval = Halo2Utils.evalPolynomial(qPoly!.values, x3);
      transcript.writeScalar(eval);
    }

// Challenge X4 for final folding
    final x4 = transcript.squeezeChallenge();
    Polynomial<PallasNativeFp, Coeff> pPoly = qPrimePoly;
    PallasNativeFp pPolyBlind = qPrimeBlind;

    for (int i = 0; i < qPolys.length; i++) {
      final poly = qPolys[i]!;
      final blind = qBlinds[i];

      pPoly = Polynomial(List.generate(
          pPoly.values.length, (j) => pPoly.values[j] * x4 + poly.values[j]));
      pPolyBlind = pPolyBlind * x4 + blind;
    }
    return (poly: pPoly, blind: pPolyBlind, x3: x3);
  }

  List<int> commitmentSync({
    required Polynomial<PallasNativeFp, Coeff> poly,
    required PallasNativeFp blind,
    required PallasNativeFp x3,
    required PlonkProvingKey pk,
    required Halo2TranscriptWriter transcript,
  }) {
    if (poly.values.length != params.n) {
      throw ArgumentException.invalidOperationArguments("createProof",
          reason: "Invalid poly length.");
    }

    // Sample a random polynomial sPoly of the same degree with root at x3
    final sPoly = poly.clone(); // copy
    for (int i = 0; i < sPoly.values.length; i++) {
      sPoly.values[i] = PallasNativeFp.random();
    }
    final sAtX3 = Halo2Utils.evalPolynomial(sPoly.values, x3);
    sPoly.values[0] = sPoly.values[0] - sAtX3;

    final sBlind = PallasNativeFp.random();

    // Write sPoly commitment to transcript
    final sCommitment = params.commit(sPoly, sBlind).toAffine();
    transcript.writePoint(sCommitment);

    // Challenge xi
    final xi = transcript.squeezeChallenge();

    // Challenge z
    final z = transcript.squeezeChallenge();

    // Compute P' = P + ξ * S
    final pPrimePoly = Polynomial<PallasNativeFp, Basis>(List.generate(
        poly.values.length, (i) => poly.values[i] + sPoly.values[i] * xi));
    final v = Halo2Utils.evalPolynomial(pPrimePoly.values, x3);
    pPrimePoly.values[0] = pPrimePoly.values[0] - v;
    final pPrimeBlind = sBlind * xi + blind;

    // Synthetic blinding factor f
    PallasNativeFp f = pPrimeBlind;

    // Initialize vectors for inner product
    var pPrime = List<PallasNativeFp>.from(pPrimePoly.values);
    var b = List<PallasNativeFp>.filled(1 << params.k, PallasNativeFp.zero(),
        growable: true);
    {
      var cur = PallasNativeFp.one();
      for (int i = 0; i < b.length; i++) {
        b[i] = cur;
        cur *= x3;
      }
    }

    var gPrime = List<VestaAffineNativePoint>.from(params.g); // clone

    for (int j = 0; j < params.k; j++) {
      final expectedLen = 1 << (params.k - j);
      assert(pPrime.length == expectedLen);
      assert(b.length == expectedLen);
      assert(gPrime.length == expectedLen);

      final half = expectedLen >> 1;

      final lJ = Halo2Utils.bestMultiexp(
        pPrime.sublist(half, expectedLen),
        gPrime.sublist(0, half),
      );

      final rJ = Halo2Utils.bestMultiexp(
        pPrime.sublist(0, half),
        gPrime.sublist(half, expectedLen),
      );

      final valueLJ = Halo2Utils.computeInnerProduct(
        pPrime.sublist(half, expectedLen),
        b.sublist(0, half),
      );

      final valueRJ = Halo2Utils.computeInnerProduct(
        pPrime.sublist(0, half),
        b.sublist(half, expectedLen),
      );

      final lJRandomness = PallasNativeFp.random();
      final rJRandomness = PallasNativeFp.random();

      final lJFinal = lJ +
          Halo2Utils.bestMultiexp(
            [valueLJ * z, lJRandomness],
            [params.u, params.w],
          );

      final rJFinal = rJ +
          Halo2Utils.bestMultiexp(
            [valueRJ * z, rJRandomness],
            [params.u, params.w],
          );

      transcript.writePoint(lJFinal.toAffine());
      transcript.writePoint(rJFinal.toAffine());

      final uJ = transcript.squeezeChallenge();
      final uJInv = uJ.invert();
      if (uJInv == null) {
        throw Halo2Exception.operationFailed("createProof",
            reason: "Division by zero.");
      }

      // Collapse p' and b
      for (int i = 0; i < half; i++) {
        pPrime[i] = pPrime[i] + (pPrime[i + half] * uJInv);
        b[i] = b[i] + (b[i + half] * uJ);
      }

      // Truncate in-place (Rust truncate equivalent)
      pPrime.removeRange(half, pPrime.length);
      b.removeRange(half, b.length);

      // Collapse G'
      PolyCommitment.generatorCollapse(gPrime, uJ);
      gPrime.removeRange(half, gPrime.length);

      // Update synthetic blinding factor
      f += lJRandomness * uJInv;
      f += rJRandomness * uJ;
    }

    assert(pPrime.length == 1);
    final c = pPrime[0];

    transcript.writeScalar(c);
    transcript.writeScalar(f);
    return transcript.toBytes();
  }

  VestaNativePoint commitLagrangeSync(
      Polynomial<PallasNativeFp, LagrangeCoeff> poly, PallasNativeFp r) {
    return Halo2Utils.bestMultiexp(
        [...poly.values, r], [...params.gLagrange, params.w]);
  }

  FutureOr<VestaNativePoint> commitLagrange(
      Polynomial<PallasNativeFp, LagrangeCoeff> poly, PallasNativeFp r) {
    return Halo2Utils.bestMultiexp(
        [...poly.values, r], [...params.gLagrange, params.w]);
  }
}
