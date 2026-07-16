import 'dart:async';
import 'dart:js_interop';
import 'package:zcash_dart/src/zk_proof/lib/types/request.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/transporter.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

@JS("window")
external _Window? _window;
@JS("fetch")
external JSPromise<_Response> _fetchGlobal(
  String resource,
  _FetchOptions? options,
);
@JS("fetch")
external JSFunction? get _fetchGlobalFunc;

abstract class ZKLibWebTransporter implements ZKLibTransporter {
  const ZKLibWebTransporter();
  static Future<ZKLibWebTransporter> init(ZKLibConfig config) {
    return ZKLibWebSyncTransporter.init(config);
  }
}

class ZKLibWebSyncTransporter implements ZKLibWebTransporter {
  ZKWasmGlue? _glueJs;
  ZKLibWebSyncTransporter(ZKWasmGlue glueJs) : _glueJs = glueJs;
  static Future<ZKLibWebSyncTransporter> init(ZKLibConfig config) async {
    final wasmConfig = config.requireWasm();
    ZKWasmGlue? glue;
    if (wasmConfig.glue != null) {
      glue = wasmConfig.glue as ZKWasmGlue;
    }
    if (glue == null) {
      JSObject? importGlue =
          await importModule(wasmConfig.moduleUrl.toJS).toDart;
      glue = importGlue as ZKWasmGlue?;
    }

    if (glue == null || glue.isUndefinedOrNull) {
      throw ZKLibException.operationFailed(
        "init",
        reason:
            "Failed to import glue module. `importModule` return undefined object.",
        details: {"url": wasmConfig.moduleUrl},
      );
    }
    if (wasmConfig.glue == null && glue.initSyncFunc != null) {
      final wasmBytes = await _FetchUtls.fetch(
        wasmConfig,
        "ZKLibWebTransporter.init",
      );
      glue.initSync(wasmBytes);
    }
    if (glue.initSyncFunc == null ||
        glue.newRequestFunc == null ||
        glue.setupSaplingOutputParamsInnerFunc == null ||
        glue.setupSaplingSpendParamsInnerFunc == null) {
      throw ZKLibException.operationFailed(
        "init",
        reason: "Missing glue module required functions.",
      );
    }

    return ZKLibWebSyncTransporter(glue);
  }

  @override
  void close() {
    _glueJs = null;
  }

  @override
  ZKLibResponse sendRequest(ZKRequest request) {
    final transporter = _glueJs;
    if (transporter == null) {
      throw ZKLibException.operationFailed(
        "sendRequest",
        reason: "ZKLib already closed.",
      );
    }
    final response = transporter.newRequest(
      request.toCbor().encode().jsify() as JSArray<JSNumber>,
    );
    final code = response.code;
    return ZKLibResponse(
      error: code == 0 ? null : ZKLibResponseCode.fromCode(code),
      payload: code == 0 ? response.bytes.toDart : [],
    );
  }

  @override
  ZKLibResponse setupSaplingParams({
    required List<int> payload,
    required ZcashSaplingParameter type,
  }) {
    final transporter = _glueJs;
    if (transporter == null) {
      throw ZKLibException.operationFailed(
        "setupSaplingParams",
        reason: "ZKLib already closed.",
      );
    }
    final code =
        switch (type) {
          ZcashSaplingParameter.spend => transporter
              .setupSaplingSpendParamsInner(
                payload.jsify() as JSArray<JSNumber>,
              ),
          ZcashSaplingParameter.output => transporter
              .setupSaplingOutputParamsInner(
                payload.jsify() as JSArray<JSNumber>,
              ),
        }.toDartInt;
    return ZKLibResponse(
      error: code == 0 ? null : ZKLibResponseCode.fromCode(code),
    );
  }
}

@JS("window")
extension type _Window._(JSObject _) implements JSObject {
  external factory _Window();
  @JS("fetch")
  external JSPromise<_Response> fetch(String resource, _FetchOptions? options);
}

@JS("Response")
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response();

  @JS("ok")
  external bool get ok;
  @JS("status")
  external int get status;
  @JS("arrayBuffer")
  external JSPromise<JSArrayBuffer> arrayBuffer();
  @JS("text")
  external JSPromise<JSString> text();

  Future<JSArrayBuffer> toBuffer() async {
    return await arrayBuffer().toDart;
  }
}

@JS()
extension type ZKWasmGlue(JSObject _) implements JSObject {
  @JS("initSync")
  external JSObject initSync(JSObject obj);
  @JS("initSync")
  external JSFunction? get initSyncFunc;

  @JS("new_request")
  external JSFunction? get newRequestFunc;
  @JS("new_request")
  external ZKJSOutputData newRequest(JSArray<JSNumber> payload);

  @JS("setup_sapling_spend_params_inner")
  external JSFunction? get setupSaplingSpendParamsInnerFunc;
  @JS("setup_sapling_spend_params_inner")
  external JSNumber setupSaplingSpendParamsInner(JSArray<JSNumber> payload);

  @JS("setup_sapling_output_params_inner")
  external JSFunction? get setupSaplingOutputParamsInnerFunc;
  @JS("setup_sapling_output_params_inner")
  external JSNumber setupSaplingOutputParamsInner(JSArray<JSNumber> payload);
}
@JS()
extension type ZKJSOutputData(JSObject _) implements JSObject {
  @JS("bytes")
  external JSUint8Array get bytes;
  @JS("code")
  external int get code;
}
extension type _FetchOptions._(JSObject _) implements JSAny {
  external _FetchOptions();
  external set method(JSString _);
  external set headers(JSAny? _);
  external set body(JSAny? _);
}

class _FetchUtls {
  static _FetchOptions? buildOptions(ZKWasmConfig config) {
    final method = config.fetchMethod;
    final headers = config.fetchHeaders;
    final body = config.fetchBody;
    if (method == null && headers == null && body == null) {
      return null;
    }
    final option = _FetchOptions();
    if (method != null) option.method = method.toJS;
    if (body != null) option.body = body.jsify();
    if (headers != null) option.headers = headers.jsify();
    return option;
  }

  static Future<_Response> fetchInternal(
    ZKWasmConfig config,
    String operation,
  ) {
    final options = buildOptions(config);
    final window = _window;
    if (window != null) {
      final result = window.fetch(config.wasmUrl, options);
      return result.toDart;
    }
    if (_fetchGlobalFunc != null) {
      final result = _fetchGlobal(config.wasmUrl, options);
      return result.toDart;
    }
    throw ZKLibException.operationFailed(
      operation,
      reason: "Fetch api mising.",
    );
  }

  static Future<JSArrayBuffer> fetch(
    ZKWasmConfig config,
    String operation,
  ) async {
    final result = await fetchInternal(config, operation);
    if (!result.ok || (result.status < 200 || result.status > 299)) {
      throw ZKLibException.operationFailed(
        operation,
        reason: "Failed to fetch resource.",
        details: {"url": config.wasmUrl, "status": result.status.toString()},
      );
    }
    return result.toBuffer();
  }
}
