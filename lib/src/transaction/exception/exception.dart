import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class ZTransactionSerializationError extends BaseDartZcashPluginException {
  const ZTransactionSerializationError(super.message, {super.details});
  static const ZTransactionSerializationError
  unxpectedErrorDuringDeserialization = ZTransactionSerializationError(
    "Unexpected error while serialization transaction",
  );
  static ZTransactionSerializationError serializationFailed(String operation) =>
      ZTransactionSerializationError(
        "Serialization failed: missing or unknown parameters for '$operation'.",
      );

  factory ZTransactionSerializationError.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.transactionSerializationError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return ZTransactionSerializationError(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.transactionSerializationError;
}
