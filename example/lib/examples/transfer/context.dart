import 'package:example/examples/transfer/params_downloader.dart';
import 'package:zcash_dart/zcash.dart';

Future<ZcashCryptoContext> getContext({
  bool setSaplingParams = true,
  bool dart = false,
  ZKLibConfig? config,
  ZcashDownloadService downloder = const SaplingParamDownloer(),
  String? libPath,
  ZKLib? lib,
}) async {
  if (lib == null && config != null) {
    lib = await ZKLib.init(config);
  }
  return DefaultZcashCryptoContext.sync(lib: lib);
}
