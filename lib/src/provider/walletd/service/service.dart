import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/provider/walletd/core/request.dart';

mixin ZcashWalletdServiceProvider
    implements
        IServiceProvider<BaseServiceRequestParams, ZcashWalletdRequestDetails> {
  @override
  Future<List<int>> doGrpcRequest(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  });

  @override
  Stream<List<int>> doGrpcRequestStream(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  });

  @override
  Future<Stream<List<int>>> doGrpcRequestStreamAsync(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  });

  @override
  Future<BaseServiceResponse> doRequest(
    BaseServiceRequestParams params, {
    Duration? timeout,
  }) {
    throw BuError(
      DefaultErrorType.unsupported,
      "This service only supports gRPC requests.",
    );
  }

  @override
  Future<BaseServiceSubscribtionResponse> doSubscribtionRequest({
    required BaseServiceRequestParams params,
    required BaseServiceSubscribtionRequest<
      dynamic,
      dynamic,
      BaseSubscribtionEvent<dynamic>,
      BaseServiceRequestParams
    >
    request,
    Duration? timeout,
  }) {
    throw BuError(
      DefaultErrorType.unsupported,
      "Subscribtion requests are not supported by this service.",
    );
  }
}
