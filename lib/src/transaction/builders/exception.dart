import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/exception.dart';

class TransactionBuilderException extends DartZCashPluginException {
  const TransactionBuilderException(super.message, {super.details});
  static TransactionBuilderException failed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return TransactionBuilderException(
        "Transaction builder operation failed during $operation",
        details: {...details ?? {}, "reason": reason}.notNullValue);
  }
}
