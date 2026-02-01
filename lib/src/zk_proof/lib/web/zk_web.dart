import 'package:zcash_dart/src/zk_proof/lib/core/zk.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';
import 'package:zcash_dart/src/zk_proof/lib/web/transporter.dart';

Future<ZKLib> initZkLib(ZKLibConfig config) => ZKLibWeb.init(config);

class ZKLibWeb extends ZKLib {
  ZKLibWebTransporter? _transporter;
  List<void Function()> _listeners = [];
  ZKLibWeb._(super.config);

  static Future<ZKLibWeb> init(ZKLibConfig config) async {
    final lib = ZKLibWeb._(config);
    ZKLibWebTransporter? transporter =
        await ZKLibWebTransporter.init(config, lib._onTerminate);
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
