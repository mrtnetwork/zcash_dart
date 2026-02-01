import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/exception/exception.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/orchard/transaction/commitment.dart';
import 'package:zcash_dart/src/orchard/utils/utils.dart';
import 'package:zcash_dart/src/value/value.dart';

abstract class OrchardShildOutput
    with ShieldedOutput<OrchardExtractedNoteCommitment> {
  const OrchardShildOutput();
  OrchardNullifier get nf;
}

class OrchardRho with Equality, LayoutSerializable {
  final PallasNativeFp inner;
  const OrchardRho(this.inner);
  factory OrchardRho.random() =>
      OrchardRho(PallasNativePoint.random().toAffine().x);
  factory OrchardRho.fromBytes(List<int> bytes) =>
      OrchardRho(PallasNativeFp.fromBytes(bytes));
  factory OrchardRho.deserializeJson(Map<String, dynamic> json) =>
      OrchardRho.fromBytes(json.valueAsBytes("inner"));
  List<int> toBytes() => inner.toBytes();

  @override
  List<dynamic> get variables => [inner];
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([LayoutConst.fixedBlob32(property: "inner")],
        property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner.toBytes()};
  }
}

class OrchardNoteRandomSeed with Equality, LayoutSerializable {
  final List<int> inner;
  OrchardNoteRandomSeed(List<int> inner)
      : inner = inner
            .exc(
                length: 32,
                operation: "OrchardRho",
                reason: "Invalid OrchardRho bytes length.")
            .asImmutableBytes;
  factory OrchardNoteRandomSeed.random(OrchardRho rho) {
    while (true) {
      try {
        final rSeed = OrchardNoteRandomSeed(QuickCrypto.generateRandom());
        rSeed.esk(rho);
        return rSeed;
      } on DartZCashPluginException {
        continue;
      }
    }
  }
  factory OrchardNoteRandomSeed.deserializeJson(Map<String, dynamic> json) =>
      OrchardNoteRandomSeed(json.valueAsBytes("inner"));
  factory OrchardNoteRandomSeed.fromBytes(List<int> bytes, OrchardRho rho) {
    final rSeed = OrchardNoteRandomSeed(bytes);
    rSeed.esk(rho);
    return rSeed;
  }

  VestaNativeFq esk(OrchardRho rho) {
    return OrchardUtils.toNonZeroScalar(
        PrfExpand.orchardEsk.apply(inner, data: [rho.toBytes()]));
  }

  PallasNativeFp psi(OrchardRho rho) {
    return PallasNativeFp.fromBytes64(
        PrfExpand.psi.apply(inner, data: [rho.toBytes()]));
  }

  OrchardNoteCommitTrapdoor rcm(OrchardRho rho) {
    return OrchardNoteCommitTrapdoor(VestaNativeFq.fromBytes64(
        PrfExpand.orchardRcm.apply(inner, data: [rho.toBytes()])));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([LayoutConst.fixedBlob32(property: "inner")],
        property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner};
  }

  @override
  List<dynamic> get variables => [inner];
}

class OrchardNote extends Note with Equality, LayoutSerializable {
  final OrchardAddress recipient;
  @override
  final ZAmount value;
  final OrchardNoteRandomSeed rseed;
  final OrchardRho rho;

  factory OrchardNote.deserializeJson(Map<String, dynamic> json) {
    return OrchardNote._(
        recipient: OrchardAddress.fromBytes(json.valueAsBytes("recipient")),
        value: ZAmount(json.valueAs("value")),
        rseed: OrchardNoteRandomSeed.deserializeJson(json.valueAs("rseed")),
        rho: OrchardRho.deserializeJson(json.valueAs("rho")));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(43, property: "recipient"),
      LayoutConst.lebI128(property: "value"),
      OrchardNoteRandomSeed.layout(property: "rseed"),
      OrchardRho.layout(property: "rho")
    ], property: property);
  }

  OrchardNote._(
      {required this.recipient,
      required this.value,
      required this.rseed,
      required this.rho});
  factory OrchardNote.build(
      {required OrchardAddress recipient,
      required ZAmount value,
      required OrchardNoteRandomSeed rseed,
      required OrchardRho rho,
      required ZCashCryptoContext context}) {
    final note = OrchardNote._(
        recipient: recipient, value: value, rseed: rseed, rho: rho);
    if (!note.hasValidCommitment(context)) {
      throw OrchardException.operationFailed("build",
          reason: "Invalid orchard note commitment.");
    }
    return note;
  }
  factory OrchardNote.unchecked(
      {required OrchardAddress recipient,
      required ZAmount value,
      required OrchardNoteRandomSeed rseed,
      required OrchardRho rho}) {
    return OrchardNote._(
        recipient: recipient, value: value, rseed: rseed, rho: rho);
  }
  static (OrchardSpendingKey, OrchardFullViewingKey, OrchardNote) dummy(
      ZCashCryptoContext context,
      {OrchardRho? rho}) {
    final dummy = OrchardUtils.createDummySpendKey();
    final recipient = dummy.fvk.addressAt(
        j: DiversifierIndex.from(0),
        scope: Bip44Changes.chainExt,
        context: context);
    rho ??= OrchardRho.random();
    final note = OrchardNote.build(
        recipient: recipient,
        value: ZAmount.zero(),
        rseed: OrchardNoteRandomSeed.random(rho),
        rho: rho,
        context: context);
    return (dummy.sk, dummy.fvk, note);
  }

  OrchardNoteCommitment? _commitmentInner(ZCashCryptoContext context) {
    final domain =
        context.getCommitDomain(OrchardUtils.noteCommitmentPersonalization);
    final gD = recipient.gD();
    final result = domain.commit(msg: [
      ...BytesUtils.bytesToBits(gD.toBytes()),
      ...BytesUtils.bytesToBits(recipient.transmissionKey.toBytes()),
      ...value.toBits(),
      ...rho.inner.toBits().take(OrchardUtils.lOrchardBase),
      ...psi().toBits().take(OrchardUtils.lOrchardBase)
    ], r: rcm().inner);
    if (result == null) {
      return null;
    }
    return OrchardNoteCommitment(result);
  }

  OrchardNoteCommitment? _commitment;
  OrchardNullifier? _nullifier;
  PallasNativeFp? _psi;
  OrchardNoteCommitTrapdoor? _rcm;

  OrchardNullifier nullifier(
      {required OrchardFullViewingKey fvk,
      required ZCashCryptoContext context}) {
    final nullifier = _nullifier ??= OrchardNullifier(
        OrchardUtils.deriveNullfierKey(
            nk: fvk.nk,
            rho: rho.inner,
            psi: psi(),
            cm: commitment(context),
            context: context));
    return nullifier;
  }

  OrchardNoteCommitment commitment(ZCashCryptoContext context) {
    final commitment = _commitment ??= _commitmentInner(context);
    if (commitment == null) {
      throw OrchardException.operationFailed("commitment",
          reason: "Failed to derive note commitment.");
    }
    return commitment;
  }

  bool hasValidCommitment(ZCashCryptoContext context) {
    try {
      commitment(context);
      return true;
    } on DartZCashPluginException {
      return false;
    }
  }

  PallasNativeFp psi() {
    final psi = _psi ??= rseed.psi(rho);
    return psi;
  }

  OrchardNoteCommitTrapdoor rcm() {
    final rcm = _rcm ??= rseed.rcm(rho);
    return rcm;
  }

  @override
  List<dynamic> get variables => [recipient, value, rseed, rho];

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "recipient": recipient.toBytes(),
      "value": value.value,
      "rseed": rseed.toSerializeJson(),
      "rho": rho.toSerializeJson()
    };
  }
}

class OrchardEncryptedNote extends NoteEncryption<VestaNativeFq,
    PallasNativePoint, OrchardNote, OrchardOutgoingViewingKey> {
  OrchardEncryptedNote(
      {required super.esk,
      required super.epk,
      required super.note,
      required super.memo,
      required super.ovk});
}

class OrchardDomainNative extends NoteDomain<
    VestaNativeFq,
    PallasNativePoint,
    PallasNativePoint,
    PallasNativePoint,
    PallasNativePoint,
    OrchardNote,
    OrchardAddress,
    OrchardDiversifiedTransmissionKey,
    OrchardKeyAgreementPrivateKey,
    OrchardOutgoingViewingKey,
    OrchardValueCommitment,
    OrchardExtractedNoteCommitment,
    OrchardShildOutput,
    OrchardEncryptedNote> {
  final List<int> _orchardKdf = "Zcash_OrchardKDF".codeUnits.immutable;
  @override
  final ZCashCryptoContext context;
  OrchardDomainNative(this.context);
  @override
  OrchardExtractedNoteCommitment cmstar(OrchardNote note) {
    return note.commitment(context).toExtractedNoteCommitment();
  }

  @override
  VestaNativeFq deriveEsk(OrchardNote note) {
    return note.rseed.esk(note.rho);
  }

  @override
  List<int> deriveOck(OrchardOutgoingViewingKey ovk, OrchardValueCommitment cv,
      OrchardExtractedNoteCommitment cm, EphemeralKeyBytes ephemeralKey) {
    const prfOck = "Zcash_Orchardock";
    return QuickCrypto.blake2b256Hash(ovk.key,
        extraBlocks: [cv.toBytes(), cm.toBytes(), ephemeralKey.inner],
        personalization: prfOck.codeUnits);
  }

  @override
  PallasNativePoint? decEpk(EphemeralKeyBytes ephemeralKey) {
    try {
      final pk = PallasNativePoint.fromBytes(ephemeralKey.inner);
      if (pk.isIdentity()) return null;
      return pk;
    } catch (_) {
      return null;
    }
  }

  @override
  EphemeralKeyBytes epkBytes(PallasNativePoint epk) {
    return EphemeralKeyBytes(epk.toBytes());
  }

  @override
  VestaNativeFq extractEsk(List<int> outPlaintext) {
    return VestaNativeFq.fromBytes(outPlaintext.sublist(32, 64));
  }

  @override
  List<int> extractMemo(List<int> plaintext) {
    return plaintext.sublist(52, 564);
  }

  @override
  OrchardDiversifiedTransmissionKey? extractPkD(List<int> outPlaintext) {
    return OrchardDiversifiedTransmissionKey.fromBytes(
        outPlaintext.sublist(0, 32));
  }

  @override
  OrchardDiversifiedTransmissionKey getPkD(OrchardNote note) {
    return note.recipient.transmissionKey;
  }

  @override
  PallasNativePoint kaAgreeDec(
      OrchardKeyAgreementPrivateKey ivk, PallasNativePoint epk) {
    final PallasNativePoint p = epk * ivk.scalar;
    // OrchardUtils.kaOrchard(base: base, sk: sk)
    if (p.isIdentity()) {
      throw OrchardException.operationFailed("kaAgreeDec",
          reason: "Scalar multiplication resulted in the identity point");
    }
    return p;
  }

  @override
  PallasNativePoint kaAgreeEnc(
      VestaNativeFq esk, OrchardDiversifiedTransmissionKey pkD,
      {bool encrypt = true}) {
    return OrchardUtils.kaOrchardNative(base: pkD.point, sk: esk);
  }

  @override
  PallasNativePoint kaDerivePublic(OrchardNote note, VestaNativeFq esk) {
    return OrchardUtils.kaOrchardNative(base: note.recipient.gD(), sk: esk);
  }

  @override
  List<int> kdf(PallasNativePoint secret, EphemeralKeyBytes ephemeralKey) {
    return QuickCrypto.blake2b256Hash(secret.toBytes(),
        extraBlocks: [ephemeralKey.inner], personalization: _orchardKdf);
  }

  @override
  List<int> notePlaintextBytes(OrchardNote note, List<int> memo) {
    return [
      0x02,
      ...note.recipient.diversifier.inner,
      ...note.value.toBytes(),
      ...note.rseed.inner,
      ...memo
    ];
  }

  @override
  List<int> outgoingPlaintextBytes(OrchardNote note, VestaNativeFq esk) {
    return [...note.recipient.transmissionKey.toBytes(), ...esk.toBytes()];
  }

  OrchardNote? orchardParseNotePlaintextWithoutMemo(
      {required List<int> plaintext,
      required OrchardShildOutput output,
      required OrchardDiversifiedTransmissionKey? Function(
              Diversifier diversifier)
          pkd}) {
    if (plaintext.isEmpty || plaintext[0] != 0x02) return null;
    try {
      final dv = Diversifier(plaintext.sublist(1, 12));
      final value = ZAmount.fromBytes(plaintext.sublist(12, 20));
      final r = OrchardNoteRandomSeed(plaintext.sublist(20, 52));
      final pkD = pkd(dv);

      if (pkD == null) return null;
      final to = OrchardAddress(transmissionKey: pkD, diversifier: dv);
      final note = OrchardNote.build(
          recipient: to,
          value: value,
          rseed: r,
          rho: OrchardRho(output.nf.inner),
          context: context);
      return note;
    } on BlockchainUtilsException {
      return null;
    }
  }

  @override
  (OrchardNote, OrchardAddress)? parseNotePlaintextWithoutMemoIvk(
      OrchardKeyAgreementPrivateKey ivk,
      List<int> plaintext,
      OrchardShildOutput output) {
    final note = orchardParseNotePlaintextWithoutMemo(
        plaintext: plaintext,
        output: output,
        pkd: (diversifier) {
          try {
            return OrchardDiversifiedTransmissionKey.derive(
                d: diversifier, ivk: ivk.scalar);
          } catch (_) {
            return null;
          }
        });
    if (note == null) return null;
    return (note, note.recipient);
  }

  @override
  (OrchardNote, OrchardAddress)? parseNotePlaintextWithoutMemoOvk(
      OrchardDiversifiedTransmissionKey pkD,
      List<int> plaintext,
      OrchardShildOutput output) {
    final note = orchardParseNotePlaintextWithoutMemo(
      plaintext: plaintext,
      output: output,
      pkd: (diversifier) {
        try {
          OrchardKeyUtils.diversifyHashNative(diversifier.inner);
          return pkD;
        } catch (_) {
          return null;
        }
      },
    );
    if (note == null) return null;
    return (note, note.recipient);
  }

  @override
  OrchardEncryptedNote createNote(
      {OrchardOutgoingViewingKey? ovk,
      required OrchardNote note,
      required List<int> memo}) {
    final esk = deriveEsk(note);
    return OrchardEncryptedNote(
        ovk: ovk,
        memo: memo,
        note: note,
        esk: esk,
        epk: kaDerivePublic(note, esk));
  }

  @override
  OrchardEncryptedNote createNoteWithEsk(
      {required OrchardNote note,
      required List<int> memo,
      required List<int> esk,
      OrchardOutgoingViewingKey? ovk}) {
    final eskScalar = VestaNativeFq.fromBytes(esk);
    return OrchardEncryptedNote(
        ovk: ovk,
        memo: memo,
        note: note,
        esk: eskScalar,
        epk: kaDerivePublic(note, eskScalar));
  }

  @override
  List<int> encKdf(PallasNativePoint secret, EphemeralKeyBytes ephemeralKey) {
    return QuickCrypto.blake2b256Hash(secret.toBytes(),
        extraBlocks: [ephemeralKey.inner], personalization: _orchardKdf);
  }
}
