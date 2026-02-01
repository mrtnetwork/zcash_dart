import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetTreeState
    extends ZCashWalletdRequest<WalletdTreeState> {
  final WalletdBlockId blockId;
  const ZWalletdRequestGetTreeState(this.blockId);
  @override
  String get method => "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTreeState";

  @override
  List<int> toBuffer() {
    return blockId.toBuffer();
  }

  @override
  WalletdTreeState onResonse(List<int> result) {
    return WalletdTreeState.deserialize(result);
  }
}
