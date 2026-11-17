import 'package:zcash_dart/zcash.dart';
import 'package:grpc/grpc.dart';

import 'grpc_provider_example.dart';

ZcashWalletdProvider getProvider({required String url, required int port}) {
  final channel = ClientChannel(
    url,
    port: port,
    options: ChannelOptions(
      credentials:
          port == 443
              ? ChannelCredentials.secure()
              : ChannelCredentials.insecure(),
    ),
  );

  final client = WalletdGrpcClient(channel);
  return ZcashWalletdProvider(client);
}
