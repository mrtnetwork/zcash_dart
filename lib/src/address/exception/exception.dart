import 'package:blockchain_utils/bip/zcash/src/types.dart';
import 'package:zcash_dart/src/exception/exception.dart';

class ZCashAddressException extends DartZCashPluginException {
  const ZCashAddressException(super.message, {super.details});
  static ZCashAddressException get invalidUnifiedReceivers =>
      ZCashAddressException("Invalid unified address receivers.");
  static ZCashAddressException mismatchNetwork(
          {required ZCashNetwork network, required ZCashNetwork expected}) =>
      ZCashAddressException(
          "Network mismatch: address belongs to a different network.",
          details: {"network": network.name, "expected": expected.name});
}
