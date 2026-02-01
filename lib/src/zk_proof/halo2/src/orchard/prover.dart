import 'dart:async';

import 'package:blockchain_utils/layout/layout.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/halo2.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/verifier.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/proof/prover.dart';

class DefaultOrchardProver implements BaseOrchardProver {
  final PlonkProver prover;
  DefaultOrchardVerifier toVerifier() {
    return DefaultOrchardVerifier(prover.toVerifier());
  }

  const DefaultOrchardProver(this.prover);

  factory DefaultOrchardProver.build(ZCashCryptoContext context,
      {PolyParams? params, PlonkProvingKey? pk, PlonkVerifyingKey? vk}) {
    return DefaultOrchardProver(
        PlonkProver.build(context, params: params, pk: pk, vk: vk));
  }

  @override
  FutureOr<List<int>> createOrchardProof(List<OrchardProofInputs> args) {
    return prover.createProof(
        circuits: args.map((e) => e.circuit.toCircuit()).toList(),
        instances: args.map((e) => e.instance.toHalo2()).toList());
  }
}

class OrchardProofInputs with LayoutSerializable {
  final OrchardTransfableCircuit circuit;
  final OrchardCircuitInstance instance;
  const OrchardProofInputs({required this.circuit, required this.instance});
  static Layout<Map<String, dynamic>> layout({String? property}) =>
      OrchardTransfableCircuit.layout(property: property);
  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return circuit.toSerializeJson(instances: instance.instances());
  }
}

class OrchardBatchProofInputs with LayoutSerializable {
  final List<OrchardProofInputs> args;
  const OrchardBatchProofInputs(this.args);
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.vec(OrchardProofInputs.layout(), property: "args"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"args": args.map((e) => e.toSerializeJson()).toList()};
  }
}

abstract interface class BaseOrchardProver {
  FutureOr<List<int>> createOrchardProof(List<OrchardProofInputs> args);
}
