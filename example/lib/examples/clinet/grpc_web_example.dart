import 'dart:async';
import 'package:grpc/grpc_web.dart';
import 'package:zcash_dart/zcash.dart';
import 'grpc_provider_example.dart';

ZCashWalletdProvider getClient({String url = "....", int port = 443}) {
  final channel = GrpcWebClientChannel.xhr(Uri.parse(url));
  final client = WalletdGrpcClient(channel);
  return ZCashWalletdProvider(client);
}

/// Example: Using walletd via gRPC-Web (Browser)
///
/// This example shows how to connect to a walletd gRPC-Web endpoint
/// from a web environment (Flutter Web / Dart Web).
///
/// Requirements:
/// - walletd must expose a gRPC-Web compatible endpoint
/// - Proper CORS configuration is required
FutureOr<void> main() async {
  /// gRPC-Web endpoint (HTTP/HTTPS, not raw gRPC)
  final String url = "walletd_grpc_web_url";

  /// Create a gRPC-Web channel using XHR transport
  /// (recommended for browser environments)
  final channel = GrpcWebClientChannel.xhr(Uri.parse(url));

  /// Initialize walletd gRPC client
  final client = WalletdGrpcClient(channel);

  /// Wrap the client with ZCash walletd provider
  final provider = ZCashWalletdProvider(client);

  /// Request Orchard subtree roots as a stream
  /// This is typically used for:
  /// - chain synchronization
  /// - note scanning
  /// - Merkle tree state updates
  final treeState = provider.requestStream(
    ZWalletdRequestGetSubtreeRoots(
      GetSubtreeRootsArg.defaultConfig(ShieldedProtocol.orchard),
    ),
  );

  /// Consume the streaming response
  await for (final _ in treeState) {
    // Handle subtree root updates here
  }
}
