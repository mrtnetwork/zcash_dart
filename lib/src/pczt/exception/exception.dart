import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/exception.dart';

class PcztException extends DartZCashPluginException {
  const PcztException(super.message, {super.details});
  static DartZCashPluginException failed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return PcztException("Pczt operation failed during $operation.",
        details: {"reason": reason, ...details ?? {}}.notNullValue);
  }
}
