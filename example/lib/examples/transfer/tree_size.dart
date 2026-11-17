import "dart:io";

import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:zcash_dart/zcash.dart';

/// Prints the note-commitment tree sizes (leaf counts) that lightwalletd
/// reports for a compact block. This is the same number the incremental
/// Merkle tree is built from.
///
/// Usage:
///   dart run lib/examples/transfer/tree_size.dart [port=9069]
Future<void> main() async {
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9069');
  final provider = createGrpcClient(url: '127.0.0.1', port: port);

  final latest = await provider.request(
    ZcashGrpcRequestMessage(request: ZWalletdGetLatestBlock()),
  );
  print('latest block height: ${latest.height}');

  for (var h = BigInt.one; h <= latest.height!; h = h + BigInt.one) {
    final block = await provider.request(
      ZcashGrpcRequestMessage(
        request: ZWalletdGetBlock(getBlock: ZWalletdBlockID(height: h)),
      ),
    );
    print(
      'height $h: saplingTreeSize=${block.saplingCommitmentTreeSize} '
      'orchardTreeSize=${block.orchardCommitmentTreeSize}',
    );
  }
}
