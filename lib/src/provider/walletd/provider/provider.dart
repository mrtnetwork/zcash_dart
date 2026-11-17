import 'package:blockchain_utils/service/models/params.dart';
import 'package:blockchain_utils/utils/json/extension/json.dart';
import 'package:zcash_dart/src/provider/walletd/core/request.dart';

class ZcashWalletdProvider<SERVICE extends IServiceProvider>
    implements
        IGrpcProvider<
          SERVICE,
          ZcashWalletdRequestDetails,
          ZcashWalletdRequestDetails
        > {
  @override
  final SERVICE service;

  ZcashWalletdProvider(this.service);

  @override
  Future<RESULT> request<RESULT, SERVICERESPONSE>(
    IServiceRequest<RESULT, SERVICERESPONSE, ZcashWalletdRequestDetails>
    request, {
    Duration? timeout,
  }) async {
    final r = await requestDynamic<RESULT, SERVICERESPONSE>(
      request,
      timeout: timeout,
    );
    return request.onResponse(r);
  }

  @override
  Future<SERVICERESPONSE> requestDynamic<RESULT, SERVICERESPONSE>(
    IServiceRequest<RESULT, SERVICERESPONSE, ZcashWalletdRequestDetails>
    request, {
    Duration? timeout,
  }) async {
    final params = await request.buildRequest(0);
    final response = await service.doGrpcRequest(params, timeout: timeout);
    return JsonParser.valueAs<SERVICERESPONSE>(response);
  }

  @override
  Stream<RESULT> requestStream<RESULT>(
    IGRPCServiceRequest<RESULT, ZcashWalletdRequestDetails> request, {
    Duration? timeout,
  }) async* {
    final r = await request.buildRequest(0);
    final result = service.doGrpcRequestStream(r, timeout: timeout);
    yield* result.map((e) => request.onResponse(e));
  }

  @override
  Future<List<RESULT>> requestOnce<RESULT>(
    IGRPCServiceRequest<RESULT, ZcashWalletdRequestDetails> request, {
    Duration? timeout,
  }) async {
    final result = requestStream<RESULT>(request, timeout: timeout);
    return await result.toList();
  }

  @override
  Future<Stream<RESULT>> requestStreamAsync<RESULT>(
    IGRPCServiceRequest<RESULT, ZcashWalletdRequestDetails> request, {
    Duration? timeout,
  }) async {
    final result = await service.doGrpcRequestStreamAsync(
      await request.buildRequest(0),
      timeout: timeout,
    );
    return result.map((e) => request.onResponse(e));
  }

  @override
  Future<List<RESULT>> requestOnceAsync<RESULT>(
    IGRPCServiceRequest<RESULT, ZcashWalletdRequestDetails> request, {
    Duration? timeout,
  }) async {
    final result = await requestStreamAsync<RESULT>(request, timeout: timeout);
    return await result.toList();
  }
}
