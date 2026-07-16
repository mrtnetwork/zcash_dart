import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class ZcashCryptoContextException extends BaseDartZcashPluginException {
  const ZcashCryptoContextException(super.message, {super.details});
  factory ZcashCryptoContextException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.cryptoError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return ZcashCryptoContextException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.cryptoError;
}
