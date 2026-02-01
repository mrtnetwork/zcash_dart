import 'package:zcash_dart/src/exception/exception.dart';

class WalletdException extends DartZCashPluginException {
  const WalletdException(super.message, {super.details});

  static DartZCashPluginException failed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return WalletdException("Opearion failed during $operation",
        details: details);
  }
}
