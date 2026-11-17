import 'dart:async';

import 'package:blockchain_utils/protocol/zip32/zip32/types.dart';
import 'package:zcash_dart/zcash.dart';
import 'package:grpc/grpc.dart';
import 'client.dart'
    if (dart.library.io) 'grpc_native_client.dart'
    if (dart.library.js_interop) 'grpc_web_client.dart';

ZcashWalletdProvider createGrpcClient({
  String url = "localhost",
  int port = 9090,
}) {
  return getProvider(url: url, port: port);
}

/// gRPC client implementation for Zcash `walletd`.
///
/// This client:
/// - Wraps a gRPC `ClientChannel`
/// - Dynamically builds gRPC methods at runtime
/// - Sends raw binary requests and receives raw binary responses
/// - Implements both unary and streaming walletd calls
class WalletdGrpcClient extends Client with ZcashWalletdServiceProvider {
  WalletdGrpcClient(super.channel);

  /// Builds a gRPC method dynamically from request metadata.
  ///
  /// walletd exposes many endpoints; instead of generating
  /// static stubs, we serialize requests as raw bytes and
  /// route them by method name.
  static ClientMethod<ZcashWalletdRequestDetails, List<int>> buildMethod(
    ZcashWalletdRequestDetails params,
  ) {
    return ClientMethod<ZcashWalletdRequestDetails, List<int>>(
      /// Full gRPC method path (e.g. `/zcash.walletd/MethodName`)
      params.method(),

      /// Serialize request into bytes
      (value) => value.toBuffer(),

      /// walletd responses are already raw bytes
      (value) => value,
    );
  }

  /// Executes a unary (single-response) walletd request.
  @override
  Future<List<int>> doGrpcRequest(
    ZcashWalletdRequestDetails params, {
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
  Stream<List<int>> doGrpcRequestStream(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  }) {
    final method = buildMethod(params);

    return $createStreamingCall(method, () async* {
      /// walletd streaming APIs expect an initial request message
      yield params;
    }(), options: CallOptions(timeout: timeout));
  }

  @override
  Future<Stream<List<int>>> doGrpcRequestStreamAsync(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  }) async {
    return doGrpcRequestStream(params);
  }
}

/// Example usage:
/// Connect to walletd and stream Orchard subtree roots.
FutureOr<void> main() async {
  final String url = "testnet.zec.rocks";
  final int port = 443;

  /// Create secure gRPC channel
  final provider = createGrpcClient(url: url, port: port);

  /// Request Orchard subtree roots as a stream
  final treeState = provider.requestStream(
    ZcashGrpcRequestMessage(
      request: ZWalletdGetSubtreeRoots(
        getSubtreeRoots: ZWalletdGetSubtreeRootsArg(
          shieldedProtocol: ZcashProtocol.orchard.toShieldedProtocol(),
        ),
      ),
    ),
  );

  /// Consume the stream
  await for (final _ in treeState) {
    // Handle subtree root updates here
  }
}
