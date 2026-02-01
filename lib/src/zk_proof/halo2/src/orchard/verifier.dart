import 'dart:async';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/halo2.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/proof/verifier.dart';

class DefaultOrchardVerifier implements BaseOrchardVerifier {
  final PlonkVerifier verifier;
  const DefaultOrchardVerifier(this.verifier);
  factory DefaultOrchardVerifier.build(ZCashCryptoContext context,
      {PolyParams? params, PlonkVerifyingKey? vk}) {
    return DefaultOrchardVerifier(
        PlonkVerifier.build(context, params: params, vk: vk));
  }

  @override
  FutureOr<bool> verifyOrchardProof(OrchardVerifyInputs args) {
    return verifier.verifySync(
        proofBytes: args.proofBytes,
        instances: args.instances.map((e) => e.toHalo2()).toList());
  }
}

class OrchardVerifyInputs with LayoutSerializable {
  final List<int> proofBytes;
  final List<OrchardCircuitInstance> instances;
  const OrchardVerifyInputs(
      {required this.proofBytes, required this.instances});
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.vecU8(property: "proof"),
      LayoutConst.vec(LayoutConst.array(LayoutConst.fixedBlob32(), 9),
          property: "instances")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "proof": proofBytes,
      "instances": instances
          .map((e) => e.instances().map((e) => e.toBytes()).toList())
          .toList(),
    };
  }
}

abstract mixin class BaseOrchardVerifier {
  FutureOr<bool> verifyOrchardProof(OrchardVerifyInputs args);
}
