import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/halo2.dart';

class PlonkVerifier {
  final PolyParams params;
  final PlonkVerifyingKey vk;
  const PlonkVerifier({required this.params, required this.vk});
  factory PlonkVerifier.build(ZCashCryptoContext context,
      {PolyParams? params, PlonkVerifyingKey? vk}) {
    params ??= PolyParams.newParams(11);
    vk ??= PlonkKeyGenerator.keygenVk(OrchardCircuit.defaultConfig(), context,
        k: 11, p: params);
    return PlonkVerifier(params: params, vk: vk);
  }
  bool verifySync({
    required List<int> proofBytes,
    required List<List<List<PallasNativeFp>>> instances,
  }) {
    for (final i in instances) {
      if (i.length != vk.cs.numInstanceColumns) {
        throw Halo2Exception.operationFailed("verify",
            reason: "Invalid instances length.");
      }
    }
    final transcript = Halo2TranscriptRead(proofBytes);
    final queries =
        buildQueriesSync(transcript: transcript, instances: instances);
    final strategy = MSM(params);
    final multiopen =
        multiopenSync(msm: strategy, queries: queries, transcript: transcript);
    final guard = commitmentSync(
        msm: strategy, transcript: transcript, x: multiopen.x, v: multiopen.v);
    return guard.useChallenges().eval();
  }

  List<VerifierQuery> buildQueriesSync({
    required Halo2TranscriptRead transcript,
    required List<List<List<PallasNativeFp>>> instances,
  }) {
    List<List<VestaAffineNativePoint>> instanceCommitments =
        instances.map((instanceVec) {
      return instanceVec.map((instance) {
        if (instance.length > params.n - (vk.cs.blindingFactors() + 1)) {
          throw Halo2Exception.operationFailed("verify",
              reason: "Invalid instances length.");
        }
        final polyCoeffs = List<PallasNativeFp>.from(instance);
        if (polyCoeffs.length < params.n) {
          polyCoeffs.addAll(
            List<PallasNativeFp>.filled(
                params.n - polyCoeffs.length, PallasNativeFp.zero()),
          );
        }
        final poly = vk.domain.lagrangeFromVec(polyCoeffs);
        return params.commitLagrange(poly, PallasNativeFp.one()).toAffine();
      }).toList();
    }).toList();

    /// Hash verification key into transcript
    vk.hashInto(transcript);

    /// Hash instance (external) commitments into the transcript
    for (final instanceCommitmentsForProof in instanceCommitments) {
      for (final commitment in instanceCommitmentsForProof) {
        transcript.commonPoint(commitment);
      }
    }
    final numProofs = instanceCommitments.length;

    /// Read advice commitments from transcript
    final List<List<VestaAffineNativePoint>> adviceCommitments =
        List.generate(numProofs, (_) {
      return transcript.readNPoint(vk.cs.numAdviceColumns);
    });

    /// Sample theta challenge for keeping lookup columns linearly independent
    final theta = transcript.squeezeChallenge();

    /// Read lookups permuted commitments
    final List<List<LookPermutationCommitments>> lookupsPermuted =
        List.generate(numProofs, (_) {
      final commitmentsForProof = <LookPermutationCommitments>[];

      for (final argument in vk.cs.lookups) {
        final readCommitments = argument.readPermutedCommitments(transcript);
        commitmentsForProof.add(readCommitments);
      }

      return commitmentsForProof;
    });

    /// Sample beta challenge
    final beta = transcript.squeezeChallenge();

    /// Sample gamma challenge
    final gamma = transcript.squeezeChallenge();

    /// Read permutation product commitments
    final List<PermutationVerifyCommitted> permutationsCommitted =
        List.generate(numProofs, (_) {
      return vk.cs.permutation.readProductCommitments(vk, transcript);
    });

    final List<List<LookupVerifyCommitted>> lookupsCommitted =
        lookupsPermuted.map((lookupsForProof) {
      final committedForProof = <LookupVerifyCommitted>[];

      for (final lookup in lookupsForProof) {
        // Read product commitments for each lookup
        final commitments = lookup.readProductCommitment(transcript);
        committedForProof.add(commitments);
      }

      return committedForProof;
    }).toList();

    final v = VanishingReadCommitted.readCommitmentsBeforeY(transcript);

    final y = transcript.squeezeChallenge();
    VanishingReadConstructed vp = v.readCommitmentsAfterY(vk, transcript);
    final x = transcript.squeezeChallenge();

    /// Read instance evaluations for each proof
    final List<List<PallasNativeFp>> instanceEvals =
        List.generate(numProofs, (_) {
      return transcript.readNScalars(vk.cs.instanceQueries.length);
    });

    /// Read advice evaluations for each proof
    final List<List<PallasNativeFp>> adviceEvals =
        List.generate(numProofs, (_) {
      return transcript.readNScalars(vk.cs.adviceQueries.length);
    });

    /// Read fixed evaluations (once, outside proofs)
    final List<PallasNativeFp> fixedEvals =
        transcript.readNScalars(vk.cs.fixedQueries.length);
    final pVanishing = vp.evaluateAfterX(transcript);

    /// Evaluate the common permutation
    final permutationsCommon = vk.permutation.evaluate(transcript);

    /// Evaluate each committed permutation per proof
    final List<PermutationVerifyEvaluated> permutationsEvaluated =
        permutationsCommitted.map((permutation) {
      return permutation.evaluate(transcript);
    }).toList();

    /// Evaluate each lookup per proof
    final List<List<LookupVerifyEvaluated>> lookupsEvaluated =
        lookupsCommitted.map((lookupsForProof) {
      return lookupsForProof.map((lookup) {
        return lookup.evaluate(transcript);
      }).toList();
    }).toList();

    final vanishing = vanishingSync(
        x: x,
        gamma: gamma,
        beta: beta,
        theta: theta,
        y: y,
        adviceEvals: adviceEvals,
        instanceEvals: instanceEvals,
        permutationsEvaluated: permutationsEvaluated,
        lookupsEvaluated: lookupsEvaluated,
        fixedEvals: fixedEvals,
        permutationsCommon: permutationsCommon,
        vanishing: pVanishing);

    return <VerifierQuery>[
      // Per-proof queries
      ...Iterable.generate(instanceCommitments.length).expand((i) {
        final instanceCommitmentsI = instanceCommitments[i];
        final instanceEvalsI = instanceEvals[i];
        final adviceCommitmentsI = adviceCommitments[i];
        final adviceEvalsI = adviceEvals[i];
        final permutation = permutationsEvaluated[i];
        final lookups = lookupsEvaluated[i];

        return <VerifierQuery>[
          // Instance queries
          ...Iterable.generate(vk.cs.instanceQueries.length).map((queryIndex) {
            final entry = vk.cs.instanceQueries[queryIndex];
            final column = entry.column;
            final at = entry.rotation;
            return VerifierQuery(
              commitment: CommitmentReferenceCommitment(
                  instanceCommitmentsI[column.index]),
              point: vk.domain.rotateOmega(x, at),
              eval: instanceEvalsI[queryIndex],
            );
          }),

          // Advice queries
          ...Iterable.generate(vk.cs.adviceQueries.length).map((queryIndex) {
            final entry = vk.cs.adviceQueries[queryIndex];
            final column = entry.column;
            final at = entry.rotation;
            return VerifierQuery(
              commitment: CommitmentReferenceCommitment(
                  adviceCommitmentsI[column.index]),
              point: vk.domain.rotateOmega(x, at),
              eval: adviceEvalsI[queryIndex],
            );
          }),
          ...permutation.queries(vk, x),
          ...lookups.expand((p) => p.queries(vk, x)),
        ];
      }),
      ...Iterable.generate(vk.cs.fixedQueries.length).map((queryIndex) {
        final entry = vk.cs.fixedQueries[queryIndex];
        final column = entry.column;
        final at = entry.rotation;
        return VerifierQuery(
          commitment:
              CommitmentReferenceCommitment(vk.fixedCommitments[column.index]),
          point: vk.domain.rotateOmega(x, at),
          eval: fixedEvals[queryIndex],
        );
      }),
      ...permutationsCommon.queries(vk.permutation, x),
      ...vanishing.queries(x),
    ];
  }

  VanishingVerifyEvaluated vanishingSync({
    required PallasNativeFp x,
    required PallasNativeFp gamma,
    required PallasNativeFp beta,
    required PallasNativeFp theta,
    required PallasNativeFp y,
    required List<List<PallasNativeFp>> adviceEvals,
    required List<List<PallasNativeFp>> instanceEvals,
    required List<PermutationVerifyEvaluated> permutationsEvaluated,
    required List<List<LookupVerifyEvaluated>> lookupsEvaluated,
    required List<PallasNativeFp> fixedEvals,
    required PermutationVerifyCommonEvaluated permutationsCommon,
    required VanishingPartiallyEvaluated vanishing,
  }) {
    // Compute x^n
    final xn = x.pow(BigInt.from(params.n));

    final blindingFactors = vk.cs.blindingFactors();
    final rotations = List<int>.generate(
        blindingFactors + 2, (i) => -blindingFactors - 1 + i);
    final lEvals = vk.domain.lIRange(x, xn, rotations);
    assert(lEvals.length == 2 + blindingFactors);

    final lLast = lEvals[0];
    final lBlind = lEvals
        .sublist(1, 1 + blindingFactors)
        .fold(PallasNativeFp.zero(), (acc, eval) => acc + eval);
    final l0 = lEvals[1 + blindingFactors];
    final expressions = <PallasNativeFp>[];
    for (int proofIdx = 0; proofIdx < adviceEvals.length; proofIdx++) {
      final adviceEval = adviceEvals[proofIdx];
      final instanceEval = instanceEvals[proofIdx];
      final permutation = permutationsEvaluated[proofIdx];
      final lookups = lookupsEvaluated[proofIdx];

      // Custom gates
      for (final gate in vk.cs.gates) {
        for (final poly in gate.polys) {
          final val = poly.evaluate<PallasNativeFp>(
            constant: (scalar) => scalar, // identity for scalar
            selectorColumn: (_) => throw Halo2Exception.operationFailed(
                "verify",
                reason: "virtual selectors removed during optimization"),
            fixedColumn: (query) => fixedEvals[query.index],
            adviceColumn: (query) => adviceEval[query.index],
            instanceColumn: (query) => instanceEval[query.index],
            negated: (a) => -a,
            sum: (a, b) => a + b,
            product: (a, b) => a * b,
            scaled: (a, scalar) => a * scalar,
          );
          expressions.add(val);
        }
      }

      // Permutation expressions
      expressions.addAll(permutation.expressions(
          vk: vk,
          p: vk.cs.permutation,
          common: permutationsCommon,
          adviceEvals: adviceEval,
          fixedEvals: fixedEvals,
          instanceEvals: instanceEval,
          l0: l0,
          lLast: lLast,
          lBlind: lBlind,
          beta: beta,
          gamma: gamma,
          x: x));

      // Lookup expressions
      for (int i = 0; i < lookups.length; i++) {
        final p = lookups[i];
        final argument = vk.cs.lookups[i];
        expressions.addAll(p.expressions(
          l0: l0,
          lLast: lLast,
          lBlind: lBlind,
          argument: argument,
          theta: theta,
          beta: beta,
          gamma: gamma,
          adviceEvals: adviceEval,
          fixedEvals: fixedEvals,
          instanceEvals: instanceEval,
        ));
      }
    }

    return vanishing.verify(
        params: params, expressions: expressions, y: y, xn: xn);
  }

  VanishingVerifyEvaluated vanishing({
    required PallasNativeFp x,
    required PallasNativeFp gamma,
    required PallasNativeFp beta,
    required PallasNativeFp theta,
    required PallasNativeFp y,
    required List<List<PallasNativeFp>> adviceEvals,
    required List<List<PallasNativeFp>> instanceEvals,
    required List<PermutationVerifyEvaluated> permutationsEvaluated,
    required List<List<LookupVerifyEvaluated>> lookupsEvaluated,
    required List<PallasNativeFp> fixedEvals,
    required PermutationVerifyCommonEvaluated permutationsCommon,
    required VanishingPartiallyEvaluated vanishing,
  }) {
    return vanishingSync(
        x: x,
        gamma: gamma,
        beta: beta,
        theta: theta,
        y: y,
        adviceEvals: adviceEvals,
        instanceEvals: instanceEvals,
        permutationsEvaluated: permutationsEvaluated,
        lookupsEvaluated: lookupsEvaluated,
        fixedEvals: fixedEvals,
        permutationsCommon: permutationsCommon,
        vanishing: vanishing);
  }

  ({PallasNativeFp x, PallasNativeFp v}) multiopenSync(
      {required MSM msm,
      required List<VerifierQuery> queries,
      required Halo2TranscriptRead transcript}) {
    // Sample x_1 for compressing openings at the same point sets together
    final x1 = transcript.squeezeChallenge(); // ChallengeX1

    // Sample x_2 for keeping multi-point quotient terms independent
    final x2 = transcript.squeezeChallenge();
    final intermediate = PolyMultiopen.constructIntermediateSets<
        CommitmentReference, PallasNativeFp>(queries.toList());
    if (intermediate == null) {
      throw Halo2Exception.operationFailed("verifyProof",
          reason: "Queries iterator contains mismatching items.");
    }

    final commitmentMap = intermediate.$1;
    final pointSets = intermediate.$2;
    // (accumulator MSM, next x1 power)
    final qCommitments = List.generate(
      pointSets.length,
      (_) => (MSM(params), PallasNativeFp.one()),
    );

    // evaluation sets per point set
    final qEvalSets = <List<PallasNativeFp>>[];
    for (final set in pointSets) {
      qEvalSets.add(List.filled(set.length, PallasNativeFp.zero()));
    }

    void accumulate(
      int setIdx,
      CommitmentReference commitment,
      List<PallasNativeFp> evals,
    ) {
      final entry = qCommitments[setIdx];
      final qCommitment = entry.$1;
      var x1Power = entry.$2;

      switch (commitment) {
        case CommitmentReferenceCommitment(:final inner):
          qCommitment.appendTerm(x1Power, inner);
          break;
        case CommitmentReferenceMSM(:final inner):
          final msmCopy = inner.clone();
          msmCopy.scale(x1Power);
          qCommitment.addMsm(msmCopy);
          break;
      }

      for (var i = 0; i < evals.length; i++) {
        qEvalSets[setIdx][i] += evals[i] * x1Power;
      }

      qCommitments[setIdx] = (qCommitment, x1Power * x1);
    }

    // Important: reverse order (matches Rust `.rev()`)
    for (final data in commitmentMap.reversed) {
      accumulate(data.setIndex, data.commitment, data.evals);
    }

    // Read commitment to quotient polynomial f(X)
    final qPrimeCommitment = transcript.readPoint();
    // Sample x_3
    final x3 = transcript.squeezeChallenge(); // ChallengeX3
    // Read evaluations u
    final u = <PallasNativeFp>[];
    for (var i = 0; i < qEvalSets.length; i++) {
      u.add(transcript.readScalar());
    }

    // Compute expected MSM evaluation at x_3
    PallasNativeFp msmEval = PallasNativeFp.zero();
    for (var i = 0; i < pointSets.length; i++) {
      final points = pointSets[i];
      final evals = qEvalSets[i];
      final proofEval = u[i];

      final rPoly = Halo2Utils.lagrangeInterpolate(points, evals);
      final rEval = Halo2Utils.evalPolynomial(rPoly, x3);

      var eval = proofEval - rEval;
      for (final point in points) {
        final inv = (x3 - point).invert();
        if (inv == null) {
          throw Halo2Exception.operationFailed("verifyProof",
              reason: "Division by zero.");
        }
        eval *= inv;
      }

      msmEval = msmEval * x2 + eval;
    }

    final x4 = transcript.squeezeChallenge();
    msm.appendTerm(PallasNativeFp.one(), qPrimeCommitment);

    var v = msmEval;
    for (var i = 0; i < qCommitments.length; i++) {
      final qCommitment = qCommitments[i].$1;
      final qEval = u[i];

      msm.scale(x4);
      msm.addMsm(qCommitment);

      v = v * x4 + qEval;
    }
    return (x: x3, v: v);
  }

  PolyGuard commitmentSync(
      {required MSM msm,
      required Halo2TranscriptRead transcript,
      required PallasNativeFp x,
      required PallasNativeFp v}) {
    final k = params.k;

    // P' = P - [v] G_0
    msm.addConstantTerm(-v);

    // Read S commitment
    final sPolyCommitment = transcript.readPoint();

    final xi = transcript.squeezeChallenge();
    msm.appendTerm(xi, sPolyCommitment);

    final z = transcript.squeezeChallenge();

    // Rounds
    final rounds = <(
      VestaAffineNativePoint,
      VestaAffineNativePoint,
      PallasNativeFp,
    )>[];

    for (int i = 0; i < k; i++) {
      final l = transcript.readPoint();
      final r = transcript.readPoint();
      final u = transcript.squeezeChallenge();
      rounds.add((l, r, u));
    }
    final inverses = rounds.map((e) => e.$3).toList(growable: false);
    Halo2Utils.batchInvert(inverses);
    // Build MSM
    final u = <PallasNativeFp>[];

    for (int i = 0; i < rounds.length; i++) {
      final (l, r, uj) = rounds[i];
      final ujInv = inverses[i];

      msm.appendTerm(ujInv, l);
      msm.appendTerm(uj, r);
      u.add(uj);
    }

    // Read c and f
    final c = transcript.readScalar();
    final negC = -c;

    final f = transcript.readScalar();

    final b = PolyCommitment.computeB(x, u);

    msm.addToUScalar(negC * b * z);
    msm.addToWScalar(-f);

    return PolyGuard(msm: msm, negC: negC, u: u);
  }
}
