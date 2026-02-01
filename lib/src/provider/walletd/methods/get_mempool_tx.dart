import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetMempoolTx
    extends ZCashWalletdRequest<WalletdCompactTx> {
  final WalletdTxExclude exclude;
  const ZWalletdRequestGetMempoolTx(this.exclude);
  @override
  String get method => "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetMempoolTx";

  @override
  List<int> toBuffer() {
    return exclude.toBuffer();
  }

  @override
  WalletdCompactTx onResonse(List<int> result) {
    return WalletdCompactTx.deserialize(result);
  }
}
