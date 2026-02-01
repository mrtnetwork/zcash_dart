import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetSubtreeRoots
    extends ZCashWalletdRequest<WalletdSubtreeRoot> {
  final GetSubtreeRootsArg args;
  const ZWalletdRequestGetSubtreeRoots(this.args);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetSubtreeRoots";

  @override
  List<int> toBuffer() {
    return args.toBuffer();
  }

  @override
  WalletdSubtreeRoot onResonse(List<int> result) {
    return WalletdSubtreeRoot.deserialize(result);
  }
}
