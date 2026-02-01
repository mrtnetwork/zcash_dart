import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/service/service.dart';

class ZCashWalletdProvider {
  final ZCashWalletdServiceProvider rpc;

  ZCashWalletdProvider(this.rpc);
  Future<List<int>> requestBuffer<RESULT>(ZCashWalletdRequest<RESULT> request,
      {Duration? timeout}) async {
    final r = await rpc.doRequest(request.buildRequest(), timeout: timeout);
    return r;
  }

  Future<RESULT> request<RESULT>(ZCashWalletdRequest<RESULT> request,
      {Duration? timeout}) async {
    final r = await rpc.doRequest(request.buildRequest(), timeout: timeout);
    return request.onResonse(r);
  }

  Stream<RESULT> requestStream<RESULT>(ZCashWalletdRequest<RESULT> request,
      {Duration? timeout}) {
    final r = rpc.doRequestStream(request.buildRequest(), timeout: timeout);
    return r.map((e) => request.onResonse(e));
  }

  Future<List<RESULT>> requestOnce<RESULT>(ZCashWalletdRequest<RESULT> request,
      {Duration? timeout}) async {
    final r = requestStream<RESULT>(request, timeout: timeout);
    return await r.toList();
  }
}
