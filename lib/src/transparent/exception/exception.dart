import 'package:zcash_dart/src/exception/exception.dart';

class TransparentExceptoion extends DartZCashPluginException {
  const TransparentExceptoion(super.message, {super.details});
  static DartZCashPluginException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return TransparentExceptoion(
        "Transparent operation failure during $operation",
        details: details);
  }

  static DartZCashPluginException multisigFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return TransparentExceptoion(
        "Transparent multisig address generation failed.",
        details: details);
  }
}
