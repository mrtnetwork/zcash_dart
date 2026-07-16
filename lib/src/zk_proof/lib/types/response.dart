import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/builder/types.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

enum ZKResponseKind {
  error(0),
  ok(1),
  saplingHasParams(2),
  saplingProof(3),
  verifyProof(4),
  orchardActionProof(5),
  version(6),
  merkleCreateContext(7),
  merkleUpdateResult(8),
  merkleUpdateSubtreeResult(9),
  merkleGetContextResult(10),
  merkleCreateWitnessResult(11),
  bytes(12);

  final int value;
  const ZKResponseKind(this.value);

  static ZKResponseKind fromValue(int? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ItemNotFoundException(name: "ZKResponseKind"),
    );
  }
}

sealed class ZKResponse with CborTagSerializable {
  const ZKResponse();
  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zkResponse;
  factory ZKResponse.deserialize({List<int>? bytes, CborObject? object}) {
    final decode = CborTagSerializable.decodeTaggedValueWithInfo(
      expectedTags: [ZcashSerializationIdentifier.zkResponse],
      cborBytes: bytes,
      cborObject: object,
    );
    final type = ZKResponseKind.fromValue(decode.values.rawValueAt(0));
    return switch (type) {
      ZKResponseKind.error => ZKResponseError._deserialize(object: decode.tag),
      ZKResponseKind.ok => ZKResponseOk._deserialize(object: decode.tag),
      ZKResponseKind.saplingHasParams =>
        ZKResponseSaplingHasParams._deserialize(object: decode.tag),
      ZKResponseKind.saplingProof => ZKResponseSaplingProof._deserialize(
        object: decode.tag,
      ),
      ZKResponseKind.verifyProof => ZKResponseVerifyProof._deserialize(
        object: decode.tag,
      ),
      ZKResponseKind.orchardActionProof =>
        ZKResponseOrchardActionProof._deserialize(object: decode.tag),
      ZKResponseKind.version => ZKResponseVersion._deserialize(
        object: decode.tag,
      ),
      ZKResponseKind.merkleCreateContext =>
        ZKResponseMerkleCreateContext._deserialize(object: decode.tag),
      ZKResponseKind.merkleUpdateResult =>
        ZKResponseMerkleUpdateResult._deserialize(object: decode.tag),
      ZKResponseKind.merkleUpdateSubtreeResult =>
        ZKResponseMerkleUpdateSubtreeResult._deserialize(object: decode.tag),
      ZKResponseKind.merkleGetContextResult =>
        ZKResponseMerkleGetContextResult._deserialize(object: decode.tag),
      ZKResponseKind.merkleCreateWitnessResult =>
        ZKResponseMerkleCreateWitnessResult._deserialize(object: decode.tag),
      ZKResponseKind.bytes => ZKResponseBytes._deserialize(object: decode.tag),
    };
  }

  T cast<T extends ZKResponse>() {
    if (this is! T) {
      throw CastFailedException<T>();
    }
    return this as T;
  }
}

class ZKResponseError extends ZKResponse {
  final ZKLibResponseCode code;
  final String message;
  const ZKResponseError({required this.code, required this.message});
  factory ZKResponseError._deserialize({List<int>? bytes, CborObject? object}) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseError(
      code: ZKLibResponseCode.fromCode(values.rawValueAt(0)),
      message: values.rawValueAt(1),
    );
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.error.value),
    CborTagSerializable.listFromDynamic([code.code.toCbor(), message.toCbor()]),
  ];
}

class ZKResponseOk extends ZKResponse {
  const ZKResponseOk();
  factory ZKResponseOk._deserialize({List<int>? bytes, CborObject? object}) {
    CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    return ZKResponseOk();
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.ok.value),
    CborTagSerializable.listFromDynamic([]),
  ];
}

class ZKResponseSaplingHasParams extends ZKResponse {
  final bool hasPrams;
  const ZKResponseSaplingHasParams(this.hasPrams);
  factory ZKResponseSaplingHasParams._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseSaplingHasParams(values.rawValueAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.saplingHasParams.value),
    CborTagSerializable.listFromDynamic([hasPrams.toCbor()]),
  ];
}

class ZKResponseSaplingProof extends ZKResponse {
  final GrothProofBytes proof;
  const ZKResponseSaplingProof(this.proof);
  factory ZKResponseSaplingProof._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseSaplingProof(GrothProofBytes(values.rawValueAt(0)));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.saplingProof.value),
    CborTagSerializable.listFromDynamic([CborBytesValue(proof.inner)]),
  ];
}

class ZKResponseVerifyProof extends ZKResponse {
  final bool verify;
  const ZKResponseVerifyProof(this.verify);
  factory ZKResponseVerifyProof._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseVerifyProof(values.rawValueAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.verifyProof.value),
    CborTagSerializable.listFromDynamic([verify.toCbor()]),
  ];
}

class ZKResponseOrchardActionProof extends ZKResponse {
  final List<int> proof;
  ZKResponseOrchardActionProof(List<int> proof)
    : proof = proof.asImmutableBytes;
  factory ZKResponseOrchardActionProof._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseOrchardActionProof(values.rawValueAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.orchardActionProof.value),
    CborTagSerializable.listFromDynamic([CborBytesValue(proof)]),
  ];
}

class ZKResponseVersion extends ZKResponse {
  final int version;
  ZKResponseVersion(this.version);
  factory ZKResponseVersion._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseVersion(values.rawValueAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.version.value),
    CborTagSerializable.listFromDynamic([version.toCbor()]),
  ];
}

class ZKResponseMerkleCreateContext extends ZKResponse {
  final int id;
  ZKResponseMerkleCreateContext(this.id);
  factory ZKResponseMerkleCreateContext._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseMerkleCreateContext(values.rawValueAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.merkleCreateContext.value),
    CborTagSerializable.listFromDynamic([id.toCbor()]),
  ];
}

class ZKResponseMerkleUpdateResult extends ZKResponse {
  final CborTagValue encodedReport;
  ZKResponseMerkleUpdateResult._(this.encodedReport);
  ZKResponseMerkleUpdateResult(SerializableMerkleInsertReport report)
    : encodedReport = report.toCbor();
  factory ZKResponseMerkleUpdateResult._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseMerkleUpdateResult._(values.objectAt(0));
  }
  SerializableMerkleInsertReport toReport(ZcashCryptoContext context) =>
      SerializableMerkleInsertReport.deserialize(
        orchardHashable: context.orchardHashable(),
        saplingHashable: context.saplingHashable(),
        object: encodedReport,
      );

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.merkleUpdateResult.value),
    CborTagSerializable.listFromDynamic([encodedReport]),
  ];
}

class ZKResponseMerkleUpdateSubtreeResult extends ZKResponse {
  final int index;
  ZKResponseMerkleUpdateSubtreeResult(this.index);
  factory ZKResponseMerkleUpdateSubtreeResult._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseMerkleUpdateSubtreeResult(values.rawValueAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.merkleUpdateSubtreeResult.value),
    CborTagSerializable.listFromDynamic([index.toCbor()]),
  ];
}

class ZKResponseMerkleGetContextResult extends ZKResponse {
  final CborTagValue encodedContext;
  ZKResponseMerkleGetContextResult._(this.encodedContext);
  ZKResponseMerkleGetContextResult(ChainMerkleState context)
    : encodedContext = context.toCbor();
  factory ZKResponseMerkleGetContextResult._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseMerkleGetContextResult._(values.objectAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.merkleUpdateSubtreeResult.value),
    CborTagSerializable.listFromDynamic([encodedContext]),
  ];
  ChainMerkleState toContext(ZcashCryptoContext context) =>
      ChainMerkleState.deserialize(
        orchardHashable: context.orchardHashable(),
        saplingHashable: context.saplingHashable(),
        object: encodedContext,
      );
}

class ZKResponseMerkleCreateWitnessResult extends ZKResponse {
  final SerializableWitnesses witnesses;
  ZKResponseMerkleCreateWitnessResult(this.witnesses);
  factory ZKResponseMerkleCreateWitnessResult._deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseMerkleCreateWitnessResult(
      SerializableWitnesses.deserialize(object: values.objectAt(0)),
    );
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.merkleCreateWitnessResult.value),
    CborTagSerializable.listFromDynamic([witnesses.toCbor()]),
  ];
}

class SerializableMerklePath with CborTagSerializable {
  final List<List<int>> paths;
  final int position;
  factory SerializableMerklePath.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.serializableMerklePath,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableMerklePath(
      paths: values.listAt<CborBytesValue>(0).map((e) => e.value).toList(),
      position: values.rawValueAt(1),
    );
  }
  SerializableMerklePath({
    required List<List<int>> paths,
    required this.position,
  }) : paths =
           paths
               .exc(
                 length: 32,
                 operation: "SerializableMerklePath",
                 reason: "Invalid merkle path elements length.",
               )
               .toImutableList;

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serializableMerklePath;

  @override
  List<CborObject?> get serializationItems => [
    CborTagSerializable.listFromDynamic(
      paths.map((e) => CborBytesValue(e)).toList(),
    ),
    position.toCbor(),
  ];
}

class SerializableWitnesses with CborTagSerializable {
  final List<int>? anchor;
  final List<SerializableMerklePath> merkles;
  factory SerializableWitnesses.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.serializableWitnesses,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableWitnesses(
      anchor: values.rawValueAt(0),
      merkles:
          values
              .listAt<CborTagValue>(1)
              .map((e) => SerializableMerklePath.deserialize(object: e))
              .toList(),
    );
  }
  SerializableWitnesses({
    required List<SerializableMerklePath> merkles,
    List<int>? anchor,
  }) : merkles = merkles.toImutableList,
       anchor = anchor?.asImmutableBytes;

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serializableWitnesses;

  @override
  List<CborObject?> get serializationItems => [
    anchor?.toCborBytes(),
    CborTagSerializable.listFromDynamic(
      merkles.map((e) => e.toCbor()).toList(),
    ),
  ];
}

class ZKResponseBytes extends ZKResponse {
  final List<int> bytes;
  ZKResponseBytes(List<int> bytes) : bytes = bytes.asImmutableBytes;
  factory ZKResponseBytes._deserialize({List<int>? bytes, CborObject? object}) {
    final decode = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zkResponse,
      cborBytes: bytes,
      cborObject: object,
    );
    final values = decode.objectAt<CborListValue>(1);
    return ZKResponseBytes(values.rawValueAt(0));
  }

  @override
  List<CborObject?> get serializationItems => [
    CborIntValue(ZKResponseKind.bytes.value),
    CborTagSerializable.listFromDynamic([bytes.toCborBytes()]),
  ];
}
