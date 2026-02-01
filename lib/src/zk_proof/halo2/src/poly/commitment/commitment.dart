import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/commitment/msm.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/params.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/transcript/transcript.dart';

class PolyCommitment {
  static Halo2TranscriptWriter createProof(
      PolyParams params,
      Halo2TranscriptWriter transcript,
      Polynomial<PallasNativeFp, Coeff> pPoly,
      PallasNativeFp pBlind,
      PallasNativeFp x3) {
    if (pPoly.values.length != params.n) {
      throw ArgumentException.invalidOperationArguments("createProof",
          reason: "Invalid poly length.");
    }

    // Sample a random polynomial sPoly of the same degree with root at x3
    final sPoly = pPoly.clone(); // copy
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
        pPoly.values.length, (i) => pPoly.values[i] + sPoly.values[i] * xi));
    final v = Halo2Utils.evalPolynomial(pPrimePoly.values, x3);
    pPrimePoly.values[0] = pPrimePoly.values[0] - v;
    final pPrimeBlind = sBlind * xi + pBlind;

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
      generatorCollapse(gPrime, uJ);
      gPrime.removeRange(half, gPrime.length);

      // Update synthetic blinding factor
      f += lJRandomness * uJInv;
      f += rJRandomness * uJ;
    }

    assert(pPrime.length == 1);
    final c = pPrime[0];

    transcript.writeScalar(c);
    transcript.writeScalar(f);
    return transcript;
  }

  static PolyGuard verifyProof(PolyParams params, MSM msm,
      Halo2TranscriptRead transcript, PallasNativeFp x, PallasNativeFp v) {
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

    // Batch invert u_j
    final inverses = rounds.map((e) => e.$3).toList(growable: false);
    Halo2Utils.batchInvert(inverses);

    // Build MSM
    final u = <PallasNativeFp>[];
    // final uPacked = <Challenge255>[];

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

    final b = computeB(x, u);

    msm.addToUScalar(negC * b * z);
    msm.addToWScalar(-f);

    return PolyGuard(msm: msm, negC: negC, u: u);
  }

  static List<PallasNativeFp> computeS(
      List<PallasNativeFp> u, PallasNativeFp init) {
    assert(u.isNotEmpty);
    final size = 1 << u.length;
    final v = List<PallasNativeFp>.filled(size, PallasNativeFp.zero());
    v[0] = init;
    for (int i = 0; i < u.length; i++) {
      final uj = u[u.length - 1 - i];
      final len = 1 << i;
      for (int j = 0; j < len; j++) {
        v[j + len] = v[j] * uj;
      }
    }

    return v;
  }

  static PallasNativeFp computeB(
    PallasNativeFp x,
    List<PallasNativeFp> u,
  ) {
    PallasNativeFp tmp = PallasNativeFp.one();
    PallasNativeFp cur = x;

    for (final uj in u.reversed) {
      tmp *= (PallasNativeFp.one() + uj * cur);
      cur *= cur;
    }

    return tmp;
  }

  static void generatorCollapse(
    List<VestaAffineNativePoint> g,
    PallasNativeFp challenge,
  ) {
    final half = g.length >> 1;

    for (int i = 0; i < half; i++) {
      final lo = g[i].toCurve();
      final hi = g[i + half] * challenge;
      g[i] = (lo + hi).toAffine();
    }
  }
}

sealed class CommitmentReference with Equality {
  const CommitmentReference();
}

class CommitmentReferenceCommitment extends CommitmentReference {
  final VestaAffineNativePoint inner;
  const CommitmentReferenceCommitment(this.inner);

  @override
  List<dynamic> get variables => [inner];
}

class CommitmentReferenceMSM extends CommitmentReference {
  final MSM inner;
  const CommitmentReferenceMSM(this.inner);

  @override
  List<dynamic> get variables => [inner];
}

class PolyGuard {
  final MSM msm;
  final PallasNativeFp negC;
  final List<PallasNativeFp> u;

  const PolyGuard({
    required this.msm,
    required this.negC,
    required this.u,
  });

  /// Apply challenges to MSM (adds s into g scalars)
  MSM useChallenges() {
    final s = PolyCommitment.computeS(u, negC);
    msm.addToGScalars(s);
    return msm;
  }
}

class CommitmentData<C extends Object?, F extends PallasNativeFp?> {
  final C commitment;
  int setIndex;
  final List<int> pointIndices;
  List<F> evals;
  CommitmentData(this.commitment, this.setIndex, this.pointIndices, this.evals);
  factory CommitmentData.defaultValue(C commitment) =>
      CommitmentData<C, F>(commitment, 0, [], []);
}
