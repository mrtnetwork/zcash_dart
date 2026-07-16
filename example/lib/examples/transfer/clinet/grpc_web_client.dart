import 'package:grpc/grpc_web.dart';
import 'package:zcash_dart/zcash.dart';
import 'grpc_provider_example.dart';

ZcashWalletdProvider getProvider({required String url, required int port}) {
  final channel = GrpcWebClientChannel.xhr(Uri.parse(url));
  final client = WalletdGrpcClient(channel);
  return ZcashWalletdProvider(client);
}
