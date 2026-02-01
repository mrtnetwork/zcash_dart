import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetTaddressTransactions
    extends ZCashWalletdRequest<WalletdRawTransaction> {
  final TransparentAddressBlockFilter filter;
  const ZWalletdRequestGetTaddressTransactions(this.filter);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressTransactions";

  @override
  List<int> toBuffer() {
    return filter.toBuffer();
  }

  @override
  WalletdRawTransaction onResonse(List<int> result) {
    return WalletdRawTransaction.deserialize(result);
  }
}
