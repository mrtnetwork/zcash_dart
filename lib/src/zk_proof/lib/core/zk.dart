import 'dart:async';
import 'package:zcash_dart/src/sapling/proof/types.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';
import 'package:zcash_dart/src/sapling/proof/parameters.dart';
import 'package:zcash_dart/src/orchard/proof/types.dart';
import 'package:zcash_dart/src/zk_proof/lib/constant/constants.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';
import 'package:zcash_dart/src/zk_proof/lib/core/lib.dart'
    if (dart.library.io) '../io/zk_io.dart'
    if (dart.library.js_interop) '../web/zk_web.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/request.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/response.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/sapling_param_downloader.dart';

abstract class BaseZKLib with SaplingParamDownloaderHelper {
  const BaseZKLib();

  /// Sets spend parameters, downloading if necessary.
  Future<void> setSpendParams({List<int>? spendParamsBytes});

  /// Sets output parameters, downloading if necessary.
  Future<void> setOutputParams({List<int>? outputParamsBytes});

  void close();
}

/// Abstract class representing a zero-knowledge library interface.
/// Handles creation and verification of Orchard and Sapling proofs.
abstract class ZKLib extends BaseZKLib {
  /// Configuration for the ZK library.
  final ZKLibConfig config;
  const ZKLib(this.config);

  /// Initializes the library and checks for supported version.
  static Future<ZKLib> init(ZKLibConfig config) async {
    final lib = await initZkLib(config);
    final version = await lib.version();
    if (ZKLibConst.supoortedVersions.contains(version)) {
      return lib;
    }
    throw ZKLibException.operationFailed(
      "init",
      reason: "Unsuported lib version.",
    );
  }

  /// Sends a low-level request to the ZK library.
  ZKLibResponse sendRequestInternal(ZKRequest request);

  /// Parses a response with a given parser function, throws on failure.
  T sendRequest<RESPONSE extends ZKResponse, T extends Object?>(
    ZKRequest<RESPONSE, T> request,
  ) {
    final result = sendRequestInternal(request);
    final error = result.error;
    if (error != null) {
      throw ZKLibException.operationFailed("sendRequest", code: error);
    }
    final decode = ZKResponse.deserialize(bytes: result.payload);
    switch (decode) {
      case ZKResponseError(:final code, :final message):
        throw ZKLibException.operationFailed(
          "sendRequest",
          code: code,
          details: {"error": message},
        );
      default:
        return request.onResponse(decode.cast<RESPONSE>());
    }
  }

  /// Creates an Orchard proof from a list of inputs.
  FutureOr<List<int>> createOrchardProof(List<OrchardProofInputs> args) {
    final params = OrchardProofParams(args);
    return sendRequest(ZKRequestOrchardCreateActionProof(params));
  }

  /// Creates Sapling output proofs from a list of inputs.
  FutureOr<List<GrothProofBytes>> createOutputProofs(
    List<SaplingOutputParams> proofs,
  ) async {
    if (proofs.isEmpty) return [];
    await setOutputParams();
    List<GrothProofBytes> results = [];
    for (final i in proofs) {
      final payload = sendRequest(ZKRequestSaplingCreateOutputProof(i));
      results.add(payload);
    }
    return results;
  }

  /// Creates Sapling spend proofs from a list of inputs.
  FutureOr<List<GrothProofBytes>> createSpendProofs(
    List<SaplingSpendParams> proofs,
  ) async {
    if (proofs.isEmpty) return [];
    await setSpendParams();
    List<GrothProofBytes> results = [];
    for (final i in proofs) {
      final payload = sendRequest(ZKRequestSaplingCreateSpendProof(i));
      results.add(payload);
    }
    return results;
  }

  /// Verifies a list of Sapling proofs (output or spend).
  FutureOr<bool> _verifySaplingProof(
    ZcashSaplingParameter type,
    List<SaplingVerifyInputs> args,
  ) async {
    assert(args.isNotEmpty);
    if (args.isEmpty) return false;
    for (final i in args) {
      final verify = switch (type) {
        ZcashSaplingParameter.spend => sendRequest(
          ZKRequestSaplingVerifySpendProof(i),
        ),
        ZcashSaplingParameter.output => sendRequest(
          ZKRequestSaplingVerifyOutputProof(i),
        ),
      };
      if (!verify) return false;
    }
    return true;
  }

  /// Verifies Sapling output proofs.
  FutureOr<bool> verifyOutputProofs(List<SaplingVerifyInputs> args) async {
    await setOutputParams();
    return _verifySaplingProof(ZcashSaplingParameter.output, args);
  }

  /// Verifies Sapling spend proofs.
  FutureOr<bool> verifySpendProofs(List<SaplingVerifyInputs> args) async {
    await setSpendParams();
    return _verifySaplingProof(ZcashSaplingParameter.spend, args);
  }

  /// Verifies an Orchard proof.
  FutureOr<bool> verifyOrchardProof(OrchardVerifyProofInputs args) async {
    return await sendRequest(ZKRequestOrchardVerifyActionProof(args));
  }

  Future<bool> _hasSaplingParams(ZcashSaplingParameter params) async {
    return switch (params) {
      ZcashSaplingParameter.spend => await sendRequest(
        ZKRequestSaplingHasSpendParams(),
      ),
      ZcashSaplingParameter.output => await sendRequest(
        ZKRequestSaplingHasOutputParams(),
      ),
    };
  }

  /// Checks if spend parameters are already set.
  Future<bool> hasSpendParams() async {
    return _hasSaplingParams(ZcashSaplingParameter.spend);
  }

  /// Checks if output parameters are already set.
  Future<bool> hasOutputParams() async {
    return _hasSaplingParams(ZcashSaplingParameter.output);
  }

  /// set sapling parameters without any validation.
  Future<void> setSaplingParamsInternal({
    required ZcashSaplingParameter type,
    required List<int> bytes,
  });

  /// Sets spend parameters, downloading if necessary.
  @override
  Future<void> setSpendParams({List<int>? spendParamsBytes}) async {
    if (await hasSpendParams()) return;
    final bytes = await getAndValidateSaplingParams(
      type: ZcashSaplingParameter.spend,
      bytes: spendParamsBytes,
      spendUrl: config.saplingSpendParamsUri(),
      downloadService: config.saplingParamsDownloader,
    );
    return setSaplingParamsInternal(
      type: ZcashSaplingParameter.spend,
      bytes: bytes,
    );
  }

  /// Sets output parameters, downloading if necessary.
  @override
  Future<void> setOutputParams({List<int>? outputParamsBytes}) async {
    if (await hasOutputParams()) return;

    final bytes = await getAndValidateSaplingParams(
      type: ZcashSaplingParameter.output,
      bytes: outputParamsBytes,
      outputUrl: config.saplingOutputParamsUri(),
      downloadService: config.saplingParamsDownloader,
    );
    return setSaplingParamsInternal(
      type: ZcashSaplingParameter.output,
      bytes: bytes,
    );
  }

  /// Returns the version of the library.
  FutureOr<int> version() async {
    return await sendRequest(ZKRequestVersion());
  }

  FutureOr<void> clearProofParams() async {
    sendRequest(ZKRequestSaplingClearOutputParams());
    sendRequest(ZKRequestSaplingClearSpendParams());
    sendRequest(ZKRequestSaplingClearOrchardProvingKey());
  }

  /// Returns the version of the library.
  FutureOr<void> logging(
    bool enable, {
    ZKLibLogLevel level = ZKLibLogLevel.debug,
  }) async {
    sendRequest(ZKRequestLogging(enable: enable, level: level));
  }

  /// Closes the library and releases resources.
  @override
  void close() {}
}

// abstract class ZKLibDefault extends BaseZKLib {
//   static ZKLibDefault init(ZKLibConfig config, ZcashCryptoContext context) {
//     return initZkLibDefault(config, context);
//   }

//   DefaultOrchardProver? _orchard;
//   DefaultSaplingProver? _sapling;

//   final ZKLibConfig config;
//   final ZcashCryptoContext context;
//   final _lock = SafeAtomicLock();
//   ZKLibDefault(this.config, this.context);

//   Future<DefaultOrchardProver> getOrchardProver() async {
//     return _lock.run(() async {
//       return _orchard ??= DefaultOrchardProver.build(context);
//     });
//   }

//   @override
//   FutureOr<List<int>> createOrchardProof(List<OrchardProofInputs> args) async {
//     final orchard = await getOrchardProver();
//     return await orchard.createOrchardProof(args);
//   }

//   @override
//   FutureOr<List<GrothProofBytes>> createOutputProofs(
//     List<SaplingProofInputs<SaplingOutputParams>> proofs,
//   ) async {
//     if (proofs.isEmpty) return [];
//     final proover = await setOutputParams();
//     return proover.createOutputProofs(proofs);
//   }

//   @override
//   FutureOr<List<GrothProofBytes>> createSpendProofs(
//     List<SaplingProofInputs<SaplingSpendParams>> proofs,
//   ) async {
//     if (proofs.isEmpty) return [];
//     final proover = await setSpendParams();
//     return proover.createSpendProofs(proofs);
//   }

//   @override
//   FutureOr<bool> verifyOrchardProof(OrchardVerifyProofInputs args) async {
//     final orchard = (await getOrchardProver()).toVerifier();
//     return orchard.verifyOrchardProof(args);
//   }

//   @override
//   FutureOr<bool> verifyOutputProofs(List<SaplingVerifyInputs> args) async {
//     if (args.isEmpty) return true;
//     final proover = (await setOutputParams()).toVerifier();
//     return proover.verifyOutputProofs(args);
//   }

//   @override
//   FutureOr<bool> verifySpendProofs(List<SaplingVerifyInputs> args) async {
//     if (args.isEmpty) return true;
//     final proover = (await setOutputParams()).toVerifier();
//     return proover.verifySpendProofs(args);
//   }

//   @override
//   Future<DefaultSaplingProver> setOutputParams({List<int>? outputParamsBytes}) async {
//     return _lock.run(() async {
//       DefaultSaplingProver? sapling = _sapling;
//       if (sapling != null && sapling.outputParams != null) return sapling;
//       final bytes = await getAndValidateSaplingParams(
//         type: ZcashSaplingParameter.output,
//         bytes: outputParamsBytes,
//         outputUrl: config.saplingOutputParamsUri(),
//         downloadService: config.saplingParamsDownloader,
//       );
//       final params = Groth16Parameters.deserialize(bytes, check: false);
//       sapling = DefaultSaplingProver(
//         outputParams: params,
//         spendParams: sapling?.spendParams,
//       );
//       _sapling = sapling;
//       return sapling;
//     });
//   }

//   @override
//   Future<DefaultSaplingProver> setSpendParams({List<int>? spendParamsBytes}) async {
//     return _lock.run(() async {
//       DefaultSaplingProver? sapling = _sapling;
//       if (sapling != null && sapling.spendParams != null) return sapling;
//       final bytes = await getAndValidateSaplingParams(
//         type: ZcashSaplingParameter.spend,
//         bytes: spendParamsBytes,
//         outputUrl: config.saplingSpendParamsUri(),
//         downloadService: config.saplingParamsDownloader,
//       );
//       final params = Groth16Parameters.deserialize(bytes, check: false);
//       sapling = DefaultSaplingProver(
//         spendParams: params,
//         outputParams: sapling?.outputParams,
//       );
//       _sapling = sapling;
//       return sapling;
//     });
//   }
// }
