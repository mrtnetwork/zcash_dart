import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/transfer/params_downloader.dart';
import 'package:zcash_dart/zcash.dart';

/// Initialize the backend (`Bu`) and a crypto context.
///
/// Proving runs in Rust: pass [libraryPath] (native `.so`/`.dylib`) or, on
/// web, [wasmUrl]/[wasmGlueUrl]. Sapling params resolve per batch from
/// explicit context bytes when set, otherwise via [downloader].
///
/// [blockchainUtils.setRustApi] is used (not a bare `Bu.init`) because it
/// installs the native backend into the `blockchainUtils` singleton. Without
/// it the pure-Dart backend stays active and the native-only APIs (Merkle
/// frontier, Orchard, Sapling) throw `UnimplementedError`.
Future<ZcashCryptoContext> getContext({
  String? libraryPath,
  String? wasmUrl,
  String? wasmGlueUrl,
  ZcashDownloadService downloader = const SaplingParamDownloer(),
}) async {
  blockchainUtils.setRustApi(
    libraryPath: libraryPath,
    wasmGlueUrl: wasmGlueUrl,
  );
  return DefaultZcashCryptoContext.sync(paramsDownloader: downloader);
}
