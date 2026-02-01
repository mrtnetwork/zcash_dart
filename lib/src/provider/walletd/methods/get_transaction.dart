import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetTransaction
    extends ZCashWalletdRequest<WalletdRawTransaction> {
  final WalletdTxFilter filter;
  const ZWalletdRequestGetTransaction(this.filter);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTransaction";

  @override
  List<int> toBuffer() {
    return filter.toBuffer();
  }

  @override
  WalletdRawTransaction onResonse(List<int> result) {
    return WalletdRawTransaction.deserialize(result);
  }
}
