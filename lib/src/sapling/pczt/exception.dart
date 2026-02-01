import 'package:zcash_dart/src/pczt/pczt.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';

class SaplingPcztException extends PcztException implements SaplingException {
  const SaplingPcztException(super.message, {super.details});
  static SaplingPcztException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return SaplingPcztException("Sapling Pczt failure during $operation",
        details: {"reason": reason, ...details ?? {}});
  }
}
