import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class TransparentExceptoion extends BaseDartZcashPluginException {
  const TransparentExceptoion(super.message, {super.details});
  static TransparentExceptoion operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return TransparentExceptoion(
      "Transparent operation failure during $operation",
      details: details,
    );
  }

  static TransparentExceptoion multisigFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return TransparentExceptoion(
      "Transparent multisig address generation failed.",
      details: details,
    );
  }

  factory TransparentExceptoion.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.transparentError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return TransparentExceptoion(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.transparentError;
}
