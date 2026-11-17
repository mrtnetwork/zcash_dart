import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/transaction/commitment.dart';
import 'package:zcash_dart/src/orchard/utils/utils.dart';
import 'package:zcash_dart/src/value/value.dart';

enum OrchardNoteVersion {
  v2(2),
  v3(3);

  const OrchardNoteVersion(this.value);
  final int value;
  static OrchardNoteVersion fromValue(int? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse:
          () => throw BuError(DefaultErrorType.notFound, "OrchardNoteVersion"),
    );
  }

  static OrchardNoteVersion? fromValueOrNull(int? value) {
    return values.firstWhereNullable((e) => e.value == value);
  }
}

abstract class OrchardShildOutput
    with ShieldedOutput<OrchardExtractedNoteCommitment> {
  const OrchardShildOutput();
  OrchardNullifier get nf;
}

class OrchardRho with Equality, LayoutSerializable {
  final BuBytes inner;
  OrchardRho(List<int> bytes)
    : inner =
          bytes
              .exc(
                length: 32,
                operation: "OrchardRho",
                reason: "Invalid OrchardRho bytes length.",
              )
              .asImmutableBytes {
    PallasFp.fromBytes(inner);
  }
  factory OrchardRho.random() {
    final scalar = blockchainUtils.api.pallas.scReduce64(
      QuickCrypto.generateRandom(length: 64),
    );
    final pt = blockchainUtils.api.pallas.multBase(scalar);
    final x = PallasPoint.fromBytes(pt).toAffine().x.toBytes();
    return OrchardRho(x);
  }
  factory OrchardRho.fromBytes(List<int> bytes) => OrchardRho(bytes);
  factory OrchardRho.deserializeJson(Map<String, dynamic> json) =>
      OrchardRho.fromBytes(json.valueAsBytes("inner"));
  BuBytes toBytes() => inner.clone();

  @override
  List<dynamic> get variables => [inner];
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner.clone()};
  }
}

class OrchardNoteRandomSeed with Equality, LayoutSerializable {
  final List<int> inner;
  OrchardNoteRandomSeed(List<int> inner)
    : inner =
          inner
              .exc(
                length: 32,
                operation: "OrchardRho",
                reason: "Invalid OrchardRho bytes length.",
              )
              .asImmutableBytes;
  factory OrchardNoteRandomSeed.random(OrchardRho rho) {
    while (true) {
      try {
        final rSeed = OrchardNoteRandomSeed(QuickCrypto.generateRandom());
        rSeed.esk(rho);
        return rSeed;
      } on BuError {
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

  BuBytes esk(OrchardRho rho) {
    return OrchardUtils.toNonZeroScalar(
      PrfExpand.orchardEsk.apply(inner, data: [rho.toBytes()]),
    );
  }

  BuBytes psi(OrchardRho rho) {
    return PallasFp.fromBytes64(
      PrfExpand.psi.apply(inner, data: [rho.toBytes()]),
    ).toBytes();
  }

  OrchardNoteCommitTrapdoor rcmV2(OrchardRho rho) {
    return OrchardNoteCommitTrapdoor(
      blockchainUtils.api.pallas.scReduce64(
        PrfExpand.orchardRcm.apply(inner, data: [rho.toBytes()]),
      ),
    );
  }

  OrchardNoteCommitTrapdoor rcmV3({
    required OrchardRho rho,
    required List<int> gd,
    required List<int> pkd,
    required BigInt value,
    required List<int> psi,
  }) {
    const String prfExpandPersonalization = "Zcash_ExpandSeed";
    final h = QuickCrypto.blake2b512Hash(
      inner,
      personalization: StringUtils.encode(prfExpandPersonalization),
      extraBlocks: [
        [0x0B],
        gd,
        pkd,
        value.toU64LeBytes(),
        rho.toBytes(),
        psi,
      ],
    );
    return OrchardNoteCommitTrapdoor(blockchainUtils.api.pallas.scReduce64(h));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
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

class OrchardNote extends Note {
  final OrchardAddress recipient;
  @override
  final ZAmount value;
  final OrchardNoteRandomSeed rseed;
  final OrchardRho rho;
  final OrchardNoteVersion version;
  factory OrchardNote.deserialize(List<int> bytes) {
    final json = LayoutSerializable.deserialize(bytes: bytes, layout: layout());
    return OrchardNote.deserializeJson(json);
  }
  factory OrchardNote.deserializeJson(Map<String, dynamic> json) {
    return OrchardNote._(
      recipient: OrchardAddress.fromBytesUnckecked(
        json.valueAsBytes("recipient"),
      ),
      value: ZAmount(json.valueAs("value")),
      rseed: OrchardNoteRandomSeed.deserializeJson(json.valueAs("rseed")),
      rho: OrchardRho.deserializeJson(json.valueAs("rho")),
      version: OrchardNoteVersion.fromValue(json.valueAsInt("version")),
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(43, property: "recipient"),
      LayoutConst.lebI128(property: "value"),
      OrchardNoteRandomSeed.layout(property: "rseed"),
      OrchardRho.layout(property: "rho"),
      LayoutConst.u8(property: "version"),
    ], property: property);
  }

  OrchardNote._({
    required this.recipient,
    required this.value,
    required this.rseed,
    required this.rho,
    required this.version,
  });
  factory OrchardNote.build({
    required OrchardAddress recipient,
    required ZAmount value,
    required OrchardNoteRandomSeed rseed,
    required OrchardRho rho,
    required ZcashCryptoContext context,
    OrchardNoteVersion version = OrchardNoteVersion.v2,
  }) {
    final note = OrchardNote._(
      recipient: recipient,
      value: value,
      rseed: rseed,
      rho: rho,
      version: version,
    );
    if (!note.hasValidCommitment(context)) {
      throw ZcashErrors.orchardFailed(
        "build",
        reason: "Invalid orchard note commitment.",
      );
    }
    return note;
  }
  factory OrchardNote.unchecked({
    required OrchardAddress recipient,
    required ZAmount value,
    required OrchardNoteRandomSeed rseed,
    required OrchardRho rho,
    OrchardNoteVersion version = OrchardNoteVersion.v2,
  }) {
    return OrchardNote._(
      recipient: recipient,
      value: value,
      rseed: rseed,
      rho: rho,
      version: version,
    );
  }
  static (OrchardSpendingKey, OrchardFullViewingKey, OrchardNote) dummy(
    ZcashCryptoContext context, {
    OrchardNoteVersion version = OrchardNoteVersion.v2,
    OrchardRho? rho,
    OrchardSpendingKey? sk,
    ZAmount? amount,
    OrchardAddress? recipient,
  }) {
    OrchardFullViewingKey fvk;

    if (sk != null) {
      fvk = OrchardFullViewingKey.fromSpendKey(sk);
    } else {
      final dummy = OrchardUtils.createDummySpendKey();
      sk = dummy.sk;
      fvk = dummy.fvk;
    }

    recipient ??= fvk.addressAt(
      j: DiversifierIndex.from(0),
      scope: Bip44Changes.chainExt,
      context: context,
    );
    rho ??= OrchardRho.random();
    final note = OrchardNote.build(
      recipient: recipient,
      value: amount ?? ZAmount.zero(),
      rseed: OrchardNoteRandomSeed.random(rho),
      version: version,
      rho: rho,
      context: context,
    );
    return (sk, fvk, note);
  }

  OrchardNoteCommitment? _commitmentInner(ZcashCryptoContext context) {
    final gDBytes = recipient.gD();
    final rcmBytes = rcm().toBytes();
    final psiBytes = psi();
    final result = blockchainUtils.api.hash.sinsemillaCommit(
      r: rcmBytes,
      bits: [
        ...BytesUtils.bytesToBits(gDBytes),
        ...BytesUtils.bytesToBits(recipient.transmissionKey.toBytes()),
        ...value.toBits(),
        ...BytesUtils.bytesToBits(
          rho.toBytes(),
        ).take(OrchardUtils.lOrchardBase),
        ...BytesUtils.bytesToBits(psiBytes).take(OrchardUtils.lOrchardBase),
      ],
      domain: OrchardUtils.noteCommitmentPersonalization,
    );
    if (result == null) {
      return null;
    }
    return OrchardNoteCommitment(result);
  }

  OrchardNoteCommitment? _commitment;
  OrchardNullifier? _nullifier;
  BuBytes? _psi;
  OrchardNoteCommitTrapdoor? _rcm;

  OrchardNullifier nullifier({
    required OrchardFullViewingKey fvk,
    required ZcashCryptoContext context,
  }) {
    final nullifier =
        _nullifier ??= OrchardNullifier(
          OrchardUtils.deriveNullfierKey(
            nk: fvk.nk,
            rho: rho.toBytes(),
            psi: psi(),
            cm: commitment(context),
            context: context,
          ),
        );
    return nullifier;
  }

  OrchardNoteCommitment commitment(ZcashCryptoContext context) {
    final commitment = _commitment ??= _commitmentInner(context);
    if (commitment == null) {
      throw ZcashErrors.orchardFailed(
        "commitment",
        reason: "Failed to derive note commitment.",
      );
    }
    return commitment;
  }

  bool hasValidCommitment(ZcashCryptoContext context) {
    try {
      commitment(context);
      return true;
    } on BuError {
      return false;
    }
  }

  BuBytes psi() {
    final psi = _psi ??= rseed.psi(rho);
    return psi.clone();
  }

  OrchardNoteCommitTrapdoor rcm() {
    switch (version) {
      case OrchardNoteVersion.v2:
        return _rcm ??= rseed.rcmV2(rho);
      case OrchardNoteVersion.v3:
        final gd = recipient.gD();
        final pkd = recipient.transmissionKey.toBytes();
        final psi = this.psi();
        return _rcm ??= rseed.rcmV3(
          gd: gd,
          pkd: pkd,
          psi: psi,
          value: value.value,
          rho: rho,
        );
    }
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
      "rho": rho.toSerializeJson(),
      "version": version.value,
    };
  }
}

class OrchardEncryptedNote
    extends
        NoteEncryption<
          BuBytes,
          BuBytes,
          OrchardNote,
          OrchardOutgoingViewingKey
        > {
  OrchardEncryptedNote({
    required super.esk,
    required super.epk,
    required super.note,
    required super.memo,
    required super.ovk,
  });
}

class OrchardDomain
    extends
        NoteDomain<
          BuBytes,
          BuBytes,
          BuBytes,
          BuBytes,
          BuBytes,
          OrchardNote,
          OrchardAddress,
          OrchardDiversifiedTransmissionKey,
          OrchardKeyAgreementPrivateKey,
          OrchardOutgoingViewingKey,
          OrchardValueCommitment,
          OrchardExtractedNoteCommitment,
          OrchardShildOutput,
          OrchardEncryptedNote
        > {
  final List<int> _orchardKdf = "Zcash_OrchardKDF".codeUnits.immutable;
  @override
  final ZcashCryptoContext context;
  final OrchardNoteVersion version;

  OrchardDomain(this.context, {this.version = OrchardNoteVersion.v2});
  @override
  OrchardExtractedNoteCommitment cmstar(OrchardNote note) {
    return note.commitment(context).toExtractedNoteCommitment();
  }

  @override
  BuBytes deriveEsk(OrchardNote note) {
    return note.rseed.esk(note.rho);
  }

  @override
  List<int> deriveOck(
    OrchardOutgoingViewingKey ovk,
    OrchardValueCommitment cv,
    OrchardExtractedNoteCommitment cm,
    EphemeralKeyBytes ephemeralKey,
  ) {
    const prfOck = "Zcash_Orchardock";
    return QuickCrypto.blake2b256Hash(
      ovk.inner,
      extraBlocks: [cv.toBytes(), cm.toBytes(), ephemeralKey.inner],
      personalization: prfOck.codeUnits,
    );
  }

  @override
  BuBytes? decEpk(EphemeralKeyBytes ephemeralKey) {
    try {
      final pt = PallasPoint.fromBytes(ephemeralKey.inner);
      if (pt.isIdentity()) return null;
      return BuBytes.from(ephemeralKey.inner);
    } catch (_) {
      return null;
    }
  }

  @override
  EphemeralKeyBytes epkBytes(BuBytes epk) {
    return EphemeralKeyBytes(epk);
  }

  @override
  BuBytes extractEsk(List<int> outPlaintext) {
    final bytes = outPlaintext.sublist(32, 64);
    VestaFq.fromBytes(bytes);
    return BuBytes.from(bytes);
  }

  @override
  List<int> extractMemo(List<int> plaintext) {
    return plaintext.sublist(52, 564);
  }

  @override
  OrchardDiversifiedTransmissionKey? extractPkD(List<int> outPlaintext) {
    return OrchardDiversifiedTransmissionKey.fromBytes(
      outPlaintext.sublist(0, 32),
    );
  }

  @override
  OrchardDiversifiedTransmissionKey getPkD(OrchardNote note) {
    return note.recipient.transmissionKey;
  }

  @override
  BuBytes kaAgreeDec(OrchardKeyAgreementPrivateKey ivk, BuBytes epk) {
    return OrchardUtils.kaOrchardBytes(base: epk, sk: ivk.toBytes());
  }

  @override
  BuBytes kaAgreeEnc(
    BuBytes esk,
    OrchardDiversifiedTransmissionKey pkD, {
    bool encrypt = true,
  }) {
    return OrchardUtils.kaOrchardBytes(base: pkD.toBytes(), sk: esk);
  }

  @override
  BuBytes kaDerivePublic(OrchardNote note, BuBytes esk) {
    return OrchardUtils.kaOrchardBytes(base: note.recipient.gD(), sk: esk);
  }

  @override
  List<int> kdf(BuBytes secret, EphemeralKeyBytes ephemeralKey) {
    return QuickCrypto.blake2b256Hash(
      secret,
      extraBlocks: [ephemeralKey.inner],
      personalization: _orchardKdf,
    );
  }

  @override
  List<int> notePlaintextBytes(OrchardNote note, List<int> memo) {
    return [
      version.value,
      ...note.recipient.diversifier.inner,
      ...note.value.toBytes(),
      ...note.rseed.inner,
      ...memo,
    ];
  }

  @override
  List<int> outgoingPlaintextBytes(OrchardNote note, BuBytes esk) {
    return [...note.recipient.transmissionKey.toBytes(), ...esk];
  }

  ({OrchardNote note, List<int>? memo})? orchardParseNotePlaintextWithoutMemo({
    required List<int> plaintext,
    required OrchardShildOutput output,
    required OrchardDiversifiedTransmissionKey? Function(
      Diversifier diversifier,
    )
    pkd,
  }) {
    final version = OrchardNoteVersion.fromValueOrNull(
      plaintext.elementAtOrNull(0),
    );
    if (version == null ||
        plaintext.length < NoteEncryptionConst.compactNoteSize) {
      return null;
    }
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
        context: context,
        version: version,
      );
      return (
        note: note,
        memo:
            plaintext.length == NoteEncryptionConst.notePlaintextSize
                ? plaintext.sublist(NoteEncryptionConst.compactNoteSize)
                : null,
      );
    } on BuError {
      return null;
    }
  }

  @override
  (OrchardNote, OrchardAddress, List<int>?)? parseNotePlaintextWithoutMemoIvk(
    OrchardKeyAgreementPrivateKey ivk,
    List<int> plaintext,
    OrchardShildOutput output,
  ) {
    final note = orchardParseNotePlaintextWithoutMemo(
      plaintext: plaintext,
      output: output,
      pkd: (diversifier) {
        try {
          return OrchardDiversifiedTransmissionKey.derive(
            d: diversifier,
            ivk: ivk.scalar,
          );
        } catch (_) {
          return null;
        }
      },
    );
    if (note == null) return null;
    return (note.note, note.note.recipient, note.memo);
  }

  @override
  (OrchardNote, OrchardAddress)? parseNotePlaintextWithoutMemoOvk(
    OrchardDiversifiedTransmissionKey pkD,
    List<int> plaintext,
    OrchardShildOutput output,
  ) {
    final note = orchardParseNotePlaintextWithoutMemo(
      plaintext: plaintext,
      output: output,
      pkd: (diversifier) {
        try {
          OrchardKeyUtils.diversifyHash(diversifier.inner);
          return pkD;
        } catch (_) {
          return null;
        }
      },
    );
    if (note == null) return null;
    return (note.note, note.note.recipient);
  }

  @override
  OrchardEncryptedNote createNote({
    OrchardOutgoingViewingKey? ovk,
    required OrchardNote note,
    required List<int> memo,
  }) {
    final esk = deriveEsk(note);
    return OrchardEncryptedNote(
      ovk: ovk,
      memo: memo,
      note: note,
      esk: esk,
      epk: kaDerivePublic(note, esk),
    );
  }

  @override
  OrchardEncryptedNote createNoteWithEsk({
    required OrchardNote note,
    required List<int> memo,
    required List<int> esk,
    OrchardOutgoingViewingKey? ovk,
  }) {
    VestaFq.fromBytes(esk);
    final eskBytes = BuBytes.from(esk);
    return OrchardEncryptedNote(
      ovk: ovk,
      memo: memo,
      note: note,
      esk: eskBytes,
      epk: kaDerivePublic(note, eskBytes),
    );
  }

  @override
  List<int> encKdf(BuBytes secret, EphemeralKeyBytes ephemeralKey) {
    return QuickCrypto.blake2b256Hash(
      secret,
      extraBlocks: [ephemeralKey.inner],
      personalization: _orchardKdf,
    );
  }
}
