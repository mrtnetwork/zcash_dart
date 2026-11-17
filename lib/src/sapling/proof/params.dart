import 'package:blockchain_utils/blockchain_utils.dart';

/// Sapling circuit kind (relocated from the removed `zk_proof` bridge).
enum ZcashSaplingParameter { spend, output }

/// Sapling Groth16 parameter locations and sizes (relocated from the removed
/// `zk_proof` bridge — the new proving backend takes params *bytes*, so the
/// download step stays but no longer belongs to a native ZK library).
abstract final class SaplingParams {
  static const String spendName = 'sapling-spend.params';
  static const String outputName = 'sapling-output.params';
  static const int spendBytesLength = 47958396;
  static const int outputBytesLength = 3592860;

  /// Accepted lengths (second entry = historical file without trailing hash).
  static const List<int> spendBytes = [
    spendBytesLength,
    spendBytesLength - 52836,
  ];
  static const List<int> outputBytes = [
    outputBytesLength,
    outputBytesLength - 52836,
  ];

  static const String downloadUrl = 'https://download.z.cash/downloads';

  static List<String> downloadLinks(
    ZcashSaplingParameter type, {
    String? downloadUrl,
  }) {
    final url = downloadUrl ?? SaplingParams.downloadUrl;
    return switch (type) {
      ZcashSaplingParameter.spend => [
        '$url/$spendName.part.1',
        '$url/$spendName.part.2',
      ],
      _ => ['$url/$outputName.part.1', '$url/$outputName.part.2'],
    };
  }

  static bool isValidParametersBytes(
    ZcashSaplingParameter type,
    List<int> bytes,
  ) {
    return switch (type) {
      ZcashSaplingParameter.spend => spendBytes.contains(bytes.length),
      _ => outputBytes.contains(bytes.length),
    };
  }
}

/// Minimal download transport (same shape as the old bridge's service).
abstract mixin class ZcashDownloadService {
  Future<List<int>> doRequest(Uri uri, ZcashSaplingParameter type);
}

/// Fetch (or accept) Sapling params bytes, validating lengths.
///
/// Either [bytes] or [downloadService] (+ optional URL overrides) must be
/// provided. Throws [BuError] when unavailable or invalid.
abstract final class SaplingParamFetcher {
  static Uri _defaultUrl(ZcashSaplingParameter type, int part) {
    final name = switch (type) {
      ZcashSaplingParameter.spend => SaplingParams.spendName,
      _ => SaplingParams.outputName,
    };
    return Uri.parse('${SaplingParams.downloadUrl}/$name.part.$part');
  }

  static Future<List<int>> getAndValidate({
    required ZcashSaplingParameter type,
    List<int>? bytes,
    Uri? spendUrl,
    Uri? outputUrl,
    ZcashDownloadService? downloadService,
  }) async {
    if (bytes == null) {
      if (downloadService == null) {
        throw BuError(
          DefaultErrorType.invalidState,
          'Sapling params unavailable: no downloader configured.',
        );
      }
      final part1 = await downloadService.doRequest(
        spendUrl ??
            (type == ZcashSaplingParameter.spend
                ? _defaultUrl(type, 1)
                : outputUrl ?? _defaultUrl(type, 1)),
        type,
      );
      bytes = part1;
      if (!SaplingParams.isValidParametersBytes(type, bytes)) {
        // Historical split layout: part.1 short + full part.2 appended.
        final part2uri =
            type == ZcashSaplingParameter.spend
                ? (spendUrl == null ? null : _defaultUrl(type, 2))
                : (outputUrl == null ? null : _defaultUrl(type, 2));
        if (part2uri != null) {
          final p2 = await downloadService.doRequest(part2uri, type);
          bytes = [...bytes, ...p2];
        }
      }
    }
    if (!SaplingParams.isValidParametersBytes(type, bytes)) {
      throw BuError(
        DefaultErrorType.invalidLength,
        'Invalid sapling param bytes length.',
      );
    }
    return bytes;
  }
}
