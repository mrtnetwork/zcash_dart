import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/zk_proof/bellman/bellman.dart';

class DefaultSaplingVerifier implements BaseSaplingVerifier {
  final Groth16Parameters? outputParams;
  final Groth16Parameters? spendParams;
  const DefaultSaplingVerifier({this.outputParams, this.spendParams});

  @override
  FutureOr<bool> verifyOutputProofs(List<SaplingVerifyInputs> args) {
    final params = outputParams;
    if (params == null) {
      throw SaplingException("Missing sapling output params.");
    }
    final groth = Groth16Verifier(params.getVk().prepareVerifyingKey());
    final result = args.map(
        (e) => groth.verify(Groth16Proof.deserialize(e.proof.inner), e.inputs));
    return result.fold<bool>(true, (p, c) => p & c);
  }

  @override
  FutureOr<bool> verifySpendProofs(List<SaplingVerifyInputs> args) {
    final params = spendParams;
    if (params == null) {
      throw SaplingException("Missing sapling spend params.");
    }
    final groth = Groth16Verifier(params.getVk().prepareVerifyingKey());
    final result = args.map(
        (e) => groth.verify(Groth16Proof.deserialize(e.proof.inner), e.inputs));
    return result.fold<bool>(true, (p, c) => p & c);
  }
}

class SaplingVerifyInputs with LayoutSerializable {
  final GrothProofBytes proof;
  final List<JubJubNativeFq> inputs;
  SaplingVerifyInputs._(
      {required this.proof, required List<JubJubNativeFq> inputs})
      : inputs = inputs.immutable;
  factory SaplingVerifyInputs(
      {required GrothProofBytes proof, required List<JubJubNativeFq> inputs}) {
    if (inputs.length != 5 && inputs.length != 7) {
      throw SaplingException("Invalid sapling proof public inputs length.");
    }
    return SaplingVerifyInputs._(proof: proof, inputs: inputs);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return LayoutConst.struct([
      GrothProofBytes.layout(property: "proof"),
      LayoutConst.array(LayoutConst.fixedBlob32(), inputs.length,
          property: "inputs")
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "proof": proof.toSerializeJson(),
      "inputs": inputs.map((e) => e.toBytes()).toList()
    };
  }
}

abstract mixin class BaseSaplingVerifier {
  FutureOr<bool> verifySpendProofs(List<SaplingVerifyInputs> args);
  FutureOr<bool> verifyOutputProofs(List<SaplingVerifyInputs> args);
}
