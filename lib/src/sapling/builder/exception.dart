import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/transaction/builders/exception.dart';

class SaplingBuilderException extends SaplingException
    implements TransactionBuilderException {
  const SaplingBuilderException(super.message, {super.details});

  static SaplingBuilderException operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return SaplingBuilderException(
      "Sapling builder operation failed during $operation",
      details: {...details ?? {}, "reason": reason},
    );
  }

  factory SaplingBuilderException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.saplingBuilderError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return SaplingBuilderException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.saplingBuilderError;
}
