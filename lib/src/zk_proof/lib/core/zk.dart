import 'dart:async';
import 'package:blockchain_utils/helper/helper.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/circuit.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/proof.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/verifier.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/prover.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/verifier.dart';
import 'package:zcash_dart/src/zk_proof/lib/constant/constants.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';
import 'package:zcash_dart/src/zk_proof/lib/core/lib.dart'
    if (dart.library.io) '../io/zk_io.dart'
    if (dart.library.js_interop) '../web/zk_web.dart';

/// Abstract class representing a zero-knowledge library interface.
/// Handles creation and verification of Orchard and Sapling proofs.
abstract class ZKLib
    implements
        BaseOrchardProver,
        BaseSaplingProver,
        BaseOrchardVerifier,
        BaseSaplingVerifier {
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
    throw ZKLibException.operationFailed("init",
        reason: "Unsuported lib version.");
  }

  /// Sends a low-level request to the ZK library.
  Future<List<int>> sendRequest(ZKLibRequestId id,
      {List<int> payload = const []});

  /// Parses a response with a given parser function, throws on failure.
  T _parseResponse<T>(List<int> payload, T? Function(List<int> bytes) parse) {
    try {
      final result = parse(payload);
      if (result != null) {
        return result;
      }
    } catch (_) {}
    throw ZKLibException("Unexpected response.");
  }

  /// Parses a boolean response from bytes (expects 0 or 1).
  bool? _parseBooleanResponse(List<int> bytes) {
    final verify = bytes[0];
    if (bytes.length == 1 && (verify == 0 || verify == 1)) {
      return verify.toBool;
    }
    return null;
  }

  /// Creates an Orchard proof from a list of inputs.
  @override
  FutureOr<List<int>> createOrchardProof(List<OrchardProofInputs> args) {
    final param = OrchardBatchProofInputs(args);
    return sendRequest(ZKLibRequestId.createOrchardProof,
        payload: param.toSerializeBytes());
  }

  /// Creates Sapling output proofs from a list of inputs.
  @override
  FutureOr<List<GrothProofBytes>> createOutputProofs(
      List<SaplingProofInputs<SaplingOutput>> proofs) async {
    await setOutputParams();
    List<GrothProofBytes> results = [];
    for (final i in proofs) {
      final payload = await sendRequest(ZKLibRequestId.createOutputProof,
          payload: i.circuit.toSerializeBytes());
      results.add(_parseResponse(
        payload,
        (bytes) {
          return GrothProofBytes(bytes);
        },
      ));
    }
    return results;
  }

  /// Creates Sapling spend proofs from a list of inputs.
  @override
  FutureOr<List<GrothProofBytes>> createSpendProofs(
      List<SaplingProofInputs<SaplingSpend>> proofs) async {
    await setSpendParams();
    List<GrothProofBytes> results = [];
    for (final i in proofs) {
      final payload = await sendRequest(ZKLibRequestId.createSpendProof,
          payload: i.circuit.toSerializeBytes());
      results.add(_parseResponse(
        payload,
        (bytes) {
          return GrothProofBytes(bytes);
        },
      ));
    }
    return results;
  }

  /// Verifies a list of Sapling proofs (output or spend).
  FutureOr<bool> _verifySaplingProof(
      ZKLibRequestId id, List<SaplingVerifyInputs> args) async {
    assert(id == ZKLibRequestId.verifyOutputProof ||
        id == ZKLibRequestId.verifySpendProof);
    assert(args.isNotEmpty);
    if (args.isEmpty) return false;
    List<bool> results = [];
    for (final i in args) {
      final payload = await sendRequest(id, payload: i.toSerializeBytes());
      results.add(_parseResponse(
        payload,
        (bytes) {
          return _parseBooleanResponse(bytes);
        },
      ));
    }
    return results.fold<bool>(true, (p, c) => p & c);
  }

  /// Verifies Sapling output proofs.
  @override
  FutureOr<bool> verifyOutputProofs(List<SaplingVerifyInputs> args) async {
    await setOutputParams();
    return _verifySaplingProof(ZKLibRequestId.verifyOutputProof, args);
  }

  /// Verifies Sapling spend proofs.
  @override
  FutureOr<bool> verifySpendProofs(List<SaplingVerifyInputs> args) async {
    await setSpendParams();
    return _verifySaplingProof(ZKLibRequestId.verifySpendProof, args);
  }

  /// Verifies an Orchard proof.
  @override
  FutureOr<bool> verifyOrchardProof(OrchardVerifyInputs args) async {
    final payload = await sendRequest(ZKLibRequestId.verifyOrchardProof,
        payload: args.toSerializeBytes());
    return _parseResponse(
      payload,
      (bytes) => _parseBooleanResponse(bytes),
    );
  }

  /// Checks if spend parameters are already set.
  Future<bool> hasSpendParams() async {
    final payload = await sendRequest(ZKLibRequestId.hasSpendParams);
    return _parseResponse(
      payload,
      (bytes) => _parseBooleanResponse(bytes),
    );
  }

  /// Checks if output parameters are already set.
  Future<bool> hasOutputParams() async {
    final payload = await sendRequest(ZKLibRequestId.hasOutputParams);
    return _parseResponse(
      payload,
      (bytes) => _parseBooleanResponse(bytes),
    );
  }

  /// Builds default download URL for Sapling parameters.
  Uri _buildDefaultUrl(ZKLibRequestId id, int part) {
    final url = switch (id) {
      ZKLibRequestId.setSpendParams =>
        "${ZKLibConst.downloadUrl}/${ZKLibConst.saplingSpendName}.part.$part",
      _ =>
        "${ZKLibConst.downloadUrl}/${ZKLibConst.saplingOutputName}.part.$part",
    };
    return Uri.parse(url);
  }

  /// Determines the URI for parameter downloads, considering configuration.
  Uri? _getUri(ZKLibRequestId id, int part) {
    final spendUrl = config.saplingSpendParamsUri();
    final outputUrl = config.saplingOutputParamsUri();
    final lastPart = part == 2;
    final url = switch (id) {
      ZKLibRequestId.setSpendParams => (lastPart && spendUrl != null)
          ? null
          : spendUrl ?? _buildDefaultUrl(id, part),
      _ => (lastPart && outputUrl != null)
          ? null
          : outputUrl ?? _buildDefaultUrl(id, part),
    };
    return url;
  }

  /// Retrieves parameter bytes, downloading if needed.
  Future<List<int>> _getParamBytes(ZKLibRequestId id, List<int>? bytes) async {
    String operation = switch (id) {
      ZKLibRequestId.setSpendParams => "setSpendParams",
      _ => "setOutputParams"
    };
    ZCashSaplingParameter type = switch (id) {
      ZKLibRequestId.setSpendParams => ZCashSaplingParameter.spend,
      _ => ZCashSaplingParameter.output
    };
    bool hasValidLegth(List<int> bytes) {
      return switch (id) {
        ZKLibRequestId.setSpendParams =>
          ZKLibConst.saplingSpendBytes.contains(bytes.length),
        ZKLibRequestId.setOutputParams =>
          ZKLibConst.saplingOutputBytes.contains(bytes.length),
        _ => false
      };
    }

    if (bytes == null) {
      final service = config.saplingParamsDownloader;
      if (service == null) {
        throw ZKLibException.operationFailed(
          operation,
          reason: "Sapling params unavailable: no downloader configured.",
        );
      }
      final part1Url = _getUri(id, 1)!;
      bytes = await service.doRequest(part1Url, type);
      if (!hasValidLegth(bytes)) {
        final part2Url = _getUri(id, 2);
        if (part2Url != null) {
          final p2Bytes = await service.doRequest(part1Url, type);
          bytes = [...bytes, ...p2Bytes];
        }
      }
    }
    if (!hasValidLegth(bytes)) {
      throw ZKLibException.operationFailed(operation,
          reason: "Invalid sapling param bytes length.");
    }
    return bytes;
  }

  /// Sets spend parameters, downloading if necessary.
  Future<void> setSpendParams({List<int>? spendParamsBytes}) async {
    if (await hasSpendParams()) return;
    final bytes =
        await _getParamBytes(ZKLibRequestId.setSpendParams, spendParamsBytes);
    await sendRequest(ZKLibRequestId.setSpendParams, payload: bytes);
    assert(await hasSpendParams(), "unexpected missing spend params");
  }

  /// Sets output parameters, downloading if necessary.
  Future<void> setOutputParams({List<int>? outputParamsBytes}) async {
    if (await hasOutputParams()) return;
    final bytes =
        await _getParamBytes(ZKLibRequestId.setOutputParams, outputParamsBytes);
    await sendRequest(ZKLibRequestId.setOutputParams, payload: bytes);
    assert(await hasOutputParams(), "unexpected missing output params");
  }

  /// Returns the version of the library.
  FutureOr<int> version() async {
    final payload = await sendRequest(ZKLibRequestId.version);
    return _parseResponse(payload, (bytes) {
      if (bytes.length == 1) return bytes[0];
      return null;
    });
  }

  /// Closes the library and releases resources.
  void close() {}

  /// Registers a callback to be called on library termination.
  void addTerminateListener(void Function() listener);
}
