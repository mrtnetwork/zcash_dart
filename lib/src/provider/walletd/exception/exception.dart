import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class WalletdException extends BaseDartZcashPluginException {
  const WalletdException(super.message, {super.details});

  static WalletdException failed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return WalletdException(
      "Opearion failed during $operation",
      details: details,
    );
  }

  factory WalletdException.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.walletdError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return WalletdException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.walletdError;
}
