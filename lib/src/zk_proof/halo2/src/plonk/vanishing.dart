import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/commitment/msm.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/multiopen.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/key.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/commitment/commitment.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/domain.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/evaluator.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/params.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/transcript/transcript.dart';

class VanishingCommitted {
  final Polynomial<PallasNativeFp, Coeff> randomPoly;
  final PallasNativeFp randomBlind;
  const VanishingCommitted(
      {required this.randomPoly, required this.randomBlind});
  factory VanishingCommitted.commit(
      {required PolyParams params,
      required EvaluationDomain domain,
      required Halo2TranscriptWriter transcript}) {
    final randomPoly = domain.emptyCoeff();
    for (var i = 0; i < randomPoly.length; i++) {
      randomPoly.values[i] = PallasNativeFp.random();
    }

    // Sample a random blinding factor
    final randomBlind = PallasNativeFp.random();

    // Commit and write to transcript
    final c = params.commit(randomPoly, randomBlind).toAffine();
    transcript.writePoint(c);

    return VanishingCommitted(
      randomPoly: randomPoly,
      randomBlind: randomBlind,
    );
  }
  List<AstContext> buildContext(
      Evaluator<ExtendedLagrangeCoeff> evaluator,
      EvaluationDomain domain,
      PallasNativeFp y,
      Iterable<Ast<ExtendedLagrangeCoeff>> expressions,
      {int numThreads = 4}) {
    return evaluator.buildContext(
        AstDistributePowers<ExtendedLagrangeCoeff>(expressions.toList(), y),
        domain,
        ExtendedLagrangeCoeffOps(),
        numThreads: numThreads);
  }

  VanishingConstructed construct(
      PolyParams params,
      EvaluationDomain domain,
      Evaluator<ExtendedLagrangeCoeff> evaluator,
      Iterable<Ast<ExtendedLagrangeCoeff>> expressions,
      PallasNativeFp y,
      Halo2TranscriptWriter transcript,
      {AstContextResult? result}) {
    // Fold the gates together using the y challenge
    final ops = ExtendedLagrangeCoeffOps();
    // Evaluate the h(X) polynomial
    Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> hPoly = () {
      if (result == null) {
        final hPolyAst =
            AstDistributePowers<ExtendedLagrangeCoeff>(expressions.toList(), y);
        return evaluator.evaluate(hPolyAst, domain, ops);
      }
      return evaluator.combine(result, domain, ops);
    }();

    // Divide by t(X) = X^n - 1
    hPoly = domain.divideByVanishingPoly(hPoly);

    // Convert from extended to coefficient representation
    hPoly = Polynomial(domain.extendedToCoeff(hPoly));
    // Split h(X) into pieces of size n
    final List<Polynomial<PallasNativeFp, Coeff>> hPieces = [];

    for (var i = 0; i < hPoly.length; i += params.n) {
      final chunk = hPoly.values.sublist(i, i + params.n);
      hPieces.add(domain.coeffFromVec(chunk));
    }

    // Generate random blinding factors for each piece
    final hBlinds =
        List.generate(hPieces.length, (_) => PallasNativeFp.random());

    // Commit to each h(X) piece
    final hCommitments = List.generate(hPieces.length,
        (i) => params.commit(hPieces[i], hBlinds[i]).toAffine());

    // Hash each h(X) piece into the transcript
    for (final c in hCommitments) {
      transcript.writePoint(c);
    }

    return VanishingConstructed(
        hPieces: hPieces, hBlinds: hBlinds, committed: this);
  }
}

class VanishingConstructed {
  final List<Polynomial<PallasNativeFp, Coeff>> hPieces;
  final List<PallasNativeFp> hBlinds;
  final VanishingCommitted committed;
  const VanishingConstructed(
      {required this.hPieces, required this.hBlinds, required this.committed});

  VanishingEvaluated evaluate(PallasNativeFp x, PallasNativeFp xn,
      EvaluationDomain domain, Halo2TranscriptWriter transcript) {
    // h_poly evaluation (reverse order)
    Polynomial<PallasNativeFp, Coeff> hPoly = domain.emptyCoeff();
    for (var i = hPieces.length - 1; i >= 0; i--) {
      hPoly = hPoly * xn + hPieces[i];
    }

    // h_blind evaluation (reverse order)
    PallasNativeFp hBlind = PallasNativeFp.zero(); // ZERO
    for (int i = hBlinds.length - 1; i >= 0; i--) {
      hBlind = hBlind * xn + hBlinds[i];
    }

    // random polynomial evaluation
    PallasNativeFp randomEval =
        Halo2Utils.evalPolynomial(committed.randomPoly.values, x);
    transcript.writeScalar(randomEval);

    return VanishingEvaluated(
        hPoly: hPoly, hBlind: hBlind, committed: committed);
  }
}

class VanishingEvaluated {
  final Polynomial<PallasNativeFp, Coeff> hPoly;
  final PallasNativeFp hBlind;
  final VanishingCommitted committed;
  const VanishingEvaluated({
    required this.hPoly,
    required this.hBlind,
    required this.committed,
  });
  List<ProverQuery> open(PallasNativeFp x) {
    return [
      ProverQuery(point: x, poly: hPoly, blind: hBlind),
      ProverQuery(
          point: x, poly: committed.randomPoly, blind: committed.randomBlind),
    ];
  }
}

class VanishingReadCommitted {
  final VestaAffineNativePoint randomPolyCommitment;
  const VanishingReadCommitted(this.randomPolyCommitment);
  factory VanishingReadCommitted.readCommitmentsBeforeY(
      Halo2TranscriptRead transcript) {
    return VanishingReadCommitted(transcript.readPoint());
  }

  VanishingReadConstructed readCommitmentsAfterY(
      PlonkVerifyingKey vk, Halo2TranscriptRead transcript) {
    return VanishingReadConstructed(
        randomPolyCommitment: randomPolyCommitment,
        hCommitments: transcript.readNPoint(vk.domain.quotientPolyDegree));
  }
}

class VanishingReadConstructed {
  final List<VestaAffineNativePoint> hCommitments;
  final VestaAffineNativePoint randomPolyCommitment;
  const VanishingReadConstructed(
      {required this.randomPolyCommitment, required this.hCommitments});
  VanishingPartiallyEvaluated evaluateAfterX(Halo2TranscriptRead transcript) {
    return VanishingPartiallyEvaluated(
        hCommitments, randomPolyCommitment, transcript.readScalar());
  }
}

class VanishingPartiallyEvaluated {
  final List<VestaAffineNativePoint> hCommitments;
  final VestaAffineNativePoint randomPolyCommitment;
  final PallasNativeFp randomEval;
  const VanishingPartiallyEvaluated(
      this.hCommitments, this.randomPolyCommitment, this.randomEval);

  VanishingVerifyEvaluated verify(
      {required PolyParams params,
      required Iterable<PallasNativeFp> expressions,
      required PallasNativeFp y,
      required PallasNativeFp xn}) {
    // expected_h_eval = (∑ v_i * y^i) / (x^n - 1)
    PallasNativeFp expectedHEval = PallasNativeFp.zero();
    for (final v in expressions) {
      expectedHEval = expectedHEval * y + v;
    }

    expectedHEval = expectedHEval *
        ((xn - PallasNativeFp.one()).invert() ?? PallasNativeFp.zero());

    // h_commitment = h_0 + x^n h_1 + x^{2n} h_2 + ...
    final hCommitment =
        hCommitments.reversed.fold(MSM(params), (acc, commitment) {
      acc.scale(xn);
      acc.appendTerm(PallasNativeFp.one(), commitment);
      return acc;
    });

    return VanishingVerifyEvaluated(
      expectedHEval: expectedHEval,
      hCommitment: hCommitment,
      polyCommitment: randomPolyCommitment,
      randomEval: randomEval,
    );
  }
}

class VanishingVerifyEvaluated {
  final MSM hCommitment;
  final VestaAffineNativePoint polyCommitment;
  final PallasNativeFp expectedHEval;
  final PallasNativeFp randomEval;
  const VanishingVerifyEvaluated(
      {required this.hCommitment,
      required this.polyCommitment,
      required this.expectedHEval,
      required this.randomEval});
  List<VerifierQuery> queries(PallasNativeFp x) {
    return [
      // Open vanishing polynomial MSM at x
      VerifierQuery(
        commitment: CommitmentReferenceMSM(hCommitment),
        point: x,
        eval: expectedHEval,
      ),

      // Open random polynomial commitment at x
      VerifierQuery(
          commitment: CommitmentReferenceCommitment(polyCommitment),
          point: x,
          eval: randomEval),
    ];
  }
}
