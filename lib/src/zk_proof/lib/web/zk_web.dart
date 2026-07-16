import 'package:zcash_dart/src/zk_proof/lib/core/zk.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/request.dart';
import 'package:zcash_dart/src/zk_proof/lib/web/transporter.dart';

Future<ZKLib> initZkLib(ZKLibConfig config) => ZKLibWeb.init(config);

class ZKLibWeb extends ZKLib {
  final ZKLibWebTransporter _transporter;
  ZKLibWeb._(super.config, ZKLibWebTransporter transport) : _transporter = transport;

  static Future<ZKLibWeb> init(ZKLibConfig config) async {
    ZKLibWebTransporter transporter = await ZKLibWebTransporter.init(config);
    return ZKLibWeb._(config, transporter);
  }

  @override
  ZKLibResponse sendRequestInternal(ZKRequest request) {
    return _transporter.sendRequest(request);
  }

  @override
  Future<void> setSaplingParamsInternal({
    required ZcashSaplingParameter type,
    required List<int> bytes,
  }) async {
    final result = _transporter.setupSaplingParams(payload: bytes, type: type);
    final error = result.error;
    if (error != null) {
      throw ZKLibException.operationFailed("setSaplingParamsInternal", code: error);
    }
  }

  @override
  void close() {
    _transporter.close();
    super.close();
  }
}
