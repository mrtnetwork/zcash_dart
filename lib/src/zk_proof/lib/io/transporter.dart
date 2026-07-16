import 'dart:async';
import 'dart:ffi';
import 'package:blockchain_utils/helper/extensions/extensions.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/request.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/transporter.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

import 'ffi.dart';

abstract class ZKLibIoTransporter implements ZKLibTransporter {
  static Future<ZKLibIoTransporter?> init(ZKLibConfig config) async {
    final uri = config.libUri;
    if (uri == null) return null;
    return ZKLibIoSyncTransporter.fromConfig(uri);
  }
}

class ZKLibIoSyncTransporter implements ZKLibIoTransporter {
  final DynamicLibrary library;
  final ZKRequestDart newRequest;
  final ZKRequestSetupSaplingParamsDart setupSaplingSpendParams;
  final ZKRequestSetupSaplingParamsDart setupSaplingOutputParams;
  final FreeBytesDart freeBytes;
  final String libUrl;
  ZKLibIoSyncTransporter(this.library, this.libUrl)
    : newRequest = library.lookupFunction<ZKRequestNative, ZKRequestDart>(
        'new_request_c',
      ),
      setupSaplingOutputParams = library.lookupFunction<
        ZKRequestSetupSaplingParamsNative,
        ZKRequestSetupSaplingParamsDart
      >('setup_sapling_output_params'),
      setupSaplingSpendParams = library.lookupFunction<
        ZKRequestSetupSaplingParamsNative,
        ZKRequestSetupSaplingParamsDart
      >('setup_sapling_spend_params'),
      freeBytes = library.lookupFunction<FreeBytesNative, FreeBytesDart>('free_bytes');

  static ZKLibIoSyncTransporter fromConfig(String uri) {
    try {
      return ZKLibIoSyncTransporter(DynamicLibrary.open(uri), uri);
    } catch (e) {
      throw ZKLibException.operationFailed(
        "DynamicLibrary.open",
        details: {"error": e.toString()},
      );
    }
  }

  @override
  ZKLibResponse sendRequest(ZKRequest request) {
    final payload = request.toCbor().encode();
    final payloadPtr = calloc<Uint8>(payload.length);
    final payloadList = payloadPtr.asTypedList(payload.length);
    payloadList.setAll(0, payload);
    final outPtr = calloc<Pointer<Uint8>>();
    final outLen = calloc<Uint64>();
    final code = newRequest(payloadPtr, payload.length, outPtr, outLen);
    try {
      if (code != 0) {
        return ZKLibResponse(error: ZKLibResponseCode.fromCode(code));
      }
      return ZKLibResponse(
        error: null,
        payload: outPtr.value.asTypedList(outLen.value).clone(immutable: true),
      );
    } finally {
      freeBytes(outPtr.value, outLen.value);
      calloc.free(outPtr);
      calloc.free(outLen);
    }
  }

  @override
  ZKLibResponse setupSaplingParams({
    required List<int> payload,
    required ZcashSaplingParameter type,
  }) {
    final payloadPtr = calloc<Uint8>(payload.length);
    final payloadList = payloadPtr.asTypedList(payload.length);
    payloadList.setAll(0, payload);
    final code = switch (type) {
      ZcashSaplingParameter.spend => setupSaplingSpendParams(payloadPtr, payload.length),
      ZcashSaplingParameter.output => setupSaplingOutputParams(
        payloadPtr,
        payload.length,
      ),
    };
    if (code != 0) {
      return ZKLibResponse(error: ZKLibResponseCode.fromCode(code));
    }
    return ZKLibResponse(error: null);
  }

  @override
  void close() {
    library.close();
  }
}
