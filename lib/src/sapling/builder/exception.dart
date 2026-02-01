import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/transaction/builders/exception.dart';

class SaplingBuilderException extends SaplingException
    implements TransactionBuilderException {
  const SaplingBuilderException(super.message, {super.details});

  static SaplingBuilderException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return SaplingBuilderException(
        "Sapling builder operation failed during $operation",
        details: {...details ?? {}, "reason": reason});
  }
}
