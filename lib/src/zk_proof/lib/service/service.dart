import 'package:zcash_dart/zcash.dart';

abstract mixin class ZCashDownloadService {
  Future<List<int>> doRequest(Uri uri, ZCashSaplingParameter type);
}
