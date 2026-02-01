import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/exception.dart';

class ZCashBlockScannerException extends DartZCashPluginException {
  const ZCashBlockScannerException(super.message, {super.details});
  static ZCashBlockScannerException failed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return ZCashBlockScannerException("Block scan failed during $operation",
        details: {"reason": reason, ...details ?? {}}.notNullValue);
  }

  static ZCashBlockScannerException invalidCompact(String elem,
      {Map<String, dynamic>? details, String? reason}) {
    return ZCashBlockScannerException("Invalid compact $elem object.",
        details: {"reason": reason, ...details ?? {}}.notNullValue);
  }
}
