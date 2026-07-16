import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/pczt/pczt.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class OrchardPcztException extends PcztException implements OrchardException {
  const OrchardPcztException(super.message, {super.details});
  static OrchardPcztException operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return OrchardPcztException(
      "Orchard Pczt operation failed during $operation",
      details: {...details ?? {}, "reason": reason},
    );
  }

  factory OrchardPcztException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.orchardPcztError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return OrchardPcztException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.orchardPcztError;
}
