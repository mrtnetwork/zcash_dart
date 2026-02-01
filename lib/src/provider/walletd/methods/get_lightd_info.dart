import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';

class ZWalletdRequestGetLightdInfo extends ZCashWalletdRequest<LightdInfo> {
  const ZWalletdRequestGetLightdInfo();
  @override
  String get method => "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo";

  @override
  List<int> toBuffer() {
    return [];
  }

  @override
  LightdInfo onResonse(List<int> result) {
    return LightdInfo.deserialize(result);
  }
}
