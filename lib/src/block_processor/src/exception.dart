import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class ZcashBlockScannerException extends BaseDartZcashPluginException {
  const ZcashBlockScannerException(super.message, {super.details});
  factory ZcashBlockScannerException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.blockScannerError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return ZcashBlockScannerException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.blockScannerError;
  static ZcashBlockScannerException failed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return ZcashBlockScannerException(
      "Block scan failed during $operation",
      details: {"reason": reason, ...details ?? {}}.notNullValue,
    );
  }

  static ZcashBlockScannerException invalidCompact(
    String elem, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return ZcashBlockScannerException(
      "Invalid compact $elem object.",
      details: {"reason": reason, ...details ?? {}}.notNullValue,
    );
  }
}
