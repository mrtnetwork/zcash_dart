import 'package:zcash_dart/src/zk_proof/lib/constant/constants.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/service/service.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

abstract mixin class SaplingParamDownloaderHelper {
  /// Builds default download URL for Sapling parameters.
  Uri _buildDefaultUrl(ZcashSaplingParameter type, int part) {
    final url = switch (type) {
      ZcashSaplingParameter.spend =>
        "${ZKLibConst.downloadUrl}/${ZKLibConst.saplingSpendName}.part.$part",
      _ =>
        "${ZKLibConst.downloadUrl}/${ZKLibConst.saplingOutputName}.part.$part",
    };
    return Uri.parse(url);
  }

  /// Determines the URI for parameter downloads, considering configuration.
  Uri? _getUri({
    required ZcashSaplingParameter type,
    required int part,
    Uri? spendUrl,
    Uri? outputUrl,
  }) {
    final lastPart = part == 2;
    final url = switch (type) {
      ZcashSaplingParameter.spend =>
        (lastPart && spendUrl != null)
            ? null
            : spendUrl ?? _buildDefaultUrl(type, part),
      _ =>
        (lastPart && outputUrl != null)
            ? null
            : outputUrl ?? _buildDefaultUrl(type, part),
    };
    return url;
  }

  static bool isValidParametersBytes(
    ZcashSaplingParameter type,
    List<int> bytes,
  ) {
    return switch (type) {
      ZcashSaplingParameter.spend => ZKLibConst.saplingSpendBytes.contains(
        bytes.length,
      ),
      ZcashSaplingParameter.output => ZKLibConst.saplingOutputBytes.contains(
        bytes.length,
      ),
    };
  }

  Future<List<int>> getAndValidateSaplingParams({
    required ZcashSaplingParameter type,
    List<int>? bytes,
    Uri? spendUrl,
    Uri? outputUrl,
    ZcashDownloadService? downloadService,
  }) async {
    String operation = switch (type) {
      ZcashSaplingParameter.spend => "setSpendParams",
      _ => "setOutputParams",
    };
    bool hasValidLegth(List<int> bytes) {
      return isValidParametersBytes(type, bytes);
    }

    if (bytes == null) {
      // final service = config?.saplingParamsDownloader;
      if (downloadService == null) {
        throw ZKLibException.operationFailed(
          operation,
          reason: "Sapling params unavailable: no downloader configured.",
        );
      }
      final part1Url =
          _getUri(
            type: type,
            part: 1,
            spendUrl: spendUrl,
            outputUrl: outputUrl,
          )!;
      bytes = await downloadService.doRequest(part1Url, type);
      if (!hasValidLegth(bytes)) {
        final part2Url = _getUri(
          type: type,
          part: 2,
          spendUrl: spendUrl,
          outputUrl: outputUrl,
        );
        if (part2Url != null) {
          final p2Bytes = await downloadService.doRequest(part1Url, type);
          bytes = [...bytes, ...p2Bytes];
        }
      }
    }
    if (!hasValidLegth(bytes)) {
      throw ZKLibException.operationFailed(
        operation,
        reason: "Invalid sapling param bytes length.",
      );
    }
    return bytes;
  }
}
