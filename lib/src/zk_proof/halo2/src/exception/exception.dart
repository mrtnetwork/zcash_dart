import 'package:zcash_dart/src/exception/exception.dart';

class Halo2Exception extends DartZCashPluginException {
  const Halo2Exception(super.message, {super.details});
  static DartZCashPluginException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return Halo2Exception("$operation operation failed.",
        details: {"operation": operation, ...details ?? {}});
  }

  // static  Halo2Exception get operationNotSupported =>
  //     Halo2Exception("Operation not supported.");
}
