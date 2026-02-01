import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/pczt/pczt.dart';

class OrchardPcztException extends PcztException implements OrchardException {
  const OrchardPcztException(super.message, {super.details});
  static OrchardPcztException operationFailed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return OrchardPcztException(
        "Orchard Pczt operation failed during $operation",
        details: {...details ?? {}, "reason": reason});
  }
}
