import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:zcash_dart/zcash.dart';

/// Minimal connectivity check against the local zcashlightwalletd.
///
/// Verifies that the gRPC endpoint answers and that the backend node is the
/// local regtest chain (run from the example package).
Future<void> main() async {
  final provider = createGrpcClient(url: '127.0.0.1', port: 9067);

  final lightdInfo = await provider.request(
    ZcashGrpcRequestMessage(request: ZWalletdGetLightdInfo()),
  );

  print('chain name        : ${lightdInfo.chainName}');
  print('block height      : ${lightdInfo.blockHeight}');
  print('sapling height    : ${lightdInfo.saplingActivationHeight}');
  print('consensus branch  : ${lightdInfo.consensusBranchId}');
  print('node version      : ${lightdInfo.zcashdSubversion}');
  print('lightd version    : ${lightdInfo.lightwalletProtocolVersion}');

  final latest = await provider.request(
    ZcashGrpcRequestMessage(request: ZWalletdGetLatestBlock()),
  );
  print('latest block      : height=${latest.height} hash=${latest.hash}');
}
