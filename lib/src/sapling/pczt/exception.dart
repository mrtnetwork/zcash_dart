import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/pczt/pczt.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class SaplingPcztException extends PcztException implements SaplingException {
  const SaplingPcztException(super.message, {super.details});
  static SaplingPcztException operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return SaplingPcztException(
      "Sapling Pczt failure during $operation",
      details: {"reason": reason, ...details ?? {}},
    );
  }

  factory SaplingPcztException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.saplingPcztError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return SaplingPcztException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.saplingPcztError;
}
