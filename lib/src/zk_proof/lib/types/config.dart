import 'package:blockchain_utils/helper/helper.dart';
import 'package:blockchain_utils/utils/binary/binary_operation.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/service/service.dart';

/// Configuration for ZKLib, including library paths, web settings, and Sapling parameters.
class ZKLibConfig {
  /// Whether to run the library in a separate isolate.
  final bool useIsolate;

  /// URLs for native libraries on each platform.
  final String? linuxLibraryUrl;
  final String? windowsLibraryUrl;
  final String? macosLibraryUrl;
  final String? iosLibraryUrl;
  final String? androidLibraryUrl;

  /// URLs for WebAssembly, glue JS, and optional worker module.
  final String? webWasmUrl;
  final String? webGlueJsUrl;
  final String? workerModuleUrl;

  /// Whether to initialize the worker inline (for web).
  final bool inlineWorkerInitialization;

  /// Optional service to download Sapling parameters.
  final ZCashDownloadService? saplingParamsDownloader;

  /// URLs for Sapling spend and output parameters.
  final String? saplingSpendParamsUrl;
  final String? saplingOutputParamsUrl;

  /// Constructor with optional overrides.
  const ZKLibConfig({
    this.useIsolate = true,
    this.inlineWorkerInitialization = false,
    this.linuxLibraryUrl,
    this.windowsLibraryUrl,
    this.macosLibraryUrl,
    this.iosLibraryUrl,
    this.androidLibraryUrl,
    this.webGlueJsUrl,
    this.webWasmUrl,
    this.workerModuleUrl,
    this.saplingParamsDownloader,
    this.saplingSpendParamsUrl,
    this.saplingOutputParamsUrl,
  });

  /// Returns Linux library URL or throws if missing.
  String requireLinuxLibrary() =>
      _require(linuxLibraryUrl, "Linux library URL is missing.");

  /// Returns Windows library URL or throws if missing.
  String requireWindowsLibrary() =>
      _require(windowsLibraryUrl, "Windows library URL is missing.");

  /// Returns macOS library URL or throws if missing.
  String requireMacosLibrary() =>
      _require(macosLibraryUrl, "macOS library URL is missing.");

  /// Returns iOS library URL or throws if missing.
  String requireIosLibrary() =>
      _require(iosLibraryUrl, "iOS library URL is missing.");

  /// Returns Android library URL or throws if missing.
  String requireAndroidLibrary() =>
      _require(androidLibraryUrl, "Android library URL is missing.");

  /// Returns glue JS URL or throws if missing.
  String requireGlueJs() => _require(webGlueJsUrl, "Glue JS URL is missing.");

  /// Returns WebAssembly URL or throws if missing.
  String requireWasm() => _require(webWasmUrl, "WASM URL is missing.");

  /// Returns worker module URL or throws if missing.
  String requireWorkerModule() =>
      _require(workerModuleUrl, "Worker module URL is missing.");

  /// Returns Sapling spend params URI or null if not set.
  Uri? saplingSpendParamsUri() =>
      _parseOptionalUri(saplingSpendParamsUrl, "Invalid Sapling spend URL.");

  /// Returns Sapling output params URI or null if not set.
  Uri? saplingOutputParamsUri() =>
      _parseOptionalUri(saplingOutputParamsUrl, "Invalid Sapling output URL.");

  /// Throws if value is null, otherwise returns it.
  String _require(String? value, String message) {
    if (value == null) {
      throw ZKLibException(message);
    }
    return value;
  }

  /// Tries to parse a string as a URI; throws on invalid format.
  Uri? _parseOptionalUri(String? url, String errorMessage) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw ZKLibException(errorMessage, details: {"url": url});
    }
    return uri;
  }
}

enum ZKLibResponseCode {
  ok(0, "Response success."),
  unexpectedResponse(0, "Unexpected response."),

  // General
  invalidLength(1, "Invalid request payload length."),
  invalidPointEncoding(2, "Invalid elliptic curve point encoding."),

  saplingInvalidParameters(3, "Invalid or inconsistent Sapling parameters."),
  unexpectedError(4, "An unexpected internal error occurred."),
  saplingSpendNotInitialized(
      5, "Sapling spend context has not been initialized."),
  saplingOutputNotInitialized(
      6, "Sapling output context has not been initialized."),
  unknowRequestId(7, "Unknown or unsupported request identifier."),

  // Sapling-specific
  saplingInvalidValue(10, "Invalid Sapling note value."),
  saplingInvalidRandomness(11, "Invalid Sapling randomness."),
  saplingInvalidAuthPath(12, "Invalid Sapling authentication path."),
  saplingInvalidAnchor(13, "Invalid Sapling anchor."),
  saplingInvalidProof(14, "Invalid Sapling zero-knowledge proof."),

  // Orchard
  orchardInvalidFvk(20, "Invalid Orchard full viewing key."),
  orchardInvalidAddress(21, "Invalid Orchard address."),
  orchardInvalidRho(22, "Invalid Orchard rho value."),
  orchardInvalidRseed(23, "Invalid Orchard rseed value."),
  orchardInvalidAuthPath(24, "Invalid Orchard authentication path."),
  orchardInvalidScalar(25, "Invalid Orchard scalar value."),
  orchardInvalidNote(26, "Invalid Orchard note."),
  orchardInvalidCommitment(27, "Invalid Orchard note commitment."),
  orchardInvalidSpend(28, "Invalid Orchard spend."),
  orchardInvalidCircuit(29, "Invalid Orchard circuit."),
  orchardProofCreationFailed(
      30, "Failed to create Orchard zero-knowledge proof.");

  final int code;
  final String description;
  const ZKLibResponseCode(this.code, this.description);

  static ZKLibResponseCode fromCode(int code) {
    return ZKLibResponseCode.values.firstWhere(
      (e) => e.code == code,
      orElse: () => ZKLibResponseCode.unexpectedResponse,
    );
  }
}

enum ZKLibRequestId {
  version(BinaryOps.maxUint32),
  setSpendParams(1),
  setOutputParams(2),
  createSpendProof(3),
  createOutputProof(4),
  verifyOutputProof(5),
  verifySpendProof(6),
  verifyOrchardProof(8),
  createOrchardProof(9),
  hasSpendParams(10),
  hasOutputParams(11);

  final int id;
  const ZKLibRequestId(this.id);
}

enum ZCashSaplingParameter { spend, output }

class ZKLibRequest {
  final ZKLibRequestId code;
  final List<int> payload;
  ZKLibRequest({required this.code, required List<int> payload})
      : payload = payload.asImmutableBytes;
}

class ZKLibResponse {
  final ZKLibResponseCode code;
  final List<int> payload;
  ZKLibResponse({required this.code, List<int> payload = const []})
      : payload = payload.asImmutableBytes;
}
