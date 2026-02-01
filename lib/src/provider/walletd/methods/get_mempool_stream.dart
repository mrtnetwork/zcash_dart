import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetMempoolStream
    extends ZCashWalletdRequest<WalletdRawTransaction> {
  const ZWalletdRequestGetMempoolStream();
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetMempoolStream";

  @override
  List<int> toBuffer() {
    return [];
  }

  @override
  WalletdRawTransaction onResonse(List<int> result) {
    return WalletdRawTransaction.deserialize(result);
  }
}
