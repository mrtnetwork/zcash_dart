import 'package:zcash_dart/src/exception/exception.dart';

class PedersenHashException extends DartZCashPluginException {
  const PedersenHashException(super.message, {super.details});
  static PedersenHashException failed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return PedersenHashException("Pedersen operation failed during $operation.",
        details: {...details ?? {}, "reason": reason});
  }
}
