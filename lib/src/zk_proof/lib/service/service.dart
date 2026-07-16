import 'package:zcash_dart/zcash.dart';

abstract mixin class ZcashDownloadService {
  Future<List<int>> doRequest(Uri uri, ZcashSaplingParameter type);
}
