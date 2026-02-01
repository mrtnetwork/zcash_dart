import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/commitment/commitment.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/commitment/msm.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/params.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/transcript/transcript.dart';

class PolyMultiopen {
  static Halo2TranscriptWriter createProof(
      {required PolyParams params,
      required Halo2TranscriptWriter transcript,
      required List<ProverQuery> queries}) {
    final x1 = transcript.squeezeChallenge();
    final x2 = transcript.squeezeChallenge();
    final intermediateSets =
        constructIntermediateSets<PolynomialPointer, PallasNativeFp?>(queries);
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
        qPrimePoly = Polynomial(
          List.generate(
              old.values.length, (j) => old.values[j] * x2 + polyObj.values[j]),
        );
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

      pPoly = Polynomial(
        List.generate(
            pPoly.values.length, (j) => pPoly.values[j] * x4 + poly.values[j]),
      );
      pPolyBlind = pPolyBlind * x4 + blind;
    }
    return PolyCommitment.createProof(
        params, transcript, pPoly, pPolyBlind, x3);
  }

  static PolyGuard verifyProof(
      PolyParams params,
      Halo2TranscriptRead transcript,
      Iterable<VerifierQuery> queries,
      MSM msm) {
    // Sample x_1 for compressing openings at the same point sets together
    final x1 = transcript.squeezeChallenge(); // ChallengeX1

    // Sample x_2 for keeping multi-point quotient terms independent
    final x2 = transcript.squeezeChallenge();
    final intermediate =
        constructIntermediateSets<CommitmentReference, PallasNativeFp>(
            queries.toList());
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
    return PolyCommitment.verifyProof(params, msm, transcript, x3, v);
  }

  static (List<CommitmentData<C, F>>, List<List<PallasNativeFp>>)?
      constructIntermediateSets<C extends Object?, F extends PallasNativeFp?>(
          List<Query<F, C>> queries) {
    final Map<C, CommitmentData<C, F?>> commitmentMap = {};
    final Map<PallasNativeFp, int> pointIndexMap = {};

    // Assign point indices
    for (final query in queries) {
      final point = query.getPoint();
      final commitment = query.getCommitment();

      pointIndexMap.putIfAbsent(point, () => pointIndexMap.length);
      final pointIndex = pointIndexMap[point]!;

      commitmentMap
          .putIfAbsent(
              commitment, () => CommitmentData<C, F?>.defaultValue(commitment))
          .pointIndices
          .add(pointIndex);
    }

    // inverse mapping
    final inversePointIndexMap = <int, PallasNativeFp>{};
    pointIndexMap.forEach((p, i) => inversePointIndexMap[i] = p);

    // Canonical point-index sets
    final pointIdxSets = <String, int>{};
    final pointIdxSetValues = <String, Set<int>>{};
    final commitmentSetKeyMap = <C, String>{};
    String pointSetKey(Set<int> set) {
      final list = set.toList()..sort();
      return list.join(',');
    }

    for (final entry in commitmentMap.entries) {
      final indices = entry.value.pointIndices.toSet();
      final key = pointSetKey(indices);

      commitmentSetKeyMap[entry.key] = key;

      pointIdxSets.putIfAbsent(key, () {
        pointIdxSetValues[key] = indices;
        return pointIdxSets.length;
      });

      entry.value.evals = List<F?>.filled(indices.length, null);
    }

    // Populate evals
    for (final query in queries) {
      final commitment = query.getCommitment();
      final commitmentData = commitmentMap[commitment]!;
      final pointIndex = pointIndexMap[query.getPoint()]!;

      final key = commitmentSetKeyMap[commitment]!;
      final setIndex = pointIdxSets[key]!;

      commitmentData.setIndex = setIndex;

      final ordered = pointIdxSetValues[key]!.toList()..sort();
      final offset = ordered.indexOf(pointIndex);

      if (commitmentData.evals[offset] == null) {
        commitmentData.evals[offset] = query.getEval();
      } else {
        return null; // conflicting evaluation
      }
    }

    // Build point sets (Rust BTreeSet equivalent)
    final pointSets =
        List.generate(pointIdxSets.length, (_) => <PallasNativeFp>[]);

    pointIdxSetValues.forEach((key, set) {
      final setIdx = pointIdxSets[key]!;
      final ordered = set.toList()..sort();
      for (final idx in ordered) {
        pointSets[setIdx].add(inversePointIndexMap[idx]!);
      }
    });

    return (
      commitmentMap.values
          .map((e) => CommitmentData<C, F>(
              e.commitment, e.setIndex, e.pointIndices, e.evals.cast<F>()))
          .toList(),
      pointSets
    );
  }
}

abstract mixin class Query<EVAL extends PallasNativeFp?,
    COMMITMENT extends Object?> {
  PallasNativeFp getPoint();
  COMMITMENT getCommitment();
  EVAL getEval();
}

class ProverQuery with Query<PallasNativeFp?, PolynomialPointer>, Equality {
  final PallasNativeFp point;
  final Polynomial<PallasNativeFp, Coeff> poly;
  final PallasNativeFp blind;
  const ProverQuery(
      {required this.point, required this.poly, required this.blind});

  @override
  PallasNativeFp getPoint() {
    return point;
  }

  @override
  PolynomialPointer getCommitment() {
    return PolynomialPointer(poly, blind);
  }

  @override
  PallasNativeFp? getEval() => null;

  @override
  List<dynamic> get variables => [point, poly, blind];
}

class VerifierQuery extends Query<PallasNativeFp, CommitmentReference> {
  final PallasNativeFp point;
  final CommitmentReference commitment;
  final PallasNativeFp eval;

  VerifierQuery(
      {required this.point, required this.commitment, required this.eval});

  @override
  CommitmentReference getCommitment() {
    return commitment;
  }

  @override
  PallasNativeFp getEval() {
    return eval;
  }

  @override
  PallasNativeFp getPoint() {
    return point;
  }
}

class PolynomialPointer with Equality {
  final Polynomial<PallasNativeFp, Coeff> poly;
  final PallasNativeFp blind;
  const PolynomialPointer(this.poly, this.blind);

  @override
  List<dynamic> get variables => [poly, blind];
}
