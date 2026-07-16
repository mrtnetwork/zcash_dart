import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class TransactionBuilderException extends BaseDartZcashPluginException {
  const TransactionBuilderException(super.message, {super.details});
  static TransactionBuilderException failed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return TransactionBuilderException(
      "Transaction builder operation failed during $operation",
      details: {...details ?? {}, "reason": reason}.notNullValue,
    );
  }

  factory TransactionBuilderException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.transactionError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return TransactionBuilderException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.transactionError;
}
