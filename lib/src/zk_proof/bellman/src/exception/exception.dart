import 'package:zcash_dart/src/exception/exception.dart';

class BellmanException extends DartZCashPluginException {
  const BellmanException(super.message, {super.details});

  static BellmanException operationFailed(String operation, {String? reason}) =>
      BellmanException("$operation operation failed.",
          details: {"reason": reason});
}
