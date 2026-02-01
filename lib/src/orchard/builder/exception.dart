import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/transaction/builders/exception.dart';

class OrchardBuilderException extends OrchardException
    implements TransactionBuilderException {
  const OrchardBuilderException(super.message, {super.details});

  static OrchardBuilderException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return OrchardBuilderException(
        "Orchard builder operation failed during $operation",
        details: {...details ?? {}, "reason": reason});
  }
}
