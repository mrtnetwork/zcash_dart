import 'package:zcash_dart/src/exception/exception.dart';

class OrchardException extends DartZCashPluginException {
  const OrchardException(super.message, {super.details});
  static OrchardException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return OrchardException("Orchard operation failed during $operation",
        details: {...details ?? {}, "reason": reason});
  }
}
