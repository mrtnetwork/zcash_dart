import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/block_processor.dart';
import 'package:zcash_dart/src/merkle/merkle.dart';
import 'package:zcash_dart/src/orchard/proof/types.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

import 'response.dart';

sealed class ZKRequest<RESPONE extends ZKResponse, T extends Object?>
    with CborTagSerializable {
  const ZKRequest();
  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zkRequest;
  T onResponse(RESPONE response);
}

class ZKRequestMerkleCreateContext
    extends ZKRequest<ZKResponseMerkleCreateContext, int> {
  final ChainMerkleState params;
  const ZKRequestMerkleCreateContext(this.params);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(0),
    CborTagSerializable.listFromDynamic([params.toCbor()]),
  ];

  @override
  int onResponse(ZKResponseMerkleCreateContext response) {
    return response.id;
  }
}

abstract class ZKRequestMerkle<RESPONE extends ZKResponse, T extends Object?>
    extends ZKRequest<RESPONE, T> {
  final int contextId;
  ZKRequestMerkle({required int contextId}) : contextId = contextId.asU32;
}

class ZKRequestMerkleUpdateSubtree
    extends ZKRequestMerkle<ZKResponseMerkleUpdateSubtreeResult, int> {
  final SubtreeRoots subtree;
  final ZcashProtocol protocol;
  ZKRequestMerkleUpdateSubtree({
    required super.contextId,
    required this.subtree,
    required this.protocol,
  }) : assert(protocol.sheilded, "Unsupported protocol.");
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(1),
    CborTagSerializable.listFromDynamic([
      contextId.toCbor(),
      protocol.value.toCbor(),
      subtree.toCbor(),
    ]),
  ];

  @override
  int onResponse(ZKResponseMerkleUpdateSubtreeResult response) {
    return response.index;
  }
}

class ZKRequestMerkleInsertChainState
    extends ZKRequestMerkle<ZKResponseOk, void> {
  final ChainState chainState;
  ZKRequestMerkleInsertChainState({
    required super.contextId,
    required this.chainState,
  });
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(2),
    CborTagSerializable.listFromDynamic([
      contextId.toCbor(),
      chainState.toCbor(),
    ]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

///SerializableMerkleInsertReport
class ZKRequestMerkleUpdateState
    extends
        ZKRequestMerkle<
          ZKResponseMerkleUpdateResult,
          ZKResponseMerkleUpdateResult
        > {
  final ScannedBlocksBundles scannedBlocks;
  ZKRequestMerkleUpdateState({
    required super.contextId,
    required this.scannedBlocks,
  });
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(3),
    CborTagSerializable.listFromDynamic([
      contextId.toCbor(),
      scannedBlocks.toCbor(),
    ]),
  ];

  @override
  ZKResponseMerkleUpdateResult onResponse(
    ZKResponseMerkleUpdateResult response,
  ) {
    return response;
  }
}

class ZKRequestMerkleMergeState extends ZKRequestMerkle<ZKResponseOk, void> {
  final SerializableMerkleInsertReport report;
  ZKRequestMerkleMergeState({required super.contextId, required this.report});
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(4),
    CborTagSerializable.listFromDynamic([contextId.toCbor(), report.toCbor()]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestMerkleGetContext
    extends
        ZKRequestMerkle<
          ZKResponseMerkleGetContextResult,
          ZKResponseMerkleGetContextResult
        > {
  ZKRequestMerkleGetContext({required super.contextId});
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(20),
    CborTagSerializable.listFromDynamic([contextId.toCbor()]),
  ];

  @override
  ZKResponseMerkleGetContextResult onResponse(
    ZKResponseMerkleGetContextResult response,
  ) {
    return response;
  }
}

class ZKRequestMerkleCreateWitness
    extends
        ZKRequestMerkle<
          ZKResponseMerkleCreateWitnessResult,
          SerializableWitnesses
        > {
  final CreateWitnessParams params;
  ZKRequestMerkleCreateWitness({
    required super.contextId,
    required this.params,
  });
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(21),
    CborTagSerializable.listFromDynamic([contextId.toCbor(), params.toCbor()]),
  ];

  @override
  SerializableWitnesses onResponse(
    ZKResponseMerkleCreateWitnessResult response,
  ) {
    return response.witnesses;
  }
}

class ZKRequestMerkleCloseContext extends ZKRequestMerkle<ZKResponseOk, void> {
  ZKRequestMerkleCloseContext({required super.contextId});
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(5),
    CborTagSerializable.listFromDynamic([contextId.toCbor()]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestSaplingHasSpendParams
    extends ZKRequest<ZKResponseSaplingHasParams, bool> {
  const ZKRequestSaplingHasSpendParams();
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(6),
    CborTagSerializable.listFromDynamic([]),
  ];

  @override
  bool onResponse(ZKResponseSaplingHasParams response) {
    return response.hasPrams;
  }
}

class ZKRequestSaplingHasOutputParams
    extends ZKRequest<ZKResponseSaplingHasParams, bool> {
  const ZKRequestSaplingHasOutputParams();
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(7),
    CborTagSerializable.listFromDynamic([]),
  ];

  @override
  bool onResponse(ZKResponseSaplingHasParams response) {
    return response.hasPrams;
  }
}

class ZKRequestSaplingSetupSpendParams extends ZKRequest<ZKResponseOk, void> {
  final List<int> bytes;
  const ZKRequestSaplingSetupSpendParams(this.bytes);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(8),
    CborTagSerializable.listFromDynamic([CborBytesValue(bytes)]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestSaplingSetupOutputParams extends ZKRequest<ZKResponseOk, void> {
  final List<int> bytes;
  const ZKRequestSaplingSetupOutputParams(this.bytes);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(9),
    CborTagSerializable.listFromDynamic([CborBytesValue(bytes)]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestSaplingCreateSpendProof
    extends ZKRequest<ZKResponseSaplingProof, GrothProofBytes> {
  final SaplingSpendParams params;
  const ZKRequestSaplingCreateSpendProof(this.params);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(10),
    CborTagSerializable.listFromDynamic([params.toCbor()]),
  ];

  @override
  GrothProofBytes onResponse(ZKResponseSaplingProof response) {
    return response.proof;
  }
}

class ZKRequestSaplingCreateOutputProof
    extends ZKRequest<ZKResponseSaplingProof, GrothProofBytes> {
  final SaplingOutputParams params;
  const ZKRequestSaplingCreateOutputProof(this.params);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(11),
    CborTagSerializable.listFromDynamic([params.toCbor()]),
  ];

  @override
  GrothProofBytes onResponse(ZKResponseSaplingProof response) {
    return response.proof;
  }
}

class ZKRequestSaplingVerifySpendProof
    extends ZKRequest<ZKResponseVerifyProof, bool> {
  final SaplingVerifyInputs inputs;
  ZKRequestSaplingVerifySpendProof(this.inputs)
    : assert(inputs.inputs.length == 7, "Invalid spend proof input");
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(12),
    CborTagSerializable.listFromDynamic([inputs.toCbor()]),
  ];

  @override
  bool onResponse(ZKResponseVerifyProof response) {
    return response.verify;
  }
}

class ZKRequestSaplingVerifyOutputProof
    extends ZKRequest<ZKResponseVerifyProof, bool> {
  final SaplingVerifyInputs inputs;
  ZKRequestSaplingVerifyOutputProof(this.inputs)
    : assert(inputs.inputs.length == 5, "Invalid output proof input.");
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(13),
    CborTagSerializable.listFromDynamic([inputs.toCbor()]),
  ];

  @override
  bool onResponse(ZKResponseVerifyProof response) {
    return response.verify;
  }
}

class ZKRequestOrchardCreateActionProof
    extends ZKRequest<ZKResponseOrchardActionProof, List<int>> {
  final OrchardProofParams params;
  const ZKRequestOrchardCreateActionProof(this.params);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(14),
    CborTagSerializable.listFromDynamic([params.toCbor()]),
  ];

  @override
  List<int> onResponse(ZKResponseOrchardActionProof response) {
    return response.proof;
  }
}

class ZKRequestOrchardVerifyActionProof
    extends ZKRequest<ZKResponseVerifyProof, bool> {
  final OrchardVerifyProofInputs params;
  const ZKRequestOrchardVerifyActionProof(this.params);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(15),
    CborTagSerializable.listFromDynamic([params.toCbor()]),
  ];

  @override
  bool onResponse(ZKResponseVerifyProof response) {
    return response.verify;
  }
}

class ZKRequestSaplingClearSpendParams extends ZKRequest<ZKResponseOk, void> {
  const ZKRequestSaplingClearSpendParams();
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(16),
    CborTagSerializable.listFromDynamic([]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestSaplingClearOutputParams extends ZKRequest<ZKResponseOk, void> {
  const ZKRequestSaplingClearOutputParams();
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(17),
    CborTagSerializable.listFromDynamic([]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestSaplingClearOrchardProvingKey
    extends ZKRequest<ZKResponseOk, void> {
  const ZKRequestSaplingClearOrchardProvingKey();
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(18),
    CborTagSerializable.listFromDynamic([]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestVersion extends ZKRequest<ZKResponseVersion, int> {
  const ZKRequestVersion();
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(19),
    CborTagSerializable.listFromDynamic([]),
  ];

  @override
  int onResponse(ZKResponseVersion response) {
    return response.version;
  }
}

class CreateWitnessParams with CborTagSerializable {
  final ZcashProtocol protocol;
  final int height;
  final List<int> positions;
  CreateWitnessParams({
    required this.protocol,
    required this.height,
    required this.positions,
  });

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.createWitnessParams;

  @override
  List<CborObject?> get serializationItems => [
    protocol.value.toCbor(),
    height.toCbor(),
    CborTagSerializable.listFromDynamic(
      positions.map((e) => CborSafeIntValue(e.toBigInt)).toList(),
    ),
  ];
}

class ZKRequestLogging extends ZKRequest<ZKResponseOk, void> {
  final bool enable;
  final ZKLibLogLevel level;
  const ZKRequestLogging({
    this.enable = true,
    this.level = ZKLibLogLevel.debug,
  });
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(22),
    CborTagSerializable.listFromDynamic([
      enable.toCbor(),
      level.value.toCbor(),
    ]),
  ];

  @override
  void onResponse(ZKResponseOk response) {}
}

class ZKRequestCommitmentShortDomain
    extends ZKRequest<ZKResponseBytes, List<int>> {
  final ZKCommitmentShortDomain domain;
  const ZKRequestCommitmentShortDomain(this.domain);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(23),
    CborTagSerializable.listFromDynamic([domain.toCbor()]),
  ];

  @override
  List<int> onResponse(ZKResponseBytes response) {
    return response.bytes;
  }
}

class ZKRequestCommitmentDomain extends ZKRequest<ZKResponseBytes, List<int>> {
  final ZKCommitmentDomain domain;
  const ZKRequestCommitmentDomain(this.domain);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(24),
    CborTagSerializable.listFromDynamic([domain.toCbor()]),
  ];

  @override
  List<int> onResponse(ZKResponseBytes response) {
    return response.bytes;
  }
}

class ZKRequestPseudoRando extends ZKRequest<ZKResponseBytes, List<int>> {
  final ZKPseudoRando args;
  const ZKRequestPseudoRando(this.args);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(25),
    CborTagSerializable.listFromDynamic([args.toCbor()]),
  ];

  @override
  List<int> onResponse(ZKResponseBytes response) {
    return response.bytes;
  }
}

class ZKRequestPedersenHash extends ZKRequest<ZKResponseBytes, List<int>> {
  final ZKPedersenHash args;
  const ZKRequestPedersenHash(this.args);
  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(26),
    CborTagSerializable.listFromDynamic([args.toCbor()]),
  ];

  @override
  List<int> onResponse(ZKResponseBytes response) {
    return response.bytes;
  }
}

class ZKCommitmentShortDomain with CborTagSerializable {
  final String domain;
  final List<bool> bits;
  final List<int> r;
  ZKCommitmentShortDomain({
    required List<int> r,
    required this.bits,
    required this.domain,
  }) : r =
           r
               .exc(
                 length: 32,
                 operation: "ZKCommitmentShortDomain",
                 reason: "Invalid r bytes length.",
               )
               .toImutableList;

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zkCommitmentShortDomain;

  @override
  List<CborObject?> get serializationItems => [
    domain.toCbor(),
    CborTagSerializable.listFromDynamic(bits.map((e) => e.toCbor()).toList()),
    r.toCborBytes(),
  ];
}

class ZKCommitmentDomain with CborTagSerializable {
  final String domain;
  final List<bool> bits;
  final List<int> r;
  ZKCommitmentDomain({
    required List<int> r,
    required this.bits,
    required this.domain,
  }) : r =
           r
               .exc(
                 length: 32,
                 operation: "ZKCommitmentDomain",
                 reason: "Invalid r bytes length.",
               )
               .toImutableList;

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zkCommitmentDomain;

  @override
  List<CborObject?> get serializationItems => [
    domain.toCbor(),
    CborTagSerializable.listFromDynamic(bits.map((e) => e.toCbor()).toList()),
    r.toCborBytes(),
  ];
}

class ZKPseudoRando with CborTagSerializable {
  final List<int> nk;
  final List<int> rho;
  ZKPseudoRando({required List<int> nk, required List<int> rho})
    : nk =
          nk
              .exc(
                length: 32,
                operation: "ZKPseudoRando",
                reason: "Invalid nk bytes length.",
              )
              .toImutableList,
      rho =
          rho
              .exc(
                length: 32,
                operation: "ZKPseudoRando",
                reason: "Invalid rho bytes length.",
              )
              .toImutableList;

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zkPseudoRando;

  @override
  List<CborObject?> get serializationItems => [
    nk.toCborBytes(),
    rho.toCborBytes(),
  ];
}

class ZKPedersenHash with CborTagSerializable {
  final List<bool> bits;
  final int? merkleTreeSize;
  ZKPedersenHash({required List<bool> bits, this.merkleTreeSize})
    : bits = bits.immutable;

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zkPedersenHash;

  @override
  List<CborObject?> get serializationItems => [
    merkleTreeSize?.toCbor(),
    CborTagSerializable.listFromDynamic(bits.map((e) => e.toCbor()).toList()),
  ];
}
