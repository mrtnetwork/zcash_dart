import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetTaddressBalance
    extends ZCashWalletdRequest<WalletdTAddressBalance> {
  final WalletdTAddressList addressList;
  const ZWalletdRequestGetTaddressBalance(this.addressList);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressBalance";

  @override
  List<int> toBuffer() {
    return addressList.toBuffer();
  }

  @override
  WalletdTAddressBalance onResonse(List<int> result) {
    return WalletdTAddressBalance.deserialize(result);
  }
}
