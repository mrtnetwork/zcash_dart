import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

abstract mixin class ZKLibTransporter {
  Future<ZKLibResponse> sendRequest(ZKLibRequestId id,
      {List<int> payload = const []});
}
