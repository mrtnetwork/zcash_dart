import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

import 'zcash.dart';

class DartZcashPluginException extends BaseDartZcashPluginException {
  const DartZcashPluginException(super.message, {super.details});

  factory DartZcashPluginException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zcashPluginError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return DartZcashPluginException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zcashPluginError;
}
