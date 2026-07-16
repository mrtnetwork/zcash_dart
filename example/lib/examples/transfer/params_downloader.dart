import 'package:zcash_dart/zcash.dart';
import 'package:http/http.dart' as http;

class SaplingParamDownloer implements ZcashDownloadService {
  const SaplingParamDownloer();
  @override
  Future<List<int>> doRequest(Uri uri, ZcashSaplingParameter type) async {
    final client = http.Client();
    try {
      final response = await client.get(uri);
      assert(response.statusCode == 200);
      return response.bodyBytes;
    } finally {
      client.close();
    }
  }
}
