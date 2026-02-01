import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetBlock extends ZCashWalletdRequest<WalletdCompactBlock> {
  final WalletdBlockId blockId;
  const ZWalletdRequestGetBlock(this.blockId);
  @override
  String get method => "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlock";

  @override
  List<int> toBuffer() {
    return blockId.toBuffer();
  }

  @override
  WalletdCompactBlock onResonse(List<int> result) {
    return WalletdCompactBlock.deserialize(result);
  }
}
