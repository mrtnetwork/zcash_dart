import 'dart:io';

import 'package:zcash_dart/src/zk_proof/lib/core/zk.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/io/transporter.dart';
import 'package:zcash_dart/src/zk_proof/lib/service/service.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/request.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/sapling_param_downloader.dart';

Future<ZKLib> initZkLib(ZKLibConfig config) => ZKLibIO.init(config);

class ZKLibIO extends ZKLib {
  ZKLibIoTransporter? _transporter;
  ZKLibIO(super.config, ZKLibIoTransporter transport)
    : _transporter = transport;

  static Future<ZKLibIO> init(ZKLibConfig config) async {
    ZKLibIoTransporter? transporter = await ZKLibIoTransporter.init(config);
    if (transporter == null) throw ZKLibException("Unsupported platform.");
    return ZKLibIO(config, transporter);
  }

  @override
  Future<List<int>> getAndValidateSaplingParams({
    required ZcashSaplingParameter type,
    List<int>? bytes,
    Uri? spendUrl,
    Uri? outputUrl,
    ZcashDownloadService? downloadService,
  }) async {
    final sapligFile = switch (type) {
      ZcashSaplingParameter.spend => config.saplingSpendParamsFileUri,
      ZcashSaplingParameter.output => config.saplingOutputParamsFileUri,
    };
    if (bytes == null) {
      if (sapligFile != null && File(sapligFile).existsSync()) {
        final bytes = File(sapligFile).readAsBytesSync();
        if (SaplingParamDownloaderHelper.isValidParametersBytes(type, bytes)) {
          return bytes;
        }
      }
    }
    final result = await super.getAndValidateSaplingParams(
      type: type,
      bytes: bytes,
      spendUrl: spendUrl,
      outputUrl: outputUrl,
      downloadService: downloadService,
    );
    if (sapligFile != null) {
      final file = File(sapligFile)..create(recursive: true);
      file.writeAsBytesSync(result);
    }
    return result;
  }

  @override
  ZKLibResponse sendRequestInternal(ZKRequest request) {
    final transporter = _transporter;
    if (transporter == null) {
      throw ZKLibException.operationFailed(
        "sendRequest",
        reason: "ZKLib already closed.",
      );
    }
    return transporter.sendRequest(request);
  }

  @override
  Future<void> setSaplingParamsInternal({
    required ZcashSaplingParameter type,
    required List<int> bytes,
  }) async {
    final transporter = _transporter;
    if (transporter == null) {
      throw ZKLibException.operationFailed(
        "setSaplingParamsInternal",
        reason: "ZKLib already closed.",
      );
    }
    final result = transporter.setupSaplingParams(payload: bytes, type: type);
    final error = result.error;
    if (error != null) {
      throw ZKLibException.operationFailed("sendRequest", code: error);
    }
  }

  @override
  void close() {
    _transporter?.close();
    _transporter = null;
    super.close();
  }
}

// class ZKLibIoDefault extends ZKLibDefault {
//   ZKLibIoDefault(super.config, super.context);

//   @override
//   Future<List<int>> getAndValidateSaplingParams({
//     required ZcashSaplingParameter type,
//     List<int>? bytes,
//     Uri? spendUrl,
//     Uri? outputUrl,
//     ZcashDownloadService? downloadService,
//   }) async {
//     final sapligFile = switch (type) {
//       ZcashSaplingParameter.spend => config.saplingSpendParamsFileUri,
//       ZcashSaplingParameter.output => config.saplingOutputParamsFileUri,
//     };
//     if (bytes == null) {
//       if (sapligFile != null && File(sapligFile).existsSync()) {
//         final bytes = File(sapligFile).readAsBytesSync();
//         if (SaplingParamDownloaderHelper.isValidParametersBytes(type, bytes)) {
//           return bytes;
//         }
//       }
//     }

//     final result = await super.getAndValidateSaplingParams(
//       type: type,
//       bytes: bytes,
//       spendUrl: spendUrl,
//       outputUrl: outputUrl,
//       downloadService: downloadService,
//     );
//     if (sapligFile != null) {
//       final file = File(sapligFile)..create(recursive: true);
//       file.writeAsBytesSync(result);
//     }
//     return result;
//   }

//   @override
//   void close() {}
// }
