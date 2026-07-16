import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class OrchardException extends BaseDartZcashPluginException {
  const OrchardException(super.message, {super.details});

  static OrchardException operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return OrchardException(
      "Orchard operation failed during $operation",
      details: {...details ?? {}, "reason": reason},
    );
  }

  factory OrchardException.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.orchardError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return OrchardException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.orchardError;
}
