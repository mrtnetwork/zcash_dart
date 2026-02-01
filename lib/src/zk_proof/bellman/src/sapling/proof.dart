import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/zk_proof/bellman/bellman.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/verifier.dart';

class SaplingProofInputs<C extends BellmanCircuit> {
  final C circuit;
  final JubJubNativeFq? r;
  final JubJubNativeFq? s;
  const SaplingProofInputs({required this.circuit, this.r, this.s});
}

class DefaultSaplingProver implements BaseSaplingProver {
  final Groth16Parameters? outputParams;
  final Groth16Parameters? spendParams;
  const DefaultSaplingProver({this.outputParams, this.spendParams});

  DefaultSaplingVerifier toVerifier() => DefaultSaplingVerifier(
      outputParams: outputParams, spendParams: spendParams);

  @override
  List<GrothProofBytes> createOutputProofs(
      List<SaplingProofInputs<SaplingOutput>> proofs) {
    final params = outputParams;
    if (params == null) {
      throw SaplingException("Missing sapling output params");
    }
    final groth = Groth16Prover(params);
    return proofs
        .map((e) => GrothProofBytes(groth
            .createGroth16Proof<SaplingOutput>(e.circuit, r: e.r, s: e.s)
            .toSerializeBytes()))
        .toList();
  }

  @override
  List<GrothProofBytes> createSpendProofs(
      List<SaplingProofInputs<SaplingSpend>> proofs) {
    final params = spendParams;
    if (params == null) {
      throw SaplingException("Missing sapling spend params");
    }
    final groth = Groth16Prover(params);
    return proofs
        .map((e) => GrothProofBytes(groth
            .createGroth16Proof<SaplingSpend>(e.circuit, r: e.r, s: e.s)
            .toSerializeBytes()))
        .toList();
  }
}

abstract mixin class BaseSaplingProver {
  FutureOr<List<GrothProofBytes>> createSpendProofs(
      List<SaplingProofInputs<SaplingSpend>> proofs);
  FutureOr<List<GrothProofBytes>> createOutputProofs(
      List<SaplingProofInputs<SaplingOutput>> proofs);
}
