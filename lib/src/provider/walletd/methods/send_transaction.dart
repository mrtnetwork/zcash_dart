import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestSendTransaction
    extends ZCashWalletdRequest<WalletdSendResponse> {
  final WalletdRawTransaction transaction;
  const ZWalletdRequestSendTransaction(this.transaction);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/SendTransaction";

  @override
  List<int> toBuffer() {
    return transaction.toBuffer();
  }

  @override
  WalletdSendResponse onResonse(List<int> result) {
    return WalletdSendResponse.deserialize(result);
  }
}
