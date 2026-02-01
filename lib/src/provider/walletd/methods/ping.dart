import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestPing extends ZCashWalletdRequest<WalletdPingResponse> {
  final WalletdPingDuration duration;
  const ZWalletdRequestPing(this.duration);
  @override
  String get method => "/cash.z.wallet.sdk.rpc.CompactTxStreamer/Ping";

  @override
  List<int> toBuffer() {
    return duration.toBuffer();
  }

  @override
  WalletdPingResponse onResonse(List<int> result) {
    return WalletdPingResponse.deserialize(result);
  }
}
