import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/pczt/pczt.dart';
import 'package:zcash_dart/src/sapling/pczt/exception.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/zk_proof/bellman/bellman.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/proof.dart';

class SaplingPcztSpend with LayoutSerializable {
  final SaplingValueCommitment cv;
  final SaplingNullifier nullifier;
  final SaplingSpendVerificationKey rk;

  final SaplingPaymentAddress? recipient;
  final ZAmount? value;
  final SaplingRSeed? rseed;
  final SaplingValueCommitTrapdoor? rcv;
  final SaplingMerklePath? witness;
  final JubJubNativeFr? alpha;
  final SaplingSpendAuthorizingKey? dummySk;
  SaplingProofGenerationKey? _proofGenerationKey;
  SaplingProofGenerationKey? get proofGenerationKey => _proofGenerationKey;
  Map<String, List<int>> _proprietary;
  Map<String, List<int>> get proprietary => _proprietary;
  GrothProofBytes? _zkproof;
  GrothProofBytes? get zkproof => _zkproof;
  ReddsaSignature? _spendAuthSig;
  ReddsaSignature? get spendAuthSig => _spendAuthSig;
  PcztZip32Derivation? _zip32derivation;
  PcztZip32Derivation? get zip32derivation => _zip32derivation;

  SaplingPcztSpend clone() => SaplingPcztSpend(
      nullifier: nullifier,
      rk: rk,
      cv: cv,
      alpha: alpha,
      dummySk: dummySk,
      proofGenerationKey: proofGenerationKey,
      proprietary: proprietary,
      rcv: rcv,
      recipient: recipient,
      rseed: rseed,
      spendAuthSig: spendAuthSig,
      value: value,
      witness: witness,
      zip32derivation: zip32derivation,
      zkproof: zkproof);

  SaplingPcztSpend(
      {required this.nullifier,
      required this.rk,
      required this.cv,
      SaplingProofGenerationKey? proofGenerationKey,
      this.rcv,
      GrothProofBytes? zkproof,
      ReddsaSignature? spendAuthSig,
      this.recipient,
      this.value,
      this.rseed,
      this.witness,
      this.alpha,
      PcztZip32Derivation? zip32derivation,
      this.dummySk,
      Map<String, List<int>> proprietary = const {}})
      : _proprietary =
            proprietary.map((k, v) => MapEntry(k, v.toImutableBytes)).immutable,
        _zip32derivation = zip32derivation,
        _spendAuthSig = spendAuthSig,
        _proofGenerationKey = proofGenerationKey,
        _zkproof = zkproof;
  factory SaplingPcztSpend.deserializeJson(Map<String, dynamic> json) {
    final List<int>? rcm = json.valueAsBytes("rcm");
    final List<int>? rseedBytes = json.valueAsBytes("rseed");
    if (rcm != null && rseedBytes != null) {
      throw SaplingPcztException.operationFailed("deserializeJson",
          reason: "Invalid note commit randomness.");
    }
    SaplingRSeed? rseed;
    if (rcm != null) {
      rseed = SaplingRSeedBeforeZip212(JubJubNativeFr.fromBytes(rcm));
    } else if (rseedBytes != null) {
      rseed = SaplingRSeedAfterZip212(rseedBytes);
    }
    return SaplingPcztSpend(
      cv: SaplingValueCommitment.deserializeJson(
          json.valueEnsureAsMap<String, dynamic>("cv")),
      nullifier: SaplingNullifier.deserializeJson(
          json.valueEnsureAsMap<String, dynamic>("nullifier")),
      rk: SaplingSpendVerificationKey.deserializeJson(
          json.valueEnsureAsMap<String, dynamic>("rk")),
      zkproof: json.valueTo<GrothProofBytes?, Map<String, dynamic>>(
          key: "zkproof", parse: (v) => GrothProofBytes.deserializeJson(v)),
      spendAuthSig: json.valueTo<ReddsaSignature?, Map<String, dynamic>>(
        key: "spend_auth_sig",
        parse: (v) => ReddsaSignature.deserializeJson(v),
      ),
      recipient: json.valueTo<SaplingPaymentAddress?, List<int>>(
        key: "recipient",
        parse: (v) => SaplingPaymentAddress.fromBytes(v),
      ),
      value: json.valueTo<ZAmount?, BigInt>(
        key: "value",
        parse: (v) {
          return ZAmount(v);
        },
      ),
      rseed: rseed,
      rcv: json.valueTo<SaplingValueCommitTrapdoor?, Map<String, dynamic>>(
          key: "rcv",
          parse: (v) => SaplingValueCommitTrapdoor.deserializeJson(v)),
      proofGenerationKey:
          json.valueTo<SaplingProofGenerationKey?, Map<String, dynamic>>(
              key: "proof_generation_key",
              parse: (v) => SaplingProofGenerationKey.deserializeJson(v)),
      witness: json.valueTo<SaplingMerklePath?, Map<String, dynamic>>(
        key: "witness",
        parse: (v) => SaplingMerklePath.deserializeJson(v),
      ),
      alpha: json.valueTo<JubJubNativeFr?, List<int>>(
        key: "alpha",
        parse: (v) => JubJubNativeFr.fromBytes(v),
      ),
      zip32derivation: json.valueTo<PcztZip32Derivation?, Map<String, dynamic>>(
        key: "zip32_derivation",
        parse: (v) => PcztZip32Derivation.deserializeJson(v),
      ),
      dummySk: json.valueTo<SaplingSpendAuthorizingKey?, List<int>>(
        key: "dummy_sk",
        parse: (v) => SaplingSpendAuthorizingKey.fromBytes(v),
      ),
      proprietary: json.valueEnsureAsMap<String, List<int>>("proprietary"),
    );
  }
  SaplingPcztSpend copyWith({
    SaplingValueCommitment? cv,
    SaplingNullifier? nullifier,
    SaplingSpendVerificationKey? rk,
    GrothProofBytes? zkproof,
    SaplingPaymentAddress? recipient,
    ZAmount? value,
    SaplingRSeed? rseed,
    SaplingValueCommitTrapdoor? rcv,
    SaplingProofGenerationKey? proofGenerationKey,
    SaplingMerklePath? witness,
    JubJubNativeFr? alpha,
    PcztZip32Derivation? zip32derivation,
    SaplingSpendAuthorizingKey? dummySk,
    Map<String, List<int>>? proprietary,
    ReddsaSignature? spendAuthSig,
  }) {
    return SaplingPcztSpend(
        nullifier: nullifier ?? this.nullifier,
        rk: rk ?? this.rk,
        alpha: alpha ?? this.alpha,
        dummySk: dummySk ?? this.dummySk,
        cv: cv ?? this.cv,
        proofGenerationKey: proofGenerationKey ?? this.proofGenerationKey,
        rcv: rcv ?? this.rcv,
        zkproof: zkproof ?? this.zkproof,
        proprietary: proprietary ?? this.proprietary,
        recipient: recipient ?? this.recipient,
        rseed: rseed ?? this.rseed,
        spendAuthSig: spendAuthSig ?? this.spendAuthSig,
        value: value ?? this.value,
        witness: witness ?? this.witness,
        zip32derivation: zip32derivation ?? this.zip32derivation);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      SaplingValueCommitment.layout(property: "cv"),
      Nullifier.layout(property: "nullifier"),
      SaplingSpendVerificationKey.layout(property: "rk"),
      LayoutConst.optional(GrothProofBytes.layout(), property: "zkproof"),
      LayoutConst.optional(ReddsaSignature.layout(),
          property: "spend_auth_sig"),
      LayoutConst.optional(LayoutConst.fixedBlobN(43), property: "recipient"),
      LayoutConst.optional(LayoutConst.lebU64(), property: "value"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "rcm"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "rseed"),
      LayoutConst.optional(SaplingValueCommitTrapdoor.layout(),
          property: "rcv"),
      LayoutConst.optional(SaplingProofGenerationKey.layout(),
          property: "proof_generation_key"),
      LayoutConst.optional(SaplingMerklePath.layout(), property: "witness"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "alpha"),
      LayoutConst.optional(PcztZip32Derivation.layout(),
          property: "zip32_derivation"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "dummy_ask"),
      LayoutConst.bscMap<String, List<int>>(
          LayoutConst.bcsString(), LayoutConst.bcsBytes(),
          property: "proprietary")
    ], property: property);
  }

  void setZip32Derivation(PcztZip32Derivation? derivation) {
    _zip32derivation = derivation;
  }

  /// Adds a proprietary key-value pair to the spend.
  void addProprietary(String name, List<int> value) {
    final proprietary = this.proprietary.clone();
    proprietary[name] = value.clone();
    _proprietary = proprietary.immutable;
  }

  void setAuthSig(ReddsaSignature sig) {
    _spendAuthSig = sig;
  }

  void setProofGenerationKey(SaplingProofGenerationKey proofGenerationKey) {
    _proofGenerationKey = proofGenerationKey;
  }

  void setZkproof(GrothProofBytes proof) {
    _zkproof = proof;
  }

  ZAmount getValue() {
    final value = this.value;
    if (value == null) {
      throw SaplingPcztException.operationFailed("getValue",
          reason: "Missing spend value.");
    }
    return value;
  }

  SaplingValueCommitTrapdoor getRcv() {
    final rcv = this.rcv;
    if (rcv == null) {
      throw SaplingPcztException.operationFailed("getRcv",
          reason: "Missing spend value commit trapdoor.");
    }
    return rcv;
  }

  SaplingProofGenerationKey getProofGenerationKey() {
    final proofGenerationKey = this.proofGenerationKey;
    if (proofGenerationKey == null) {
      throw SaplingPcztException.operationFailed("getProofGenerationKey",
          reason: "Missing spend proof generation key.");
    }
    return proofGenerationKey;
  }

  JubJubNativeFr getAlpha() {
    final alpha = this.alpha;
    if (alpha == null) {
      throw SaplingPcztException.operationFailed("getAlpha",
          reason: "Invalid spend auth randomizer.");
    }
    return alpha;
  }

  SaplingPaymentAddress getRecipient() {
    final recipient = this.recipient;
    if (recipient == null) {
      throw SaplingPcztException.operationFailed("getRecipient",
          reason: "Missing spend recipient.");
    }
    return recipient;
  }

  SaplingRSeed getRseed() {
    final rseed = this.rseed;
    if (rseed == null) {
      throw SaplingPcztException.operationFailed("getRseed",
          reason: "Missing spend rseed.");
    }
    return rseed;
  }

  SaplingMerklePath getWitness() {
    final witness = this.witness;
    if (witness == null) {
      throw SaplingPcztException.operationFailed("getWitness",
          reason: "Missing spend witness.");
    }
    return witness;
  }

  void verifyCv() {
    final value = getValue();
    final rcv = getRcv();
    final cvNet = SaplingValueCommitment.derive(value: value, rcv: rcv);
    if (cvNet == cv) return;
    throw SaplingPcztException.operationFailed("verifyCv",
        reason: "Invalid spend value commit.");
  }

  SaplingViewingKey vkForValidation({SaplingFullViewingKey? fvk}) {
    SaplingViewingKey? vk = proofGenerationKey?.toViewingKey();
    if (vk != null && fvk != null) {
      if (vk.ak == fvk.vk.ak && vk.nk == fvk.vk.nk) {
        return vk;
      }
      final value = this.value;
      if ((value?.isZero() ?? false)) return vk;
      throw SaplingPcztException.operationFailed("vkForValidation",
          reason: "Mismatch full view key.");
    }
    vk ??= fvk?.vk;

    if (vk == null) {
      throw SaplingPcztException.operationFailed("vkForValidation",
          reason: "Missing spend proof generation key.");
    }
    return vk;
  }

  void verifyNullifier(ZCashCryptoContext context,
      {SaplingFullViewingKey? fvk}) {
    final vk = vkForValidation(fvk: fvk);
    final recipient = getRecipient();
    final value = getValue();
    final rseed = getRseed();
    final note = SaplingNote(recipient: recipient, value: value, rseed: rseed);
    if (vk.ivk().toPaymentAddress(note.recipient.diversifier) !=
        note.recipient) {
      throw SaplingPcztException.operationFailed("verifyNullifier",
          reason: "Invalid full view key for note.");
    }
    final witness = getWitness();
    if (note.nullifier(
            nk: vk.nk, position: witness.position.position, context: context) !=
        nullifier) {
      throw SaplingPcztException.operationFailed("verifyNullifier",
          reason: "Invalid spend nullifier.");
    }
  }

  void verifyRk({SaplingFullViewingKey? fvk}) {
    final vk = vkForValidation(fvk: fvk);
    final alpha = getAlpha();
    if (vk.ak.randomize(alpha) != rk) {
      throw SaplingPcztException.operationFailed("verifyRk",
          reason: "Invalid spend randomized verification key.");
    }
  }

  SaplingSpendAuthorizingKey _validateAndGetRsk(
      List<int> sighash, SaplingSpendAuthorizingKey ask) {
    sighash = sighash.exc(
        length: 32, operation: "sign", reason: "Invalid sighash bytes length.");
    final alpha = getAlpha();
    final rk = this.rk;
    final rsk = ask.randomize(JubJubFr.fromBytes(alpha.toBytes()));
    if (rsk.toVerificationKey() != rk) {
      throw SaplingPcztException.operationFailed("sign",
          reason: "Invalid spend authorization key.");
    }
    return rsk;
  }

  Future<void> sign(
      {required ZCashCryptoContext context,
      required List<int> sighash,
      required SaplingSpendAuthorizingKey ask}) async {
    final rsk = _validateAndGetRsk(sighash, ask);
    final signature = await context.signRedJubJub(rsk, sighash);
    setAuthSig(signature);
  }

  Future<void> applySignature(
      {required ZCashCryptoContext context,
      required List<int> sighash,
      required ReddsaSignature signature,
      bool verifySignature = true}) async {
    if (verifySignature &&
        !await context.verifyRedJubJubSignature(
            vk: rk, signature: signature, message: sighash)) {
      throw SaplingPcztException.operationFailed("applySignature",
          reason: "Invalid external signature.");
    }
    setAuthSig(signature);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "cv": cv.toSerializeJson(),
      "nullifier": nullifier.toSerializeJson(),
      "rk": rk.toSerializeJson(),
      "zkproof": zkproof?.toSerializeJson(),
      "spend_auth_sig": spendAuthSig?.toSerializeJson(),
      "recipient": recipient?.toBytes(),
      "value": value?.value,
      "rcm": switch (rseed) {
        SaplingRSeedBeforeZip212(:final inner) => inner.toBytes(),
        _ => null
      },
      "rseed": switch (rseed) {
        SaplingRSeedAfterZip212(:final inner) => inner,
        _ => null
      },
      "rcv": rcv?.toSerializeJson(),
      "proof_generation_key": proofGenerationKey?.toSerializeJson(),
      "witness": witness?.toSerializeJson(),
      "alpha": alpha?.toBytes(),
      "zip32_derivation": zip32derivation?.toSerializeJson(),
      "dummy_ask": dummySk?.toBytes(),
      "proprietary": proprietary
    };
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMege(SaplingPcztSpend other) {
    return PcztUtils.canMerge(spendAuthSig, other.spendAuthSig) &&
        PcztUtils.canMerge(recipient, other.recipient) &&
        PcztUtils.canMerge(value, other.value) &&
        PcztUtils.canMerge(rseed, other.rseed) &&
        PcztUtils.canMerge(rcv, other.rcv) &&
        PcztUtils.canMerge(proofGenerationKey, other.proofGenerationKey) &&
        PcztUtils.canMerge(witness, other.witness) &&
        PcztUtils.canMerge(alpha, other.alpha) &&
        PcztUtils.canMerge(zkproof, other.zkproof) &&
        PcztUtils.canMerge(zip32derivation, other.zip32derivation) &&
        PcztUtils.canMerge(dummySk, other.dummySk) &&
        PcztUtils.canMerge(cv, other.cv) &&
        PcztUtils.canMerge(nullifier, other.nullifier) &&
        PcztUtils.canMerge(rk, other.rk);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  SaplingPcztSpend? merge(SaplingPcztSpend other) {
    if (!canMege(other)) return null;
    final proprietary =
        PcztUtils.mergeProprietary(this.proprietary, other.proprietary);
    if (proprietary == null) return null;
    final zkproof = this.zkproof ?? other.zkproof;
    final spendAuthSig = this.spendAuthSig ?? other.spendAuthSig;
    final recipient = this.recipient ?? other.recipient;
    final value = this.value ?? other.value;
    final rseed = this.rseed ?? other.rseed;
    final rcv = this.rcv ?? other.rcv;
    final proofGenerationKey =
        this.proofGenerationKey ?? other.proofGenerationKey;
    final alpha = this.alpha ?? other.alpha;
    final zip32derivation = this.zip32derivation ?? other.zip32derivation;
    final dummySk = this.dummySk ?? other.dummySk;
    final witness = this.witness ?? other.witness;
    return SaplingPcztSpend(
        nullifier: nullifier,
        rk: rk,
        cv: cv,
        alpha: alpha,
        dummySk: dummySk,
        proofGenerationKey: proofGenerationKey,
        proprietary: proprietary,
        rcv: rcv,
        recipient: recipient,
        rseed: rseed,
        spendAuthSig: spendAuthSig,
        value: value,
        witness: witness,
        zip32derivation: zip32derivation,
        zkproof: zkproof);
  }
}

class SaplingPcztOutput with LayoutSerializable {
  final SaplingValueCommitment cv;
  final SaplingExtractedNoteCommitment cmu;
  final EphemeralKeyBytes ephemeralKey;
  final List<int> encCiphertext;
  final List<int> outCiphertext;
  final SaplingPaymentAddress? recipient;
  final ZAmount? value;
  final List<int>? rseed;
  final SaplingValueCommitTrapdoor? rcv;
  final List<int>? ock;

  GrothProofBytes? _zkproof;
  GrothProofBytes? get zkproof => _zkproof;
  PcztZip32Derivation? _zip32derivation;
  PcztZip32Derivation? get zip32derivation => _zip32derivation;
  String? _userAddress;
  String? get userAddress => _userAddress;
  Map<String, List<int>> _proprietary;
  Map<String, List<int>> get proprietary => _proprietary;
  SaplingPcztOutput copyWith({
    final SaplingValueCommitment? cv,
    final SaplingExtractedNoteCommitment? cmu,
    final EphemeralKeyBytes? ephemeralKey,
    final List<int>? encCiphertext,
    final List<int>? outCiphertext,
    final GrothProofBytes? zkproof,
    final SaplingPaymentAddress? recipient,
    final ZAmount? value,
    final List<int>? rseed,
    final SaplingValueCommitTrapdoor? rcv,
    final List<int>? ock,
    PcztZip32Derivation? zip32derivation,
    String? userAddress,
    Map<String, List<int>>? proprietary,
  }) {
    return SaplingPcztOutput(
        cv: cv ?? this.cv,
        cmu: cmu ?? this.cmu,
        ephemeralKey: ephemeralKey ?? this.ephemeralKey,
        encCiphertext: encCiphertext ?? this.encCiphertext,
        outCiphertext: outCiphertext ?? this.outCiphertext,
        ock: ock ?? this.ock,
        proprietary: proprietary ?? this.proprietary,
        rcv: rcv ?? this.rcv,
        recipient: recipient ?? this.recipient,
        rseed: rseed ?? this.rseed,
        userAddress: userAddress ?? this.userAddress,
        value: value ?? this.value,
        zip32derivation: zip32derivation ?? this.zip32derivation,
        zkproof: zkproof ?? this.zkproof);
  }

  SaplingPcztOutput(
      {required this.cv,
      required this.cmu,
      required this.ephemeralKey,
      required List<int> encCiphertext,
      required List<int> outCiphertext,
      GrothProofBytes? zkproof,
      this.recipient,
      this.value,
      List<int>? rseed,
      this.rcv,
      List<int>? ock,
      PcztZip32Derivation? zip32derivation,
      String? userAddress,
      Map<String, List<int>> proprietary = const {}})
      : _proprietary = proprietary
            .map((k, v) => MapEntry(k, v.asImmutableBytes))
            .immutable,
        _zip32derivation = zip32derivation,
        _userAddress = userAddress,
        rseed = rseed
            ?.exc(length: 32, operation: "Invalid rseed bytes length.")
            .asImmutableBytes,
        encCiphertext = encCiphertext
            .exc(
              length: NoteEncryptionConst.encCiphertextSize,
              operation: "SaplingPcztOutput",
              reason: "Invalid encCiphertext bytes length.",
            )
            .asImmutableBytes,
        outCiphertext = outCiphertext
            .exc(
              length: NoteEncryptionConst.outCiphertextSize,
              operation: "SaplingPcztOutput",
              reason: "Invalid outCiphertext bytes length.",
            )
            .asImmutableBytes,
        ock = ock
            ?.exc(
                length: 32,
                operation: "SaplingPcztOutput",
                reason: "Invalid ock bytes length.")
            .asImmutableBytes,
        _zkproof = zkproof;
  factory SaplingPcztOutput.deserializeJson(Map<String, dynamic> json) {
    return SaplingPcztOutput(
      cv: SaplingValueCommitment.deserializeJson(
          json.valueEnsureAsMap<String, dynamic>("cv")),
      cmu: SaplingExtractedNoteCommitment.deserializeJson(
          json.valueEnsureAsMap<String, dynamic>("cmu")),
      ephemeralKey: EphemeralKeyBytes.deserializeJson(
          json.valueEnsureAsMap<String, dynamic>("ephemeral_key")),
      encCiphertext: json.valueAsBytes("enc_ciphertext"),
      outCiphertext: json.valueAsBytes("out_ciphertext"),
      zkproof: json.valueTo<GrothProofBytes?, Map<String, dynamic>>(
          key: "zkproof", parse: (v) => GrothProofBytes.deserializeJson(v)),
      recipient: json.valueTo<SaplingPaymentAddress?, List<int>>(
        key: "recipient",
        parse: (v) => SaplingPaymentAddress.fromBytes(v),
      ),
      value: json.valueTo<ZAmount?, BigInt>(
          key: "value", parse: (v) => ZAmount(v)),
      rseed: json.valueAsBytes("rseed"),
      rcv: json.valueTo<SaplingValueCommitTrapdoor?, Map<String, dynamic>>(
          key: "rcv",
          parse: (v) => SaplingValueCommitTrapdoor.deserializeJson(v)),
      ock: json.valueAsBytes("ock"),
      zip32derivation: json.valueTo<PcztZip32Derivation?, Map<String, dynamic>>(
        key: "zip32_derivation",
        parse: (v) => PcztZip32Derivation.deserializeJson(v),
      ),
      userAddress: json.valueAsString("user_address"),
      proprietary: json.valueEnsureAsMap<String, List<int>>("proprietary"),
    );
  }

  SaplingPcztOutput clone() => SaplingPcztOutput(
      cv: cv,
      cmu: cmu,
      ephemeralKey: ephemeralKey,
      encCiphertext: encCiphertext,
      outCiphertext: outCiphertext,
      ock: ock,
      proprietary: proprietary,
      rcv: rcv,
      recipient: recipient,
      rseed: rseed,
      userAddress: userAddress,
      value: value,
      zip32derivation: zip32derivation,
      zkproof: zkproof);

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      SaplingValueCommitment.layout(property: "cv"),
      SaplingExtractedNoteCommitment.layout(property: "cmu"),
      EphemeralKeyBytes.layout(property: "ephemeral_key"),
      LayoutConst.bcsBytes(property: "enc_ciphertext"),
      LayoutConst.bcsBytes(property: "out_ciphertext"),
      LayoutConst.optional(GrothProofBytes.layout(), property: "zkproof"),
      LayoutConst.optional(LayoutConst.fixedBlobN(43), property: "recipient"),
      LayoutConst.optional(LayoutConst.lebU64(), property: "value"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "rseed"),
      LayoutConst.optional(SaplingValueCommitTrapdoor.layout(),
          property: "rcv"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "ock"),
      LayoutConst.optional(PcztZip32Derivation.layout(),
          property: "zip32_derivation"),
      LayoutConst.optional(LayoutConst.string(), property: "user_address"),
      LayoutConst.bscMap<String, List<int>>(
          LayoutConst.bcsString(), LayoutConst.bcsBytes(),
          property: "proprietary")
    ], property: property);
  }

  void setZip32Derivation(PcztZip32Derivation? derivation) {
    _zip32derivation = derivation;
  }

  /// Adds a proprietary key-value pair to the output.
  void addProprietary(String name, List<int> value) {
    final proprietary = this.proprietary.clone();
    proprietary[name] = value.clone();
    _proprietary = proprietary.immutable;
  }

  void setUserAddress(String? userAddress) {
    _userAddress = userAddress;
  }

  void setZkproof(GrothProofBytes? zkproof) {
    _zkproof = zkproof;
  }

  SaplingPaymentAddress getRecipient() {
    final recipient = this.recipient;
    if (recipient == null) {
      throw SaplingPcztException.operationFailed("getRecipient",
          reason: "Missing output recipient.");
    }
    return recipient;
  }

  GrothProofBytes getZkproof() {
    final zkproof = this.zkproof;
    if (zkproof == null) {
      throw SaplingPcztException.operationFailed("getZkproof",
          reason: "Missing output zkproof.");
    }
    return zkproof;
  }

  ZAmount getValue() {
    final value = this.value;
    if (value == null) {
      throw SaplingPcztException.operationFailed("getValue",
          reason: "Missing output value.");
    }
    return value;
  }

  List<int> getRseed() {
    final rseed = this.rseed;
    if (rseed == null) {
      throw SaplingPcztException.operationFailed("getRseed",
          reason: "Missing output random seed.");
    }
    return rseed;
  }

  SaplingValueCommitTrapdoor getRcv() {
    final rcv = this.rcv;
    if (rcv == null) {
      throw SaplingPcztException.operationFailed("getRcv",
          reason: "Missing output value commit trapdoor.");
    }
    return rcv;
  }

  void verifyCv() {
    final value = getValue();
    final rcv = getRcv();
    final cvNet = SaplingValueCommitment.derive(value: value, rcv: rcv);
    if (cvNet == cv) return;
    throw SaplingPcztException.operationFailed("verifyCv",
        reason: "Invalid output value commit.");
  }

  void verifyNcommitment(ZCashCryptoContext context) {
    final recipient = getRecipient();
    final value = getValue();
    final rseed = getRseed();
    final note = SaplingNote(
        recipient: recipient,
        value: value,
        rseed: SaplingRSeedAfterZip212(rseed));
    if (note.cmu(context) != cmu) {
      throw SaplingPcztException.operationFailed("verifyNcommitment",
          reason: "Invalid output extracted note commitment");
    }
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "cv": cv.toSerializeJson(),
      "cmu": cmu.toSerializeJson(),
      "ephemeral_key": ephemeralKey.toSerializeJson(),
      "enc_ciphertext": encCiphertext,
      "out_ciphertext": outCiphertext,
      "zkproof": zkproof?.toSerializeJson(),
      "recipient": recipient?.toBytes(),
      "value": value?.value,
      "rseed": rseed,
      "rcv": rcv?.toSerializeJson(),
      "ock": ock,
      "zip32_derivation": zip32derivation?.toSerializeJson(),
      "user_address": userAddress,
      "proprietary": proprietary
    };
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMege(SaplingPcztOutput other) {
    return PcztUtils.canMerge(encCiphertext, other.encCiphertext) &&
        PcztUtils.canMerge(outCiphertext, other.outCiphertext) &&
        PcztUtils.canMerge(recipient, other.recipient) &&
        PcztUtils.canMerge(value, other.value) &&
        PcztUtils.canMerge(rseed, other.rseed) &&
        PcztUtils.canMerge(rcv, other.rcv) &&
        PcztUtils.canMerge(ock, other.ock) &&
        PcztUtils.canMerge(zkproof, other.zkproof) &&
        PcztUtils.canMerge(zip32derivation, other.zip32derivation) &&
        PcztUtils.canMerge(userAddress, other.userAddress) &&
        PcztUtils.canMerge(cv, other.cv) &&
        PcztUtils.canMerge(cmu, other.cmu) &&
        PcztUtils.canMerge(ephemeralKey, other.ephemeralKey);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  SaplingPcztOutput? merge(SaplingPcztOutput other) {
    if (!canMege(other)) return null;
    final proprietary =
        PcztUtils.mergeProprietary(this.proprietary, other.proprietary);
    if (proprietary == null) return null;
    final zkproof = this.zkproof ?? other.zkproof;
    final recipient = this.recipient ?? other.recipient;
    final value = this.value ?? other.value;
    final rseed = this.rseed ?? other.rseed;
    final rcv = this.rcv ?? other.rcv;
    final ock = this.ock ?? other.ock;
    final zip32derivation = this.zip32derivation ?? other.zip32derivation;
    final userAddress = this.userAddress ?? other.userAddress;
    return SaplingPcztOutput(
        cv: cv,
        cmu: cmu,
        ephemeralKey: ephemeralKey,
        encCiphertext: encCiphertext,
        outCiphertext: outCiphertext,
        ock: ock,
        proprietary: proprietary,
        rcv: rcv,
        recipient: recipient,
        rseed: rseed,
        userAddress: userAddress,
        value: value,
        zip32derivation: zip32derivation,
        zkproof: zkproof);
  }
}

class SaplingPcztBundle
    with LayoutSerializable
    implements
        PcztBundle<SaplingBundle, SaplingExtractedBundle, SaplingPcztBundle> {
  final List<SaplingPcztSpend> spends;
  final List<SaplingPcztOutput> outputs;
  @override
  final ZAmount valueSum;
  final SaplingAnchor anchor;
  SaplingBindingAuthorizingKey? _bsk;
  SaplingBindingAuthorizingKey? get bsk => _bsk;
  SaplingPcztBundle(
      {required List<SaplingPcztSpend> spends,
      required List<SaplingPcztOutput> outputs,
      required this.valueSum,
      required this.anchor,
      SaplingBindingAuthorizingKey? bsk})
      : _bsk = bsk,
        spends = spends.immutable,
        outputs = outputs.immutable;

  @override
  SaplingPcztBundle clone() => SaplingPcztBundle(
      spends: spends,
      outputs: outputs,
      valueSum: valueSum,
      anchor: anchor,
      bsk: bsk);

  factory SaplingPcztBundle.deserializeJson(Map<String, dynamic> json) {
    return SaplingPcztBundle(
        spends: json
            .valueEnsureAsList<Map<String, dynamic>>("spends")
            .map((e) => SaplingPcztSpend.deserializeJson(e))
            .toList(),
        outputs: json
            .valueEnsureAsList<Map<String, dynamic>>("outputs")
            .map((e) => SaplingPcztOutput.deserializeJson(e))
            .toList(),
        valueSum: ZAmount(json.valueAs("value_sum")),
        anchor: SaplingAnchor.deserializeJson(json.valueAs("anchor")),
        bsk: json.valueTo<SaplingBindingAuthorizingKey?, List<int>>(
            key: "bsk",
            parse: (v) => SaplingBindingAuthorizingKey.fromBytes(v)));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.bcsVector(SaplingPcztSpend.layout(), property: "spends"),
      LayoutConst.bcsVector(SaplingPcztOutput.layout(), property: "outputs"),
      LayoutConst.lebI128(property: "value_sum"),
      SaplingAnchor.layout(property: "anchor"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "bsk"),
    ], property: property);
  }

  SaplingBindingAuthorizingKey getBsk() {
    final bsk = this.bsk;
    if (bsk == null) {
      throw SaplingPcztException.operationFailed("getBsk",
          reason: "Missing bundle binding signing key.");
    }
    return bsk;
  }

  void setProofGenerationKey(
      int index, SaplingProofGenerationKey proofGenerationKey) {
    final spend = spends.elementAtOrNull(index);
    if (spend == null) {
      throw SaplingPcztException.operationFailed("setProofGenerationKey",
          reason: "Index out of range.");
    }
    spend.setProofGenerationKey(proofGenerationKey);
  }

  void setBsk(SaplingBindingAuthorizingKey? bsk) {
    _bsk = bsk;
  }

  void setSpendProof(int index, GrothProofBytes proof) {
    final spend = spends.elementAtOrNull(index);
    if (spend == null) {
      throw SaplingPcztException.operationFailed("setSpendProof",
          reason: "Index out of range.");
    }
    spend.setZkproof(proof);
  }

  void setOutputProof(int index, GrothProofBytes proof) {
    final output = outputs.elementAtOrNull(index);
    if (output == null) {
      throw SaplingPcztException.operationFailed("setOutputProof",
          reason: "Index out of range.");
    }
    output.setZkproof(proof);
  }

  ({
    List<SaplingProofInputs<SaplingSpend>> circuits,
    List<SaplingPcztSpend> spends,
  }) createSpendCircuits() {
    final spends = this.spends.clone();
    final spendsCircuit = spends.map((e) {
      final note = SaplingNote(
          recipient: e.getRecipient(),
          value: e.getValue(),
          rseed: e.getRseed());
      final alpha = e.getAlpha();
      final rcv = e.getRcv();
      final merklePath = e.getWitness();
      return SaplingProofInputs(
          circuit: SaplingSpend.build(
              proofGenerationKey: e.getProofGenerationKey(),
              diversifier: note.recipient.diversifier,
              rseed: note.rseed,
              value: note.value,
              alpha: alpha,
              rcv: rcv,
              anchor: anchor,
              merklePath: merklePath),
          r: JubJubNativeFq.random(),
          s: JubJubNativeFq.random());
    }).toList();

    return (circuits: spendsCircuit, spends: spends);
  }

  ({
    List<SaplingProofInputs<SaplingOutput>> circuits,
    List<SaplingPcztOutput> outputs
  }) createOutputCircuits() {
    final outputs = this.outputs.clone();
    final outputCircuit = outputs.map((e) {
      final recipient = e.getRecipient();
      final value = e.getValue();
      final note = SaplingNote(
          recipient: recipient,
          value: value,
          rseed: SaplingRSeedAfterZip212(e.getRseed()));
      final esk = note.deriveEsk() ?? JubJubNativeFr.random();
      final rcm = note.rseed.rcm();
      final rcv = e.getRcv();
      return SaplingProofInputs(
          circuit: SaplingOutput.build(
              esk: esk,
              paymentAddress: recipient,
              rcm: rcm,
              value: value,
              rcv: rcv),
          r: JubJubNativeFq.random(),
          s: JubJubNativeFq.random());
    }).toList();
    return (circuits: outputCircuit, outputs: outputs);
  }

  Future<void> createProofs(ZCashCryptoContext context) async {
    final spends = createSpendCircuits();
    final proofs = await context.createSaplingSpendProofs(spends.circuits);
    for (final i in proofs.indexed) {
      final proof = GrothProofBytes(i.$2.toSerializeBytes());

      spends.spends[i.$1].setZkproof(proof);
    }
    final outputs = createOutputCircuits();
    final outputProofs =
        await context.createSaplingOutputProofs(outputs.circuits);
    for (final i in outputProofs.indexed) {
      final proof = GrothProofBytes(i.$2.toSerializeBytes());
      outputs.outputs[i.$1].setZkproof(proof);
    }
  }

  @override
  SaplingExtractedBundle? extract() {
    final bundle = _toTxData();
    if (bundle == null) return null;
    final bsk = getBsk();
    return SaplingExtractedBundle(bundle: bundle, bindingSigningKey: bsk);
  }

  @override
  SaplingBundle? extractEffects() => _toTxData(extract: false);

  SaplingBundle? _toTxData({bool extract = true}) {
    if (this.spends.isEmpty && this.outputs.isEmpty) return null;
    final spends = this.spends.map((e) {
      final zkProof = e.zkproof;
      final authSig = e.spendAuthSig;
      if (extract && (zkProof == null || authSig == null)) {
        throw SaplingPcztException.operationFailed("extract",
            reason: zkProof == null
                ? "Missing spend proof."
                : "Missing spend authorization.");
      }
      return SaplingSpendDescription(
          cv: e.cv,
          anchor: anchor,
          nullifier: e.nullifier,
          rk: e.rk,
          zkProof: zkProof,
          authSig: authSig);
    }).toList();

    final outputs = this.outputs.map((e) {
      final zkProof = e.zkproof;
      if (extract && zkProof == null) {
        throw SaplingPcztException.operationFailed("extract",
            reason: "Missing output zkproof.");
      }
      return SaplingOutputDescription(
          cv: e.cv,
          cmu: e.cmu,
          ephemeralKey: e.ephemeralKey,
          encCiphertext: e.encCiphertext,
          outCiphertext: e.outCiphertext,
          zkproof: zkProof);
    }).toList();

    return SaplingBundle(
        shieldedSpends: spends,
        shieldedOutputs: outputs,
        valueBalance: valueSum.asI64(),
        authorization: null);
  }

  void _finalizeAndSetBsk() {
    final sumSpendsRcvs = spends
        .map((e) => e.getRcv())
        .fold(SaplingTrapdoorSum.zero(), (p, c) => p + c);
    final sumOutputRcvs = outputs
        .map((e) => e.getRcv())
        .fold(SaplingTrapdoorSum.zero(), (p, c) => p + c);

    final bsk = (sumSpendsRcvs - sumOutputRcvs).toBsk();
    final sumSpendCvs = spends
        .map((e) => e.cv)
        .fold(SaplingCommitmentSum.zero(), (p, c) => p + c);
    final sumOutputCvs = outputs
        .map((e) => e.cv)
        .fold(SaplingCommitmentSum.zero(), (p, c) => p + c);
    final bvk = (sumSpendCvs - sumOutputCvs).toBvk(valueSum);
    if (bsk.toVerificationKey() != bvk) {
      throw SaplingPcztException.operationFailed("finalize",
          reason: "value commit mismatch.");
    }
    setBsk(bsk);
  }

  Future<void> finalize(
      {required List<int> sighash, required ZCashCryptoContext context}) async {
    _finalizeAndSetBsk();
    for (final i in spends) {
      final sk = i.dummySk;
      if (sk == null) continue;
      await i.sign(sighash: sighash, ask: sk, context: context);
    }
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "spends": spends.map((e) => e.toSerializeJson()).toList(),
      "outputs": outputs.map((e) => e.toSerializeJson()).toList(),
      "value_sum": valueSum.value,
      "anchor": anchor.toSerializeJson(),
      "bsk": bsk?.toBytes()
    };
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  SaplingPcztBundle? merge(
      {required SaplingPcztBundle other,
      required PcztGlobal global,
      required PcztGlobal otherGlobal}) {
    if (anchor != other.anchor) return null;
    List<SaplingPcztSpend> spends = this.spends;
    List<SaplingPcztOutput> outputs = this.outputs;
    ZAmount valueSum = this.valueSum;

    switch ((bsk, other.bsk)) {
      case (
            final SaplingBindingAuthorizingKey a,
            final SaplingBindingAuthorizingKey b
          )
          when a != b:
        {
          return null;
        }
      case (final SaplingBindingAuthorizingKey _, null):
      case (null, final SaplingBindingAuthorizingKey _):
        if (spends.length != other.spends.length ||
            outputs.length != other.outputs.length ||
            valueSum != other.valueSum) {
          return null;
        }
        break;
      default:
        if ((spends.length < other.spends.length &&
                outputs.length > other.outputs.length) ||
            (spends.length > other.spends.length &&
                outputs.length < other.outputs.length)) {
          return null;
        }
        if ((spends.length < other.spends.length &&
                !global.shieldedModifiable()) ||
            (spends.length > other.spends.length &&
                !otherGlobal.shieldedModifiable())) {
          return null;
        }
        if (spends.length < other.spends.length) {
          spends = [...spends, ...other.spends.sublist(spends.length)];
          valueSum = other.valueSum;
        }

        if ((outputs.length < other.outputs.length &&
                !global.shieldedModifiable()) ||
            (outputs.length > other.outputs.length &&
                !otherGlobal.shieldedModifiable())) {
          return null;
        }
        if (outputs.length < other.outputs.length) {
          outputs = [...outputs, ...other.outputs.sublist(outputs.length)];
          valueSum = other.valueSum;
        }
        break;
    }
    List<SaplingPcztSpend> mergedSpends = [];
    List<SaplingPcztOutput> mergedOutputs = [];
    for (final i in spends.indexed) {
      final merge = i.$2.merge(other.spends[i.$1]);
      if (merge == null) return null;
      mergedSpends.add(merge);
    }
    for (final i in outputs.indexed) {
      final merge = i.$2.merge(other.outputs[i.$1]);
      if (merge == null) return null;
      mergedOutputs.add(merge);
    }
    return SaplingPcztBundle(
        spends: mergedSpends,
        outputs: mergedOutputs,
        valueSum: valueSum,
        anchor: anchor,
        bsk: bsk);
  }
}

class SaplingExtractedBundle implements ExtractedBundle<SaplingBundle> {
  @override
  final SaplingBundle bundle;
  final SaplingBindingAuthorizingKey bindingSigningKey;
  const SaplingExtractedBundle(
      {required this.bundle, required this.bindingSigningKey});

  Future<SaplingBundle> buildBindingAutorization(
      {required List<int> sighash,
      required ZCashCryptoContext context,
      bool verifySignature = true}) async {
    sighash = sighash.exc(
        length: 32,
        operation: "buildBindingAutorization",
        reason: "Invalid sighash bytes length.");
    for (final i in bundle.shieldedSpends) {
      final signature = i.authSig;
      if (signature == null) {
        throw SaplingPcztException.operationFailed("buildBindingAutorization",
            reason: "Missing spend autorization.");
      }
      if (verifySignature &&
          !await context.verifyRedJubJubSignature(
              signature: signature, message: sighash, vk: i.rk)) {
        throw SaplingPcztException.operationFailed("buildBindingAutorization",
            reason: "spend autorization verification failed.");
      }
    }
    final bindingSignature = bindingSigningKey.sign(sighash);
    return SaplingBundle(
        shieldedOutputs: bundle.shieldedOutputs,
        shieldedSpends: bundle.shieldedSpends,
        valueBalance: bundle.valueBalance,
        authorization:
            SaplingBundleAuthorization(bindingSignature: bindingSignature));
  }

  @override
  ZAmount get valueSum => bundle.valueBalance;
}
