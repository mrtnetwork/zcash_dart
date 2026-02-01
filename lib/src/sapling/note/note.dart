import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/sapling/transaction/commitment.dart';
import 'package:zcash_dart/src/sapling/utils/utils.dart';
import 'package:zcash_dart/src/value/value.dart';

abstract class SaplingShildOutput
    with ShieldedOutput<SaplingExtractedNoteCommitment> {
  const SaplingShildOutput();
}

class SaplingNote extends Note with Equality, LayoutSerializable {
  final SaplingPaymentAddress recipient;

  @override
  final ZAmount value;
  final SaplingRSeed rseed;

  SaplingNote(
      {required this.recipient, required this.value, required this.rseed});

  factory SaplingNote.deserializeJson(Map<String, dynamic> json) {
    return SaplingNote(
        recipient:
            SaplingPaymentAddress.fromBytes(json.valueAsBytes("recipient")),
        value: ZAmount(json.valueAsBigInt("value")),
        rseed: SaplingRSeed.deserializeJson(json.valueAs("rseed")));
  }

  static ({
    SaplingNote note,
    SaplingFullViewingKey fvk,
    SaplingExpandedSpendingKey sk
  }) dummy() {
    final dummy = SaplingUtils.dummySk();
    final ex = dummy.sk;
    final fvk = dummy.toExtendedFvk().toDiversifiableFullViewingKey();
    final recipient = fvk.defaultAddress().$1;
    final rseed = SaplingRSeedAfterZip212(QuickCrypto.generateRandom());
    final note =
        SaplingNote(recipient: recipient, value: ZAmount.zero(), rseed: rseed);
    return (note: note, fvk: fvk.fvk, sk: ex);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(43, property: "recipient"),
      SaplingRSeed.layout(property: "rseed"),
      LayoutConst.lebI128(property: "value")
    ], property: property);
  }

  SaplingNoteCommitment? _cm;
  SaplingExtractedNoteCommitment? _cmu;

  SaplingNoteCommitment _cmFullPoint(ZCashCryptoContext context) {
    return _cm ??= SaplingNoteCommitment.deriv(
        gD: recipient.gd().toBytes(),
        pkD: recipient.transmissionKey.toBytes(),
        v: value,
        rcm: rseed.rcm(),
        context: context);
  }

  SaplingExtractedNoteCommitment cmu(ZCashCryptoContext context) {
    return _cmu ??= SaplingExtractedNoteCommitment.fromNoteCommitment(
        _cmFullPoint(context));
  }

  SaplingNullifier nullifier(
      {required SaplingNullifierDerivingKey nk,
      required int position,
      required ZCashCryptoContext context}) {
    final cm = _cmFullPoint(context);
    final rho = SaplingUtils.mixingPedersenHash(cm.inner, position);
    return SaplingNullifier(SaplingUtils.prfNfNative(nk: nk.inner, rho: rho));
  }

  JubJubNativeFr? deriveEsk() => rseed.deriveEsk();

  @override
  List<dynamic> get variables => [recipient, value, rseed];

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "recipient": recipient.toBytes(),
      "rseed": rseed.toSerializeJson(),
      "value": value.value
    };
  }
}

class SaplingEncryptedNote extends NoteEncryption<JubJubNativeFr,
    JubJubNativePoint, SaplingNote, SaplingOutgoingViewingKey> {
  SaplingEncryptedNote(
      {required super.esk,
      required super.epk,
      required super.note,
      required super.memo,
      required super.ovk});
}

class SaplingDomainNative extends NoteDomain<
    JubJubNativeFr,
    JubJubNativePoint,
    JubJubNativePoint,
    JubJubNativePoint,
    JubJubNativePoint,
    SaplingNote,
    SaplingPaymentAddress,
    SaplingDiversifiedTransmissionKey,
    SaplingIvk,
    SaplingOutgoingViewingKey,
    SaplingValueCommitment,
    SaplingExtractedNoteCommitment,
    SaplingShildOutput,
    SaplingEncryptedNote> {
  @override
  final ZCashCryptoContext context;
  SaplingDomainNative(this.context, {this.zip212enforcement});
  final Zip212Enforcement? zip212enforcement;

  @override
  SaplingExtractedNoteCommitment cmstar(SaplingNote note) {
    return note.cmu(context);
  }

  @override
  JubJubNativeFr? deriveEsk(SaplingNote note) {
    return note.deriveEsk();
  }

  @override
  List<int> deriveOck(SaplingOutgoingViewingKey ovk, SaplingValueCommitment cv,
      SaplingExtractedNoteCommitment cm, EphemeralKeyBytes ephemeralKey) {
    const prfOck = "Zcash_Derive_ock";
    return QuickCrypto.blake2b256Hash(ovk.inner,
        extraBlocks: [cv.toBytes(), cm.toBytes(), ephemeralKey.inner],
        personalization: prfOck.codeUnits);
  }

  @override
  JubJubNativePoint? decEpk(EphemeralKeyBytes ephemeralKey) {
    try {
      final pk = JubJubNativePoint.fromBytes(ephemeralKey.inner);
      if (pk.isIdentity()) return null;
      return pk;
    } catch (_) {
      return null;
    }
  }

  @override
  EphemeralKeyBytes epkBytes(JubJubNativePoint epk) {
    return EphemeralKeyBytes(epk.toBytes());
  }

  @override
  JubJubNativeFr extractEsk(List<int> outPlaintext) {
    return JubJubNativeFr.fromBytes(outPlaintext.sublist(32, 64));
  }

  @override
  List<int> extractMemo(List<int> plaintext) {
    return plaintext.sublist(52, 564);
  }

  @override
  SaplingDiversifiedTransmissionKey? extractPkD(List<int> outPlaintext) {
    return SaplingDiversifiedTransmissionKey.fromBytes(
        outPlaintext.sublist(0, 32));
  }

  @override
  SaplingDiversifiedTransmissionKey getPkD(SaplingNote note) {
    return note.recipient.transmissionKey;
  }

  @override
  JubJubNativePoint kaAgreeDec(SaplingIvk ivk, JubJubNativePoint epk) {
    return SaplingUtils.kaSaplingAgreeNative(scalar: ivk.inner, b: epk);
  }

  @override
  JubJubNativePoint kaAgreeEnc(
      JubJubNativeFr esk, SaplingDiversifiedTransmissionKey pkD,
      {bool encrypt = true}) {
    return SaplingUtils.kaSaplingAgreeNative(scalar: esk, b: pkD.inner);
  }

  @override
  JubJubNativePoint kaDerivePublic(SaplingNote note, JubJubNativeFr esk) {
    return SaplingUtils.kaSaplingDerivePublic(
        scalar: esk, b: note.recipient.gd());
  }

  @override
  List<int> kdf(JubJubNativePoint secret, EphemeralKeyBytes ephemeralKey) {
    return SaplingUtils.kdfSapling(
        ephemeralKey: ephemeralKey.inner, secret: secret.toBytes());
  }

  @override
  List<int> notePlaintextBytes(SaplingNote note, List<int> memo) {
    int tag = switch (note.rseed.type) {
      SaplingRSeedType.afterZip212 => 2,
      SaplingRSeedType.beforeZip212 => 1
    };
    return [
      tag,
      ...note.recipient.diversifier.inner,
      ...note.value.toBytes(),
      ...note.rseed.toBytes(),
      ...memo
    ];
  }

  @override
  List<int> outgoingPlaintextBytes(SaplingNote note, JubJubNativeFr esk) {
    return [...note.recipient.transmissionKey.toBytes(), ...esk.toBytes()];
  }

  bool plaintextVersionIsValid(int leadbyte) {
    return switch (zip212enforcement) {
      null ||
      Zip212Enforcement.gracePeriod =>
        leadbyte == 0x01 || leadbyte == 0x02,
      Zip212Enforcement.off => leadbyte == 0x01,
      _ => leadbyte == 0x02
    };
  }

  SaplingNote? saplingParseNotePlaintextWithoutMemo(
      {required List<int> plaintext,
      required SaplingDiversifiedTransmissionKey? Function(
              Diversifier diversifier)
          pkd}) {
    if (plaintext.isEmpty || !plaintextVersionIsValid(plaintext[0])) {
      return null;
    }
    try {
      final dv = Diversifier(plaintext.sublist(1, 12));
      final value = ZAmount.fromBytes(plaintext.sublist(12, 20));
      final r = plaintext.sublist(20, 52);
      final rSeed = switch (plaintext[0]) {
        0x01 => SaplingRSeedBeforeZip212(JubJubNativeFr.fromBytes(r)),
        _ => SaplingRSeedAfterZip212(r)
      };
      final pkD = pkd(dv);
      if (pkD == null) return null;
      final to = SaplingPaymentAddress(transmissionKey: pkD, diversifier: dv);
      final note = SaplingNote(recipient: to, value: value, rseed: rSeed);
      note.cmu(context);
      return note;
    } on BlockchainUtilsException {
      return null;
    }
  }

  @override
  (SaplingNote, SaplingPaymentAddress)? parseNotePlaintextWithoutMemoIvk(
      SaplingIvk ivk, List<int> plaintext, SaplingShildOutput output) {
    final note = saplingParseNotePlaintextWithoutMemo(
      plaintext: plaintext,
      pkd: (diversifier) => SaplingDiversifiedTransmissionKey.derive(
          d: diversifier, ivk: ivk.inner),
    );
    if (note == null) return null;
    return (note, note.recipient);
  }

  @override
  (SaplingNote, SaplingPaymentAddress)? parseNotePlaintextWithoutMemoOvk(
      SaplingDiversifiedTransmissionKey pkD,
      List<int> plaintext,
      SaplingShildOutput output) {
    final note = saplingParseNotePlaintextWithoutMemo(
      plaintext: plaintext,
      pkd: (diversifier) {
        final gd = SaplingKeyUtils.diversifyHash<JubJubFr, JubJubPoint>(
            d: diversifier.inner, fromBytes: JubJubPoint.fromBytes);
        if (gd == null) return null;
        return pkD;
      },
    );
    if (note == null) return null;
    return (note, note.recipient);
  }

  @override
  SaplingEncryptedNote createNote(
      {SaplingOutgoingViewingKey? ovk,
      required SaplingNote note,
      required List<int> memo}) {
    final esk = deriveEsk(note);
    if (esk == null) {
      throw SaplingException.operationFailed("createNote",
          reason: "ZIP-212 is active.");
    }
    return SaplingEncryptedNote(
        ovk: ovk,
        memo: memo,
        note: note,
        esk: esk,
        epk: kaDerivePublic(note, esk));
  }

  @override
  SaplingEncryptedNote createNoteWithEsk(
      {required SaplingNote note,
      required List<int> memo,
      required List<int> esk,
      SaplingOutgoingViewingKey? ovk}) {
    final eskScalar = JubJubNativeFr.fromBytes(esk);
    return SaplingEncryptedNote(
        ovk: ovk,
        memo: memo,
        note: note,
        esk: eskScalar,
        epk: kaDerivePublic(note, eskScalar));
  }

  @override
  List<int> encKdf(JubJubNativePoint secret, EphemeralKeyBytes ephemeralKey) {
    return SaplingUtils.kdfSapling(
        ephemeralKey: ephemeralKey.inner, secret: secret.toBytes());
  }
}
