import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetLatestBlock
    extends ZCashWalletdRequest<WalletdBlockId> {
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock";

  @override
  List<int> toBuffer() {
    return [];
  }

  @override
  WalletdBlockId onResonse(List<int> result) {
    return WalletdBlockId.deserialize(result);
  }
}
