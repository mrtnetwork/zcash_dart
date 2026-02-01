import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetTaddressBalanceStream
    extends ZCashWalletdRequest<WalletdTAddressBalance> {
  final WalletdTAddress address;
  const ZWalletdRequestGetTaddressBalanceStream(this.address);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressBalanceStream";

  @override
  List<int> toBuffer() {
    return address.toBuffer();
  }

  @override
  WalletdTAddressBalance onResonse(List<int> result) {
    return WalletdTAddressBalance.deserialize(result);
  }
}
