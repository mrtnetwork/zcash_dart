import 'package:zcash_dart/src/transaction/builders/exception.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';

class TransparentBuilderException extends TransparentExceptoion
    implements TransactionBuilderException {
  const TransparentBuilderException(super.message, {super.details});

  static TransparentBuilderException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return TransparentBuilderException(
        "Transparent builder operation failed during $operation",
        details: {...details ?? {}, "reason": reason});
  }
}
