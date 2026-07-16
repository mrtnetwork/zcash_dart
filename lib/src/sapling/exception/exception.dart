import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class SaplingException extends BaseDartZcashPluginException {
  const SaplingException(super.message, {super.details});

  static SaplingException operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return SaplingException(
      "Sapling operation failure during $operation",
      details: details,
    );
  }

  factory SaplingException.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.saplingError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return SaplingException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.saplingError;
}
