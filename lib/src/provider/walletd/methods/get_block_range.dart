import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetBlockRange
    extends ZCashWalletdRequest<WalletdCompactBlock> {
  final WalletdBlockRange range;
  const ZWalletdRequestGetBlockRange(this.range);
  @override
  String get method => "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockRange";

  @override
  List<int> toBuffer() {
    return range.toBuffer();
  }

  @override
  WalletdCompactBlock onResonse(List<int> result) {
    return WalletdCompactBlock.deserialize(result);
  }
}
