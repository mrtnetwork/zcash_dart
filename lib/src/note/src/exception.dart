import 'package:zcash_dart/src/exception/exception.dart';

class NoteEncryptionException extends DartZCashPluginException {
  const NoteEncryptionException(super.message, {super.details});

  static NoteEncryptionException failed(String operation,
      {Map<String, dynamic>? details, String? reason}) {
    return NoteEncryptionException("Note operation failed during $operation.",
        details: {...details ?? {}, "reason": reason});
  }
}
