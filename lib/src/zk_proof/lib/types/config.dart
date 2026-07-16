import 'package:blockchain_utils/exception/exception/blockchain_utils.dart';
import 'package:blockchain_utils/helper/helper.dart';
import 'package:blockchain_utils/utils/binary/binary_operation.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/service/service.dart';

class ZKWasmConfig {
  final String moduleUrl;
  final String wasmUrl;

  /// Pre-initialized WASM glue module instance.
  ///
  /// The object must be created using [importModule], and [initSync]
  /// must already be called before passing it here.
  ///
  /// If omitted, the library will import and initialize the module automatically.
  final Object? glue;

  /// Optional HTTP method passed to the Fetch API when loading the WASM binary.
  final String? fetchMethod;

  /// Optional headers passed to the Fetch API when loading the WASM binary.
  final Map<String, String>? fetchHeaders;

  /// Optional request body passed to the Fetch API when loading the WASM binary.
  final Object? fetchBody;

  const ZKWasmConfig({
    required this.moduleUrl,
    required this.wasmUrl,
    this.fetchMethod,
    this.fetchHeaders,
    this.fetchBody,
    this.glue,
  });
}

/// Configuration for ZKLib, including library paths, web settings, and Sapling parameters.
class ZKLibConfig {
  /// URLs for native libraries on each platform.
  final String? libUri;

  /// URLs for WebAssembly, glue JS, and optional worker module.
  final ZKWasmConfig? wasm;

  /// Whether to initialize the worker inline (for web).
  final bool inlineWorkerInitialization;

  /// Optional service to download Sapling parameters.
  final ZcashDownloadService? saplingParamsDownloader;

  /// URLs for Sapling spend and output parameters.
  final String? saplingSpendParamsUrl;
  final String? saplingOutputParamsUrl;

  /// URLs for Sapling spend and output parameters.
  final String? saplingSpendParamsFileUri;
  final String? saplingOutputParamsFileUri;

  /// Constructor with optional overrides.
  const ZKLibConfig({
    this.libUri,
    this.inlineWorkerInitialization = false,
    this.wasm,
    this.saplingParamsDownloader,
    this.saplingSpendParamsUrl,
    this.saplingOutputParamsUrl,
    this.saplingSpendParamsFileUri,
    this.saplingOutputParamsFileUri,
  });

  /// Returns Linux library URL or throws if missing.
  String requireIoLibrary() => _require(libUri, "Library URL is missing.");

  /// Returns glue JS URL or throws if missing.
  ZKWasmConfig requireWasm() => _require(wasm, "Wasm config is missing.");

  /// Returns Sapling spend params URI or null if not set.
  Uri? saplingSpendParamsUri() =>
      _parseOptionalUri(saplingSpendParamsUrl, "Invalid Sapling spend URL.");

  /// Returns Sapling output params URI or null if not set.
  Uri? saplingOutputParamsUri() =>
      _parseOptionalUri(saplingOutputParamsUrl, "Invalid Sapling output URL.");

  /// Throws if value is null, otherwise returns it.
  T _require<T extends Object>(T? value, String message) {
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
  keyError(1),
  encodingError(2),
  invalidInput(3),
  proofError(4),
  witnessError(5),
  merkleError(6),
  internal(7),
  missing(8),
  hashError(9),
  unexpectedResponse(-1);

  final int code;
  // final String description;
  const ZKLibResponseCode(this.code);

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
  bool get isSaplingSetParams =>
      this == setSpendParams || this == setOutputParams;
}

enum ZcashSaplingParameter { spend, output }

class ZKLibRequest {
  final ZKLibRequestId code;
  final List<int> payload;
  ZKLibRequest({required this.code, required List<int> payload})
    : payload = payload.asImmutableBytes;
}

class ZKLibResponse {
  final ZKLibResponseCode? error;
  final List<int> payload;
  ZKLibResponse({required this.error, List<int> payload = const []})
    : payload = payload.asImmutableBytes;
}

enum ZKLibLogLevel {
  debug(1),
  info(2),
  error(3),
  danger(4);

  final int value;
  const ZKLibLogLevel(this.value);

  static ZKLibLogLevel fromValue(int? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ItemNotFoundException(),
    );
  }
}
