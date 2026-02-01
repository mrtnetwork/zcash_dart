import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/transporter.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

@JS("window")
external _Window _window;
@JS("encodeURIComponent")
external String _encodeURIComponent(String uriComponent);

abstract class ZKLibWebTransporter implements ZKLibTransporter {
  const ZKLibWebTransporter();
  static Future<ZKLibWebTransporter> init(
      ZKLibConfig config, void Function() onTerminate) {
    if (config.useIsolate) {
      return ZKLibWebWorkerTransporter.init(config, onTerminate);
    }
    return ZKLibWebSyncTransporter.init(config);
  }

  void close();
}

class ZKLibWebSyncTransporter implements ZKLibWebTransporter {
  _ZKWasmGlue? _glueJs;
  ZKLibWebSyncTransporter._(_ZKWasmGlue glueJs) : _glueJs = glueJs;
  static Future<ZKLibWebSyncTransporter> init(ZKLibConfig config) async {
    JSObject glue = await importModule(config.requireGlueJs().toJS).toDart;
    if (glue.isUndefinedOrNull) {
      throw ZKLibException.operationFailed("init",
          reason:
              "Failed to import glue module. `importModule` return undefined object.",
          details: {"url": config.requireGlueJs()});
    }
    final wasmBytes = await _window.fetchBuffer(config.requireWasm(), "init");
    glue = glue as _ZKWasmGlue;
    if (glue.initSyncFunc == null || glue.processWasmFunc == null) {
      throw ZKLibException.operationFailed("init",
          reason: "Missing glue module required functions.",
          details: {
            "function": glue.initSyncFunc == null ? "initSync" : "process_wasm"
          });
    }
    final wasm = glue.initSync(wasmBytes.toJS);
    if (wasm.processWasmFunc == null) {
      throw ZKLibException.operationFailed("init",
          reason: "Missing wasm required function.",
          details: {"function": "process_wasm"});
    }
    return ZKLibWebSyncTransporter._(glue);
  }

  @override
  Future<ZKLibResponse> sendRequest(ZKLibRequestId id,
      {List<int> payload = const []}) async {
    final transporter = _glueJs;
    if (transporter == null) {
      throw ZKLibException.operationFailed("sendRequest",
          reason: "ZKLib already closed.");
    }
    final jsU8Array = switch (payload) {
      final Uint8List r => r.toJS,
      _ => Uint8List.fromList(payload).toJS
    };
    final response = transporter.processWasm(id.id, jsU8Array);
    return ZKLibResponse(
        code: ZKLibResponseCode.fromCode(response.code),
        payload: response.bytes.toDart);
  }

  @override
  void close() {
    _glueJs = null;
  }
}

class ZKLibWebWorkerTransporter implements ZKLibWebTransporter {
  final _lock = SafeAtomicLock();
  _Worker? _worker;
  ZKLibWebWorkerTransporter._(_Worker worker) : _worker = worker;
  Completer<_JsOutputData>? _messageCompleter;
  void _onResponse(_MessageEvent<_JsOutputData> e) {
    _messageCompleter?.complete(e.data);
  }

  static Future<ZKLibWebWorkerTransporter> init(
    ZKLibConfig config,
    void Function() onTerminate,
  ) async {
    _Worker worker;
    final workerModuleUrl = config.requireWorkerModule();
    String glue = config.requireGlueJs();
    if (config.inlineWorkerInitialization) {
      final workerModule = await _window.fetchText(workerModuleUrl, "init");
      worker = _Worker(
          "data:text/javascript,${_encodeURIComponent(workerModule)}",
          _WorkerOptions()..type = "module");
      glue = await _window.fetchText(glue, "init");
    } else {
      worker = _Worker(workerModuleUrl, _WorkerOptions()..type = "module");
    }
    final wasm = await _window.fetchBuffer(config.requireWasm(), "init");
    final Completer<ZKLibWebWorkerTransporter> completer = Completer();
    void onMessage(_MessageEvent<_JsOutputData> event) {
      if (!completer.isCompleted) {
        completer.complete(ZKLibWebWorkerTransporter._(worker));
      }
    }

    void onError(_MessageEvent event) {
      if (!completer.isCompleted) {
        completer.completeError(ZKLibException.operationFailed("init",
            reason: "Worker onError called."));
      }
    }

    worker.addEventListener("message", onMessage.toJS);
    worker.addEventListener("error", onError.toJS);
    worker.postMessage({
      "glue": glue,
      "wasm": wasm,
      "inline": config.inlineWorkerInitialization
    }.jsify()!);
    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw ZKLibException.operationFailed(
        "init",
        reason: "Worker did not respond within 10 seconds",
      ),
    );
    worker.removeEventListener("message", onMessage.toJS);
    worker.removeEventListener("error", onError.toJS);
    worker.addEventListener("message", result._onResponse.toJS);
    worker.addEventListener("error", onTerminate.toJS);

    return result;
  }

  @override
  Future<ZKLibResponse> sendRequest(ZKLibRequestId id,
      {List<int> payload = const []}) async {
    return await _lock.run(() async {
      final worker = _worker;
      if (worker == null) {
        throw ZKLibException.operationFailed("sendRequest",
            reason: "ZKLib already closed.");
      }
      final completer = _messageCompleter = Completer<_JsOutputData>();

      worker.postMessage(_JsInputData(
          id: id.id,
          payload: switch (payload) {
            Uint8List payload => payload.toJS,
            _ => Uint8List.fromList(payload).toJS
          }));
      final result = await completer.future;
      return ZKLibResponse(
          code: ZKLibResponseCode.fromCode(result.code),
          payload: result.bytes.toDart);
    });
  }

  @override
  void close() {
    final worker = _worker;
    _worker = null;
    _messageCompleter?.completeError(ZKLibException(
        "ZKLib closed: worker terminated before completing the operation"));
    _lock.run(() {
      worker?.terminate();
    });
  }
}

@JS("window")
extension type _Window._(JSObject _) implements _WebEventStream {
  external factory _Window();
  @JS("fetch")
  external JSPromise<_Response> _fetch(String resource);

  @JS("postMessage")
  external void postMessage(JSAny? message);

  Future<_Response> fetch(String url, String operation) async {
    final future = _fetch(url);
    final result = await future.toDart;
    if (!result.ok || (result.status < 200 || result.status > 299)) {
      throw ZKLibException.operationFailed(operation,
          reason: "Failed to fetch resource.",
          details: {"url": url, "status": result.status});
    }
    return result;
  }

  Future<ByteBuffer> fetchBuffer(String url, String operation) async {
    final result = await fetch(url, operation);
    return result.toBuffer();
  }

  Future<String> fetchText(String url, String operation) async {
    final result = await fetch(url, operation);
    return result.toText();
  }
}

@JS("Response")
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response();

  @JS("ok")
  external bool get ok;
  @JS("status")
  external int get status;
  @JS("arrayBuffer")
  external JSPromise<JSArrayBuffer> _arrayBuffer();
  @JS("text")
  external JSPromise<JSString> _text();
  Future<ByteBuffer> toBuffer() async {
    final data = await _arrayBuffer().toDart;
    return data.toDart;
  }

  Future<String> toText() async {
    final data = await _text().toDart;
    return data.toDart;
  }
}

extension type _WebEventStream._(JSObject _) {
  @JS("addEventListener")
  external void addEventListener(String type, JSFunction callback);
  @JS("removeEventListener")
  external void removeEventListener(String type, JSFunction callback);
}
@JS()
extension type _WASM(JSObject _) implements JSObject {
  @JS("process_wasm")
  external JSFunction? get processWasmFunc;
}
@JS()
extension type _ZKWasmGlue(JSObject _) implements JSObject {
  @JS("initSync")
  external _WASM initSync(JSObject obj);
  @JS("initSync")
  external JSFunction? get initSyncFunc;

  @JS("process_wasm")
  external JSFunction? get processWasmFunc;
  @JS("process_wasm")
  external _JsOutputData processWasm(int id, JSUint8Array payload);
}
@JS()
extension type _JsOutputData(JSObject _) implements JSObject {
  @JS("bytes")
  external JSUint8Array get bytes;
  @JS("code")
  external int get code;
}

@JS()
extension type _JsInputData._(JSObject _) implements JSObject {
  external factory _JsInputData({int id, JSUint8Array payload});
  @JS("payload")
  external JSUint8Array get payload;
  @JS("id")
  external int get id;
}

@JS("Worker")
extension type _Worker._(JSObject _) implements JSObject, _WebEventStream {
  external factory _Worker(String? aURL, _WorkerOptions? options);
  external String? get aURL;
  external _WorkerOptions? get options;
  external void postMessage(JSAny message);
  @JS("terminate")
  external void terminate();
}
extension type _WorkerOptions._(JSObject _) implements JSObject {
  external factory _WorkerOptions(
      // ignore: unused_element_parameter
      {String? type,
      // ignore: unused_element_parameter
      String? credentials,
      // ignore: unused_element_parameter
      String? name});

  external String? get type;
  external set type(String? type);
  external String? get credentials;
  external set credentials(String? type);
  external String? get name;
  external set name(String? type);
}
@JS("Event")
extension type _MessageEvent<T extends JSAny?>._(JSObject _)
    implements JSObject {
  external factory _MessageEvent();
  external T get data;
}
