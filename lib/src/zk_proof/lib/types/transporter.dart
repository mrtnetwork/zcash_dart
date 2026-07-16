import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/request.dart';

abstract mixin class ZKLibTransporter {
  void close();
  ZKLibResponse sendRequest(ZKRequest request);
  ZKLibResponse setupSaplingParams({
    required List<int> payload,
    required ZcashSaplingParameter type,
  });
}
