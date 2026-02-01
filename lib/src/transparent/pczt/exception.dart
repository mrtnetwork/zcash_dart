import 'package:zcash_dart/src/pczt/pczt.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';

class TransparentPcztException extends PcztException
    implements TransparentExceptoion {
  const TransparentPcztException(super.message, {super.details});
  static TransparentPcztException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return TransparentPcztException(
        "Transparent Pczt failure during $operation",
        details: {...details ?? {}, "reason": reason});
  }
}
