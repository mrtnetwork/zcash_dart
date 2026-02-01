import 'package:zcash_dart/src/address/src/zcash_address.dart';

class TransactionBuilderUtils {
  static bool isValidOutputAddressParams(
      {ZCashAddress? zAddress, String? address, Object? protocolAddr}) {
    return [zAddress, address, protocolAddr].where((e) => e != null).length ==
        1;
  }
}
