import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'types.dart';

class NoteEncryptionConst {
  static const int compactNoteSize = 1 + 11 + 8 + 32;
  static const int memoLength = 512;

  /// The size of NotePlaintextBytes.
  static const int notePlaintextSize = compactNoteSize + memoLength;

  /// The size of OutPlaintextBytes.
  /// pk_d (32) + esk (32)
  static const int outPlaintextSize = 32 + 32;

  static const int aeadTagSize = 16;

  /// The size of an encrypted note plaintext.
  static const int encCiphertextSize = notePlaintextSize + aeadTagSize;

  /// The size of an encrypted outgoing plaintext.
  static const int outCiphertextSize = outPlaintextSize + aeadTagSize;

  static const int outGoingCypherKey = 32;

  static const int noteCommitmentTreeDepth = 32;

  static const int shardHeight = 16;
}

abstract class NoteDomain<
    ENCSECRET extends Object,
    ENCSECRETAGGPK extends Object,
    DECPK,
    DEC extends Object,
    ENC extends Object,
    NOTE extends Object,
    RECIPIENT extends ShieldAddress,
    DIVERSIFIEDTRANSMISSIONKEY extends Object,
    INCOMINGVIEWINGKEY extends Object,
    OUTGOINGVIEWINGKEY extends Object,
    VALUECOMMITMENT extends Object,
    EXTRACTEDCOMMITMENT extends Object,
    OUTPUT extends ShieldedOutput<EXTRACTEDCOMMITMENT>,
    ENCNOTE extends NoteEncryption<ENCSECRET, ENCSECRETAGGPK, NOTE,
        OUTGOINGVIEWINGKEY>> {
  final List<int> _nonce = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  ZCashCryptoContext get context;

  /// Derives the EphemeralSecretKey corresponding to this note.
  ENCSECRET? deriveEsk(NOTE note);

  /// Extracts the DiversifiedTransmissionKey from the note.
  DIVERSIFIEDTRANSMISSIONKEY getPkD(NOTE note);

  /// Derives EphemeralPublicKey from esk and the note's diversifier.
  ENCSECRETAGGPK kaDerivePublic(NOTE note, ENCSECRET esk);

  /// Derives the SharedSecret from the sender's information during note encryption.
  ENC kaAgreeEnc(ENCSECRET esk, DIVERSIFIEDTRANSMISSIONKEY pkD);

  /// Derives the SharedSecret from the recipient's information during note trial decryption.
  DEC kaAgreeDec(INCOMINGVIEWINGKEY ivk, DECPK epk);

  /// Derives the SymmetricKey used to encrypt the note plaintext.
  List<int> kdf(DEC secret, EphemeralKeyBytes ephemeralKey);
  List<int> encKdf(
    ENC secret,
    EphemeralKeyBytes ephemeralKey,
  );

  /// Encodes the given Note and Memo as a note plaintext.
  List<int> notePlaintextBytes(NOTE note, List<int> memo);

  /// Derives the OutgoingCipherKey for an encrypted note.
  List<int> deriveOck(
    OUTGOINGVIEWINGKEY ovk,
    VALUECOMMITMENT cv,
    EXTRACTEDCOMMITMENT cm,
    EphemeralKeyBytes ephemeralKey,
  );

  /// Encodes the outgoing plaintext for the given note.
  List<int> outgoingPlaintextBytes(NOTE note, ENCSECRET esk);

  // /// Returns the byte encoding of the given EphemeralPublicKey.
  EphemeralKeyBytes epkBytes(ENCSECRETAGGPK epk);

  /// Attempts to parse EphemeralPublicKey from bytes.
  DECPK? decEpk(EphemeralKeyBytes ephemeralKey);

  /// Derives the ExtractedCommitment for this note.
  EXTRACTEDCOMMITMENT cmstar(NOTE note);

  /// Parses the given note plaintext from the recipient's perspective.
  (NOTE, RECIPIENT)? parseNotePlaintextWithoutMemoIvk(
      INCOMINGVIEWINGKEY ivk, List<int> plaintext, OUTPUT output);

  /// Parses the given note plaintext from the sender's perspective.
  (NOTE, RECIPIENT)? parseNotePlaintextWithoutMemoOvk(
      DIVERSIFIEDTRANSMISSIONKEY pkD, List<int> plaintext, OUTPUT output);

  /// Extracts the memo field from the given note plaintext.
  List<int> extractMemo(List<int> plaintext);

  /// Parses the DiversifiedTransmissionKey field of the outgoing plaintext.
  DIVERSIFIEDTRANSMISSIONKEY? extractPkD(List<int> outPlaintextx);

  /// Parses the EphemeralSecretKey field of the outgoing plaintext.
  ENCSECRET? extractEsk(List<int> outPlaintext);

  /// compact memo
  (List<int>, List<int>)? splitPlaintextAtMemo(List<int> plaintext) {
    if (plaintext.length < NoteEncryptionConst.memoLength) {
      return null;
    }

    final int splitPoint = plaintext.length - NoteEncryptionConst.memoLength;
    final List<int> compactPart = plaintext.sublist(0, splitPoint);
    final List<int> memoPart = plaintext.sublist(splitPoint);

    return (compactPart, memoPart);
  }

  (NOTE, RECIPIENT)? _parseNotePlaintextWithoutMemoIvk({
    required INCOMINGVIEWINGKEY ivk,
    required EphemeralKeyBytes ephemeralKey,
    required EXTRACTEDCOMMITMENT cm,
    required List<int> plaintext,
    required OUTPUT output,
  }) {
    final note = parseNotePlaintextWithoutMemoIvk(ivk, plaintext, output);
    if (note == null) return null;
    if (_checkNoteValidaty(note: note.$1, ephemeralKey: ephemeralKey, cm: cm)) {
      return note;
    }
    return null;
  }

  bool _checkNoteValidaty({
    required NOTE note,
    required EphemeralKeyBytes ephemeralKey,
    required EXTRACTEDCOMMITMENT cm,
  }) {
    final gCm = cmstar(note);
    if (gCm == cm) {
      final esk = deriveEsk(note);
      if (esk == null) return true;
      final epk = epkBytes(kaDerivePublic(note, esk));
      if (epk == ephemeralKey) {
        return true;
      }
    }
    return false;
  }

  (NOTE, RECIPIENT)? tryCompactNoteDecryptionInner(
      {required INCOMINGVIEWINGKEY ivk,
      required EphemeralKeyBytes ephemeralKey,
      required OUTPUT output,
      required List<int> key}) {
    final plaintext = output.encCiphertextCompact;
    final result = List<int>.filled(plaintext.length, 0);
    ChaCha20.streamXOR(key, _nonce, plaintext, result, seekBytes: 64);
    return _parseNotePlaintextWithoutMemoIvk(
        ivk: ivk,
        ephemeralKey: ephemeralKey,
        cm: output.cmstar(),
        plaintext: result,
        output: output);
  }

  (NOTE, RECIPIENT, List<int>)? tryNoteDecryptionInner(
      {required INCOMINGVIEWINGKEY ivk,
      required EphemeralKeyBytes ephemeralKey,
      required OUTPUT output,
      required List<int> key}) {
    final plain = output.splitCiphertextAtTag();
    if (plain == null) return null;
    final dec = ChaCha20Poly1305(key).decrypt(_nonce, plain.$2);
    if (dec == null) return null;
    final compact = splitPlaintextAtMemo(dec);
    if (compact == null) return null;
    final result = _parseNotePlaintextWithoutMemoIvk(
        ivk: ivk,
        plaintext: compact.$1,
        cm: output.cmstar(),
        ephemeralKey: ephemeralKey,
        output: output);
    if (result == null) return null;
    return (result.$1, result.$2, compact.$2);
  }

  (NOTE, RECIPIENT, List<int>)? tryNoteDecryption(
      {required INCOMINGVIEWINGKEY ivk, required OUTPUT output}) {
    final ephemeralKey = output.ephemeralKey;
    final epk = decEpk(ephemeralKey);
    if (epk == null) return null;
    final secret = kaAgreeDec(ivk, epk);
    final key = kdf(secret, ephemeralKey);
    return tryNoteDecryptionInner(
        ivk: ivk, ephemeralKey: ephemeralKey, output: output, key: key);
  }

  List<BatchOutputDecryptionResult<EXTRACTEDCOMMITMENT, O, NOTE, RECIPIENT>>
      batchOutputCompactNoteDecryption<O extends OUTPUT>(
          {required INCOMINGVIEWINGKEY ivk, required List<O> outputs}) {
    List<BatchOutputDecryptionResult<EXTRACTEDCOMMITMENT, O, NOTE, RECIPIENT>>
        result = [];
    for (final output in outputs) {
      final decrypt = tryCompactNoteDecryption(ivk: ivk, output: output);
      if (decrypt == null) continue;
      result.add(BatchOutputDecryptionResult(
          output: output, note: decrypt.$1, recipient: decrypt.$2));
    }
    return result;
  }

  BatchIVKDecryptionResult<INCOMINGVIEWINGKEY, NOTE, RECIPIENT>?
      batchIvkCompactNoteDecryption(
          {required List<INCOMINGVIEWINGKEY> ivks, required OUTPUT output}) {
    for (final ivk in ivks) {
      final decrypt = tryCompactNoteDecryption(ivk: ivk, output: output);
      if (decrypt != null) {
        return BatchIVKDecryptionResult(
            ivk: ivk, note: decrypt.$1, recipient: decrypt.$2);
      }
    }
    return null;
  }

  (NOTE, RECIPIENT)? tryCompactNoteDecryption(
      {required INCOMINGVIEWINGKEY ivk, required OUTPUT output}) {
    final ephemeralKey = output.ephemeralKey;
    final epk = decEpk(ephemeralKey);
    if (epk == null) return null;
    final secret = kaAgreeDec(ivk, epk);
    final key = kdf(secret, ephemeralKey);
    return tryCompactNoteDecryptionInner(
        ivk: ivk, ephemeralKey: ephemeralKey, output: output, key: key);
  }

  (NOTE, RECIPIENT, List<int>)? tryOutputRecoveryWithOvk(
      {required OUTGOINGVIEWINGKEY ovk,
      required OUTPUT output,
      required List<int> outCiphertext,
      required VALUECOMMITMENT cv}) {
    final ock = deriveOck(ovk, cv, output.cmstar(), output.ephemeralKey);
    return tryOutputRecoveryWithOck(
        ock: ock, output: output, outCiphertext: outCiphertext);
  }

  (NOTE, RECIPIENT, List<int>)? tryOutputRecoveryWithOck(
      {required List<int> ock,
      required OUTPUT output,
      required List<int> outCiphertext}) {
    assert(ock.length == NoteEncryptionConst.outGoingCypherKey);
    assert(outCiphertext.length == NoteEncryptionConst.outCiphertextSize);
    if (ock.length != NoteEncryptionConst.outGoingCypherKey ||
        outCiphertext.length != NoteEncryptionConst.outCiphertextSize) {
      return null;
    }
    final dec = ChaCha20Poly1305(ock).decrypt(_nonce, outCiphertext);
    if (dec == null) return null;
    final pkD = extractPkD(dec);
    final esk = extractEsk(dec);
    if (pkD == null || esk == null) return null;
    return _tryOutputRecoveryWithPkdEsk(pkD: pkD, esk: esk, output: output);
  }

  (NOTE, RECIPIENT, List<int>)? _tryOutputRecoveryWithPkdEsk({
    required DIVERSIFIEDTRANSMISSIONKEY pkD,
    required ENCSECRET esk,
    required OUTPUT output,
  }) {
    final ephemeralKey = output.ephemeralKey;
    final sharedSecret = kaAgreeEnc(esk, pkD);
    final key = encKdf(sharedSecret, ephemeralKey);
    final plaintext = output.splitCiphertextAtTag();
    assert(plaintext != null);
    if (plaintext == null) return null;
    final dec = ChaCha20Poly1305(key).decrypt(_nonce, plaintext.$2);
    if (dec == null) return null;
    final compact = splitPlaintextAtMemo(dec);
    if (compact == null) return null;
    final note = parseNotePlaintextWithoutMemoOvk(pkD, compact.$1, output);
    if (note == null) return null;
    final derivedEsk = deriveEsk(note.$1);
    if (derivedEsk != null && derivedEsk != esk) {
      {
        return null;
      }
    }
    if (_checkNoteValidaty(
        note: note.$1, ephemeralKey: ephemeralKey, cm: output.cmstar())) {
      return (note.$1, note.$2, compact.$2);
    }
    return null;
  }

  ENCNOTE createNote(
      {required NOTE note, required List<int> memo, OUTGOINGVIEWINGKEY? ovk});
  ENCNOTE createNoteWithEsk(
      {required NOTE note,
      required List<int> memo,
      required List<int> esk,
      OUTGOINGVIEWINGKEY? ovk});

  List<int> encryptNotePlaintext(ENCNOTE encryptedNote) {
    final pkD = getPkD(encryptedNote.note);
    final sharedSecret = kaAgreeEnc(encryptedNote.esk, pkD);
    final key = encKdf(sharedSecret, epkBytes(encryptedNote.epk));
    final input = notePlaintextBytes(encryptedNote.note, encryptedNote.memo);
    final enc = ChaCha20Poly1305(key).encrypt(_nonce, input);
    return enc;
  }

  List<int> encryptOutgoingPlaintext(
      {required ENCNOTE encryotedNote,
      required VALUECOMMITMENT cv,
      required EXTRACTEDCOMMITMENT cm}) {
    final ovk = encryotedNote.ovk;
    List<int> ock;
    List<int> input;
    if (ovk != null) {
      ock = deriveOck(ovk, cv, cm, epkBytes(encryotedNote.epk));
      input = outgoingPlaintextBytes(encryotedNote.note, encryotedNote.esk);
    } else {
      ock = QuickCrypto.generateRandom();
      input = QuickCrypto.generateRandom(NoteEncryptionConst.outPlaintextSize);
    }
    final chacha = ChaCha20Poly1305(ock);
    return chacha.encrypt(_nonce, input);
  }
}
