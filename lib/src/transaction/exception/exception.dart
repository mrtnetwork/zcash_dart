import 'package:zcash_dart/src/exception/exception.dart';

class ZTransactionSerializationError extends DartZCashPluginException {
  const ZTransactionSerializationError(super.message, {super.details});
  static const ZTransactionSerializationError
      unxpectedErrorDuringDeserialization = ZTransactionSerializationError(
          "Unexpected error while serialization transaction");
  static ZTransactionSerializationError serializationFailed(String operation) =>
      ZTransactionSerializationError(
          "Serialization failed: missing or unknown parameters for '$operation'.");
}
