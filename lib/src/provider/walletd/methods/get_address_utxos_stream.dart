import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetAddressUtxosStream
    extends ZCashWalletdRequest<WalletdGetAddressUtxosReply> {
  final WalletdGetAddressUtxosArg args;
  const ZWalletdRequestGetAddressUtxosStream(this.args);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetAddressUtxosStream";

  @override
  List<int> toBuffer() {
    return args.toBuffer();
  }

  @override
  WalletdGetAddressUtxosReply onResonse(List<int> result) {
    return WalletdGetAddressUtxosReply.deserialize(result);
  }
}
