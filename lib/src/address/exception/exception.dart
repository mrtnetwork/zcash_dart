import 'package:blockchain_utils/bip/zcash/src/types.dart';
import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class ZcashAddressException extends BaseDartZcashPluginException {
  const ZcashAddressException(super.message, {super.details});
  static ZcashAddressException get invalidUnifiedReceivers =>
      ZcashAddressException("Invalid unified address receivers.");
  static ZcashAddressException mismatchNetwork({
    required ZcashNetwork network,
    required ZcashNetwork expected,
  }) => ZcashAddressException(
    "Network mismatch: address belongs to a different network.",
    details: {"network": network.name, "expected": expected.name},
  );

  factory ZcashAddressException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zcashAddressError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return ZcashAddressException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zcashAddressError;
}
