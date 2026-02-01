import 'package:zcash_dart/src/exception/exception.dart';

class SaplingException extends DartZCashPluginException {
  const SaplingException(super.message, {super.details});

  static SaplingException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return SaplingException("Sapling operation failure during $operation",
        details: details);
  }
}
