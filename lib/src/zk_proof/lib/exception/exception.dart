import 'package:blockchain_utils/helper/extensions/extensions.dart';
import 'package:zcash_dart/src/exception/exception.dart';

class ZKLibException extends DartZCashPluginException {
  const ZKLibException(super.message, {super.details});

  static ZKLibException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return ZKLibException("Operation failure during $operation",
        details: {"reason": reason, ...details ?? {}}.notNullValue);
  }
}
