import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetLatestTreeState
    extends ZCashWalletdRequest<WalletdTreeState> {
  const ZWalletdRequestGetLatestTreeState();
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestTreeState";

  @override
  List<int> toBuffer() {
    return [];
  }

  @override
  WalletdTreeState onResonse(List<int> result) {
    return WalletdTreeState.deserialize(result);
  }
}
