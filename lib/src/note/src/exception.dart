import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class NoteEncryptionException extends BaseDartZcashPluginException {
  const NoteEncryptionException(super.message, {super.details});

  static NoteEncryptionException failed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) {
    return NoteEncryptionException(
      "Note operation failed during $operation.",
      details: {...details ?? {}, "reason": reason},
    );
  }

  factory NoteEncryptionException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.noteError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return NoteEncryptionException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.noteError;
}
