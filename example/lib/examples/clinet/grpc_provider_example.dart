import 'dart:async';

import 'package:zcash_dart/zcash.dart';
import 'package:grpc/grpc.dart';

ZCashWalletdProvider getClient({String url = "....", int port = 443}) {
  final channel = ClientChannel(
    url,
    port: port,
    options: const ChannelOptions(credentials: ChannelCredentials.secure()),
  );

  final client = WalletdGrpcClient(channel);
  return ZCashWalletdProvider(client);
}

/// gRPC client implementation for Zcash `walletd`.
///
/// This client:
/// - Wraps a gRPC `ClientChannel`
/// - Dynamically builds gRPC methods at runtime
/// - Sends raw binary requests and receives raw binary responses
/// - Implements both unary and streaming walletd calls
class WalletdGrpcClient extends Client with ZCashWalletdServiceProvider {
  WalletdGrpcClient(super.channel);

  /// Builds a gRPC method dynamically from request metadata.
  ///
  /// walletd exposes many endpoints; instead of generating
  /// static stubs, we serialize requests as raw bytes and
  /// route them by method name.
  static ClientMethod<ZCashWalletdRequestDetails, List<int>> buildMethod(
    ZCashWalletdRequestDetails params,
  ) {
    return ClientMethod<ZCashWalletdRequestDetails, List<int>>(
      /// Full gRPC method path (e.g. `/zcash.walletd/MethodName`)
      params.request.method,

      /// Serialize request into bytes
      (value) => value.toBuffer(),

      /// walletd responses are already raw bytes
      (value) => value,
    );
  }

  /// Executes a unary (single-response) walletd request.
  @override
  Future<List<int>> doRequest<T>(
    ZCashWalletdRequestDetails<dynamic> params, {
    Duration? timeout,
  }) async {
    final method = buildMethod(params);

    final request = $createUnaryCall(
      method,
      params,
      options: CallOptions(timeout: timeout),
    );

    return await request;
  }

  /// Executes a streaming walletd request.
  ///
  /// Used for endpoints such as:
  /// - subtree roots
  /// - block scanning
  /// - chain state updates
  @override
  Stream<List<int>> doRequestStream<T>(
    ZCashWalletdRequestDetails<dynamic> params, {
    Duration? timeout,
  }) {
    final method = buildMethod(params);

    return $createStreamingCall(method, () async* {
      /// walletd streaming APIs expect an initial request message
      yield params;
    }(), options: CallOptions(timeout: timeout));
  }
}

/// Example usage:
/// Connect to walletd and stream Orchard subtree roots.
FutureOr<void> main() async {
  final String url = "testnet.zec.rocks";
  final int port = 443;

  /// Create secure gRPC channel
  final channel = ClientChannel(
    url,
    port: port,
    options: const ChannelOptions(credentials: ChannelCredentials.secure()),
  );

  /// Initialize walletd client and provider
  final client = WalletdGrpcClient(channel);
  final provider = ZCashWalletdProvider(client);

  /// Request Orchard subtree roots as a stream
  final treeState = provider.requestStream(
    ZWalletdRequestGetSubtreeRoots(
      GetSubtreeRootsArg.defaultConfig(ShieldedProtocol.orchard),
    ),
  );

  /// Consume the stream
  await for (final _ in treeState) {
    // Handle subtree root updates here
  }
}
