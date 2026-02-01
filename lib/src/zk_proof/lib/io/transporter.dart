import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:blockchain_utils/utils/atomic/atomic.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/transporter.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

import 'ffi.dart';

abstract class ZKLibIoTransporter implements ZKLibTransporter {
  void close() {}
  static Future<ZKLibIoTransporter?> init(
      ZKLibConfig config, void Function() onTerminate) async {
    final uri = () {
      if (Platform.isAndroid) return config.requireAndroidLibrary();
      if (Platform.isIOS) return config.requireIosLibrary();
      if (Platform.isLinux) return config.requireLinuxLibrary();
      if (Platform.isMacOS) return config.requireMacosLibrary();
      if (Platform.isWindows) return config.requireWindowsLibrary();
      return null;
    }();
    if (uri == null) return null;
    if (!config.useIsolate) {
      return ZKLibIoIsolateTransporter.init(uri, onTerminate);
    }
    return ZKLibIoSyncTransporter.fromConfig(uri);
  }
}

class ZKLibIoSyncTransporter implements ZKLibIoTransporter {
  final DynamicLibrary library;
  final ProcessBytesDart processBytes;
  final FreeBytesDart freeBytes;
  ZKLibIoSyncTransporter(this.library)
      : processBytes =
            library.lookupFunction<ProcessBytesNative, ProcessBytesDart>(
                'process_bytes_ffi'),
        freeBytes = library
            .lookupFunction<FreeBytesNative, FreeBytesDart>('free_bytes');

  static ZKLibIoSyncTransporter fromConfig(String uri) {
    try {
      return ZKLibIoSyncTransporter(DynamicLibrary.open(uri));
    } catch (e) {
      throw ZKLibException("Failed to open dynamic liberary.",
          details: {"uri": uri, "error": e.toString()});
    }
  }

  ZKLibResponse sendRequestSync(ZKLibRequestId id,
      {List<int> payload = const []}) {
    final payloadPtr = calloc<Uint8>(payload.length);
    final payloadList = payloadPtr.asTypedList(payload.length);
    payloadList.setAll(0, payload);
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Uint64>();
    try {
      final code =
          processBytes(id.id, payloadPtr, payload.length, outPtr, outLen);
      return ZKLibResponse(
          code: ZKLibResponseCode.fromCode(code),
          payload: outPtr.value.asTypedList(outLen.value));
    } finally {
      freeBytes(outPtr.value, outLen.value);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  @override
  Future<ZKLibResponse> sendRequest(ZKLibRequestId id,
      {List<int> payload = const []}) async {
    return sendRequestSync(id, payload: payload);
  }

  @override
  void close() {
    library.close();
  }
}

class ZKLibIoIsolateTransporter implements ZKLibIoTransporter {
  final _lock = SafeAtomicLock();
  Completer<ZKLibResponse>? _lastRequest;
  StreamSubscription<dynamic>? onClose;
  final SendPort port;
  final ReceivePort receivePort;
  ZKLibIoIsolateTransporter(
      {required this.port, required this.receivePort, required this.onClose});
  void listen(dynamic msg) {
    switch (msg) {
      case ZKLibResponse msg:
        _lastRequest?.complete(msg);
        _lastRequest = null;
        break;
      default:
        break;
    }
  }

  static Future<ZKLibIoIsolateTransporter> init(
      String uri, void Function() onTerminate) async {
    final initPort = RawReceivePort(null, "zklib");
    final connection = Completer<SendPort>.sync();
    initPort.handler = (_ZKLibIsolateInitResponse initialMessage) {
      if (connection.isCompleted) return;
      final port = initialMessage.port;
      final error = initialMessage.exception;
      if (error != null) {
        connection.completeError(error);
      } else if (port != null) {
        connection.complete(port);
      }
    };
    final onExit = ReceivePort();
    void onExitCallBack() {
      if (!connection.isCompleted) {
        connection.completeError(
            ZKLibException("The isolate terminated unexpectedly."));
      }
    }

    final onClose = onExit.listen((s) {
      onExitCallBack();
      onTerminate();
      onExit.close();
    });
    try {
      await Isolate.spawn(_ZKLibIsolate.init,
          _ZKLibIsolateConfig(uri: uri, port: initPort.sendPort),
          debugName: "zklib", errorsAreFatal: true, onExit: onExit.sendPort);
    } catch (_) {
      initPort.close();
      onExit.close();
      rethrow;
    }
    try {
      final result = await connection.future;
      final transporter = ZKLibIoIsolateTransporter(
          port: result,
          receivePort: ReceivePort.fromRawReceivePort(initPort),
          onClose: onClose);
      transporter.receivePort.listen(transporter.listen);

      // initPort.keepIsolateAlive;
      return transporter;
    } on ZKLibException {
      initPort.close();
      onExit.close();
      rethrow;
    }
  }

  @override
  Future<ZKLibResponse> sendRequest(ZKLibRequestId id,
      {List<int> payload = const []}) async {
    return await _lock.run(() async {
      final lock = _lastRequest = Completer<ZKLibResponse>();
      port.send(ZKLibRequest(code: id, payload: payload));
      return await lock.future;
    });
  }

  @override
  void close() {
    receivePort.close();
    onClose?.cancel();
    onClose = null;
    _lastRequest?.completeError(ZKLibException(
        "ZKLib closed: isolate terminated before completing the operation"));
    _lastRequest = null;
    _lock.run(() => port.send(_ZKLibCloseIsolate()));
  }
}

class _ZKLibIsolate {
  final SendPort port;
  ZKLibIoSyncTransporter? transporter;
  _ZKLibIsolate({required this.port, required this.transporter});

  static _ZKLibIsolate? init(_ZKLibIsolateConfig request) {
    ZKLibIoSyncTransporter? transporter;
    try {
      transporter = ZKLibIoSyncTransporter.fromConfig(request.uri);
    } catch (e) {
      request.port.send(_ZKLibIsolateInitResponse(
          exception: ZKLibException("Failed to open dynamic liberary.",
              details: {"uri": request.uri, "error": e.toString()}),
          port: null));
      return null;
    }
    final receivePort = ReceivePort();
    final c = _ZKLibIsolate(transporter: transporter, port: request.port);
    request.port.send(
        _ZKLibIsolateInitResponse(exception: null, port: receivePort.sendPort));
    receivePort.listen(c.onListen);
    return c;
  }

  void onListen(dynamic message) {
    final transporter = this.transporter;
    assert(transporter != null, "ZKLib closed");
    if (transporter == null) {
      return;
    }
    switch (message) {
      case ZKLibRequest msg:
        final response =
            transporter.sendRequestSync(msg.code, payload: msg.payload);
        port.send(response);
        break;
      case _ZKLibCloseIsolate _:
        this.transporter = null;
        transporter.close();
        break;
      default:
        throw ZKLibException("Unexpected request.");
    }
  }
}

class _ZKLibIsolateConfig {
  final String uri;
  final SendPort port;
  const _ZKLibIsolateConfig({required this.uri, required this.port});
}

class _ZKLibIsolateInitResponse {
  final ZKLibException? exception;
  final SendPort? port;
  const _ZKLibIsolateInitResponse(
      {required this.exception, required this.port});
}

class _ZKLibCloseIsolate {
  const _ZKLibCloseIsolate();
}
