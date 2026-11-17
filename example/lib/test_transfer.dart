import 'dart:io';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/transfer_example.dart';

void main() async {
  print('Starting...');
  final host = Platform.environment['LWD_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9067');
  final context = await getContext(libraryPath: zcashRustLibrary());
  print('Context ready');

  final provider = createGrpcClient(url: host, port: port);
  print('Provider created');

  await fullTransferExample(context: context, provider: provider);
  print('Done');
}
