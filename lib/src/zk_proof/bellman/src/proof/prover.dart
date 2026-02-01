import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/domain.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/multiexp.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/variable.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/groth16/params.dart';

class Groth16Prover {
  final Groth16Parameters params;
  const Groth16Prover(this.params);

  Groth16Proof createGroth16Proof<C extends BellmanCircuit>(C circuit,
      {JubJubNativeFq? r, JubJubNativeFq? s}) {
    r ??= JubJubNativeFq.random();
    s ??= JubJubNativeFq.random();
    final prover = _ProvingAssignment();

    prover.allocInput(() => JubJubNativeFq.one());

    circuit.synthesize(prover);

    for (int i = 0; i < prover.inputAssignment.length; i++) {
      prover.enforce(
          (lc) => lc + GVariable(GIndexInput(i)), (lc) => lc, (lc) => lc);
    }
    final vk = params.getVk();

    final h = () {
      final aDomain = SaplingEvaluationDomain.fromCoeffs(prover.a);
      final bDomain = SaplingEvaluationDomain.fromCoeffs(prover.b);
      final cDomain = SaplingEvaluationDomain.fromCoeffs(prover.c);
      aDomain.ifft();
      aDomain.cosetFFT();

      bDomain.ifft();
      bDomain.cosetFFT();
      cDomain.ifft();
      cDomain.cosetFFT();
      aDomain.mulAssign(bDomain);
      aDomain.subAssign(cDomain);

      aDomain.divideByZOnCoset();
      aDomain.icosetFFT();
      final aCoeffs =
          aDomain.coeffs.map((x) => Exponent.fromScalar(x.scalar)).toList();
      aCoeffs.removeLast();
      return GMultiexpUtils.multiexp(
          params.getHBuilder(aCoeffs.length), null, aCoeffs);
    }();

    final List<Exponent> inputAssignment =
        prover.inputAssignment.map((s) => Exponent.fromScalar(s)).toList();

    final List<Exponent> auxAssignment =
        prover.auxAssignment.map((s) => Exponent.fromScalar(s)).toList();

    final l = GMultiexpUtils.multiexp(
        params.getLBuilder(auxAssignment.length), null, auxAssignment);

    final int aAuxDensityTotal = prover.aAuxDensity.getTotalDensity();

    final (aInputsSource, aAuxSource) =
        params.getABuilders(inputAssignment.length, aAuxDensityTotal);

    final aInputs =
        GMultiexpUtils.multiexp(aInputsSource, null, inputAssignment);
    final aAux =
        GMultiexpUtils.multiexp(aAuxSource, prover.aAuxDensity, auxAssignment);
    final bInputDensity = prover.bInputDensity;
    final int bInputDensityTotal = bInputDensity.getTotalDensity();

    final bAuxDensity = prover.bAuxDensity;
    final int bAuxDensityTotal = bAuxDensity.getTotalDensity();

    final (bG1InputsSource, bG1AuxSource) =
        params.getBG1Builders(bInputDensityTotal, bAuxDensityTotal);

    final bG1Inputs = GMultiexpUtils.multiexp(
        bG1InputsSource, bInputDensity, inputAssignment);
    final bG1Aux =
        GMultiexpUtils.multiexp(bG1AuxSource, bAuxDensity, auxAssignment);
    final (bG2InputsSource, bG2AuxSource) =
        params.getBG2Builders(bInputDensityTotal, bAuxDensityTotal);
    final bG2Inputs = GMultiexpUtils.multiexp(
        bG2InputsSource, bInputDensity, inputAssignment);
    final bG2Aux =
        GMultiexpUtils.multiexp(bG2AuxSource, bAuxDensity, auxAssignment);

    if (vk.deltaG1.isIdentity() || vk.deltaG2.isIdentity()) {
      throw BellmanException.operationFailed("createProof");
    }

    G1NativeProjective gA = vk.deltaG1 * r;
    gA += vk.alphaG1;

    G2NativeProjective gB = vk.deltaG2 * s;
    gB += vk.betaG2;

    G1NativeProjective gC;
    {
      final rs = r * s;

      gC = vk.deltaG1 * rs;
      gC += vk.alphaG1 * s;
      gC += vk.betaG1 * r;
    }

    G1NativeProjective aAnswer = aInputs;
    aAnswer += aAux;

    gA += aAnswer;

    aAnswer *= s;

    gC += aAnswer;

    G1NativeProjective b1Answer = bG1Inputs;
    b1Answer += bG1Aux;

    G2NativeProjective b2Answer = bG2Inputs;
    b2Answer += bG2Aux;

    gB += b2Answer;

    b1Answer *= r;

    gC += b1Answer;
    gC += h;
    gC += l;
    return Groth16Proof(a: gA.toAffine(), b: gB.toAffine(), c: gC.toAffine());
  }
}

class _ProvingAssignment extends BellmanConstraintSystem<_ProvingAssignment> {
  static JubJubNativeFq _eval(LinearCombination lc,
      {DensityTracker? inputDensity,
      DensityTracker? auxDensity,
      required List<JubJubNativeFq> inputAssignment,
      required List<JubJubNativeFq> auxAssignment}) {
    var acc = JubJubNativeFq.zero();

    for (final (index, coeff) in lc.inner) {
      if (coeff.isZero()) {
        continue;
      }

      JubJubNativeFq tmp;
      if (index.isInput()) {
        tmp = inputAssignment[index.input];
        inputDensity?.inc(index.input);
      } else {
        tmp = auxAssignment[index.input];
        auxDensity?.inc(index.input);
      }

      if (coeff != JubJubNativeFq.one()) {
        tmp *= coeff;
      }

      acc += tmp;
    }

    return acc;
  }

  // Densities
  final DensityTracker aAuxDensity = DensityTracker();
  final DensityTracker bInputDensity = DensityTracker();
  final DensityTracker bAuxDensity = DensityTracker();

  // Evaluations of A, B, C polynomials
  final List<AssignableFq> a = [];
  final List<AssignableFq> b = [];
  final List<AssignableFq> c = [];

  // Assignments of variables
  final List<JubJubNativeFq> inputAssignment = [];
  final List<JubJubNativeFq> auxAssignment = [];

  @override
  _ProvingAssignment getRoot() => this;

  @override
  GVariable alloc(JubJubNativeFq Function() f) {
    final sc = f();
    auxAssignment.add(sc);
    aAuxDensity.addElement();
    bAuxDensity.addElement();
    return GVariable(GIndexAux(auxAssignment.length - 1));
  }

  @override
  GVariable allocInput(JubJubNativeFq Function() f) {
    inputAssignment.add(f());
    bInputDensity.addElement();

    return GVariable(GIndexInput(inputAssignment.length - 1));
  }

  @override
  void enforce(
    LinearCombination Function(LinearCombination) aFn,
    LinearCombination Function(LinearCombination) bFn,
    LinearCombination Function(LinearCombination) cFn,
  ) {
    final aLc = aFn(LinearCombination.zero());
    final bLc = bFn(LinearCombination.zero());
    final cLc = cFn(LinearCombination.zero());
    a.add(AssignableFq(_eval(aLc,
        inputDensity: null,
        auxDensity: aAuxDensity,
        inputAssignment: inputAssignment,
        auxAssignment: auxAssignment)));
    b.add(AssignableFq(_eval(
      bLc,
      inputDensity: bInputDensity,
      auxDensity: bAuxDensity,
      inputAssignment: inputAssignment,
      auxAssignment: auxAssignment,
    )));
    c.add(AssignableFq(_eval(
      cLc,
      inputDensity: null,
      auxDensity: null,
      inputAssignment: inputAssignment,
      auxAssignment: auxAssignment,
    )));
  }
}
