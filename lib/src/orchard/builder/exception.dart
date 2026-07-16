import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/transaction/builders/exception.dart';

class OrchardBuilderException extends OrchardException
    implements TransactionBuilderException {
  const OrchardBuilderException(super.message, {super.details});
  factory OrchardBuilderException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.orchardBuilderError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return OrchardBuilderException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }
  static OrchardBuilderException operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return OrchardBuilderException(
      "Orchard builder operation failed during $operation",
      details: {...details ?? {}, "reason": reason},
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.orchardBuilderError;
}
