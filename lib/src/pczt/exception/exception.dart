import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class PcztException extends BaseDartZcashPluginException {
  const PcztException(super.message, {super.details});
  static PcztException failed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return PcztException(
      "Pczt operation failed during $operation.",
      details: {"reason": reason, ...details ?? {}}.notNullValue,
    );
  }

  factory PcztException.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.pcztError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return PcztException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.pcztError;
}
