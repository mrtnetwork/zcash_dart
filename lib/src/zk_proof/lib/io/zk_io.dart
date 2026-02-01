import 'package:zcash_dart/src/zk_proof/lib/core/zk.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/io/transporter.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

Future<ZKLib> initZkLib(ZKLibConfig config) => ZKLibIO.init(config);

class ZKLibIO extends ZKLib {
  ZKLibIoTransporter? _transporter;
  List<void Function()> _listeners = [];
  ZKLibIO._(super.config);

  static Future<ZKLibIO> init(ZKLibConfig config) async {
    final lib = ZKLibIO._(config);
    ZKLibIoTransporter? transporter =
        await ZKLibIoTransporter.init(config, lib._onTerminate);
    if (transporter == null) throw ZKLibException("Unsupported platform.");
    lib._transporter = transporter;
    return lib;
  }

  @override
  Future<List<int>> sendRequest(ZKLibRequestId id,
      {List<int> payload = const []}) async {
    final transporter = _transporter;
    if (transporter == null) {
      throw ZKLibException.operationFailed("sendRequest",
          reason: "ZKLib already closed.");
    }
    final response = await transporter.sendRequest(id, payload: payload);
    if (response.code != ZKLibResponseCode.ok) {
      throw ZKLibException.operationFailed("sendRequest",
          reason: response.code.description);
    }
    return response.payload;
  }

  void _onTerminate() {
    final transporter = _transporter;
    _transporter = null;
    transporter?.close();
    for (final i in [..._listeners]) {
      i();
    }
    _listeners = [];
  }

  @override
  void close() {
    _transporter?.close();
    _transporter = null;
    _listeners = [];
    super.close();
  }

  @override
  void addTerminateListener(void Function() listener) {
    _listeners.add(listener);
  }
}
