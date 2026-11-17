import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/zcash.dart';

class OrchardPcztSpend with LayoutSerializable {
  final OrchardNullifier nullifier;
  final RedPallasSpendPublicKey rk;
  final OrchardAddress? recipient;
  final ZAmount? value;
  final OrchardRho? rho;
  final OrchardNoteRandomSeed? rseed;
  final OrchardFullViewingKey? fvk;
  final OrchardMerklePath? witness;
  final BuBytes? alpha;
  final OrchardSpendingKey? dummySk;

  ReddsaSignature? _spendAuthSig;
  ReddsaSignature? get spendAuthSig => _spendAuthSig;
  PcztZip32Derivation? _zip32derivation;
  PcztZip32Derivation? get zip32derivation => _zip32derivation;
  Map<String, List<int>> _proprietary;
  Map<String, List<int>> get proprietary => _proprietary;
  OrchardPcztSpend({
    required this.nullifier,
    required this.rk,
    ReddsaSignature? spendAuthSig,
    this.recipient,
    this.value,
    this.rho,
    this.rseed,
    this.fvk,
    this.witness,
    this.alpha,
    PcztZip32Derivation? zip32derivation,
    this.dummySk,
    Map<String, List<int>> proprietary = const {},
  }) : _proprietary =
           proprietary.map((k, v) => MapEntry(k, v.toImutableBytes)).immutable,
       _zip32derivation = zip32derivation,
       _spendAuthSig = spendAuthSig;
  factory OrchardPcztSpend.deserializeJson(Map<String, dynamic> json) {
    return OrchardPcztSpend(
      nullifier: OrchardNullifier.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("nullifier"),
      ),
      rk: RedPallasSpendPublicKey.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("rk"),
      ),
      spendAuthSig: json.valueTo<ReddsaSignature?, Map<String, dynamic>>(
        key: "spend_auth_sig",
        parse: (v) => ReddsaSignature.deserializeJson(v),
      ),
      recipient: json.valueTo<OrchardAddress?, List<int>>(
        key: "recipient",
        parse: (v) => OrchardAddress.fromBytes(v),
      ),
      value: json.valueTo<ZAmount?, BigInt>(
        key: "value",
        parse: (v) => ZAmount(v),
      ),
      rho: json.valueTo<OrchardRho?, Map<String, dynamic>>(
        key: "rho",
        parse: (v) => OrchardRho.deserializeJson(v),
      ),
      rseed: json.valueTo<OrchardNoteRandomSeed?, Map<String, dynamic>>(
        key: "rseed",
        parse: (v) => OrchardNoteRandomSeed.deserializeJson(v),
      ),
      fvk: json.valueTo<OrchardFullViewingKey?, List<int>>(
        key: "fvk",
        parse: (v) => OrchardFullViewingKey.fromBytesUnchecked(v),
      ),
      witness: json.valueTo<OrchardMerklePath?, Map<String, dynamic>>(
        key: "witness",
        parse: (v) => OrchardMerklePath.deserializeJson(v),
      ),
      alpha: json.valueTo<BuBytes?, List<int>>(
        key: "alpha",
        parse: (v) {
          VestaFq.fromBytes(v);
          return BuBytes.from(v);
        },
      ),
      zip32derivation: json.valueTo<PcztZip32Derivation?, Map<String, dynamic>>(
        key: "zip32_derivation",
        parse: (v) => PcztZip32Derivation.deserializeJson(v),
      ),
      dummySk: json.valueTo<OrchardSpendingKey?, List<int>>(
        key: "dummy_sk",
        parse: (v) => OrchardSpendingKey(v),
      ),
      proprietary: json.valueEnsureAsMap<String, List<int>>("proprietary"),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      Nullifier.layout(property: "nullifier"),
      RedPallasSpendPublicKey.layout(property: "rk"),
      LayoutConst.optional(
        ReddsaSignature.layout(),
        property: "spend_auth_sig",
      ),
      LayoutConst.optional(LayoutConst.fixedBlobN(43), property: "recipient"),
      LayoutConst.optional(LayoutConst.lebU64(), property: "value"),
      LayoutConst.optional(OrchardRho.layout(), property: "rho"),
      LayoutConst.optional(OrchardNoteRandomSeed.layout(), property: "rseed"),
      LayoutConst.optional(LayoutConst.fixedBlobN(96), property: "fvk"),
      LayoutConst.optional(OrchardMerklePath.layout(), property: "witness"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "alpha"),
      LayoutConst.optional(
        PcztZip32Derivation.layout(),
        property: "zip32_derivation",
      ),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "dummy_sk"),
      LayoutConst.bcsMap<String, List<int>>(
        LayoutConst.bcsString(),
        LayoutConst.bcsBytes(),
        property: "proprietary",
      ),
    ], property: property);
  }

  OrchardPcztSpend clone() => OrchardPcztSpend(
    nullifier: nullifier,
    rk: rk,
    alpha: alpha,
    dummySk: dummySk,
    fvk: fvk,
    proprietary: proprietary,
    recipient: recipient,
    rho: rho,
    rseed: rseed,
    spendAuthSig: spendAuthSig,
    value: value,
    witness: witness,
    zip32derivation: zip32derivation,
  );

  OrchardPcztSpend copyWith({
    OrchardNullifier? nullifier,
    RedPallasSpendPublicKey? rk,
    ReddsaSignature? spendAuthSig,
    OrchardAddress? recipient,
    ZAmount? value,
    OrchardRho? rho,
    OrchardNoteRandomSeed? rseed,
    OrchardFullViewingKey? fvk,
    OrchardMerklePath? witness,
    BuBytes? alpha,
    PcztZip32Derivation? zip32derivation,
    OrchardSpendingKey? dummySk,
    Map<String, List<int>>? proprietary,
  }) {
    return OrchardPcztSpend(
      nullifier: nullifier ?? this.nullifier,
      rk: rk ?? this.rk,
      alpha: alpha ?? this.alpha,
      dummySk: dummySk ?? this.dummySk,
      fvk: fvk ?? this.fvk,
      proprietary: proprietary ?? this.proprietary,
      recipient: recipient ?? this.recipient,
      rho: rho ?? this.rho,
      rseed: rseed ?? this.rseed,
      spendAuthSig: spendAuthSig ?? this.spendAuthSig,
      value: value ?? this.value,
      witness: witness ?? this.witness,
      zip32derivation: zip32derivation ?? this.zip32derivation,
    );
  }

  ZAmount getValue() {
    final value = this.value;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getValue",
        reason: "Missing spend value.",
      );
    }
    return value;
  }

  OrchardAddress getRecipient() {
    final value = recipient;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getRecipient",
        reason: "Missing spend recipient.",
      );
    }
    return value;
  }

  OrchardRho getRho() {
    final value = rho;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getRho",
        reason: "Missing spend rho.",
      );
    }
    return value;
  }

  OrchardNoteRandomSeed getRseed() {
    final value = rseed;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getRseed",
        reason: "Missing spend rseed.",
      );
    }
    return value;
  }

  OrchardFullViewingKey getFvk() {
    final value = fvk;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getFvk",
        reason: "Missing spend full view key.",
      );
    }
    return value;
  }

  OrchardMerklePath getWitness() {
    final value = witness;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getWitness",
        reason: "Missing spend witness.",
      );
    }
    return value;
  }

  BuBytes getAlpha() {
    final value = alpha;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getAlpha",
        reason: "Missing spend alpha.",
      );
    }
    return value;
  }

  OrchardSpendingKey getDummySk() {
    final value = dummySk;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getDummySk",
        reason: "Missing spend dummy secret key.",
      );
    }
    return value;
  }

  void setZip32Derivation(PcztZip32Derivation? derivation) {
    _zip32derivation = derivation;
  }

  /// Adds a proprietary key-value pair to the input.
  void addProprietary(String name, List<int> value) {
    final proprietary = this.proprietary.clone();
    proprietary[name] = value.clone();
    _proprietary = proprietary.immutable;
  }

  void setAuthSig(ReddsaSignature sig) {
    _spendAuthSig = sig;
  }

  OrchardFullViewingKey findFvk({OrchardFullViewingKey? fvk}) {
    final sFvk = this.fvk;
    if (fvk != null && sFvk != null) {
      if (fvk == sFvk) return fvk;
      throw ZcashErrors.orchardPcztFailed(
        "findFvk",
        reason: "Mismatch full viewing key.",
      );
    }
    if (fvk != null) return fvk;
    if (sFvk != null) return sFvk;
    throw ZcashErrors.orchardPcztFailed(
      "findFvk",
      reason: "Missing orchard full viewing key.",
    );
  }

  void verifyNullifier(
    ZcashCryptoContext context, {
    OrchardFullViewingKey? fvk,
    // Note version of the pool the spend belongs to
    // (orchard v2, ironwood v3). The rebuilt note must use the same
    // version it was created with, or the recomputed nullifier can never
    // match. Defaults to v2 for version-less legacy data.
    OrchardNoteVersion version = OrchardNoteVersion.v2,
  }) {
    fvk = findFvk(fvk: fvk);
    final note = OrchardNote.build(
      recipient: getRecipient(),
      value: getValue(),
      rseed: getRseed(),
      rho: getRho(),
      context: context,
      version: version,
    );
    final addr = fvk.scopeForAddress(address: getRecipient(), context: context);
    if (addr == null) {
      throw ZcashErrors.orchardPcztFailed(
        "verifyNullifier",
        reason: "Invalid full viewing key for note.",
      );
    }
    if (note.nullifier(context: context, fvk: fvk) != nullifier) {
      throw ZcashErrors.orchardPcztFailed(
        "verifyNullifier",
        reason: "Invalid orchard spend nullifier.",
      );
    }
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "proprietary": proprietary,
      "dummy_sk": dummySk?.toBytes(),
      "zip32_derivation": zip32derivation?.toSerializeJson(),
      "alpha": alpha,
      "witness": witness?.toSerializeJson(),
      "fvk": fvk?.toBytes(),
      "rseed": rseed?.toSerializeJson(),
      "rho": rho?.toSerializeJson(),
      "value": value?.value,
      "recipient": recipient?.toBytes(),
      "spend_auth_sig": spendAuthSig?.toSerializeJson(),
      "rk": rk.toSerializeJson(),
      "nullifier": nullifier.toSerializeJson(),
    };
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMarge(OrchardPcztSpend other) {
    return PcztUtils.canMerge(nullifier, other.nullifier) &&
        PcztUtils.canMerge(rk, other.rk) &&
        PcztUtils.canMerge(recipient, other.recipient) &&
        PcztUtils.canMerge(value, other.value) &&
        PcztUtils.canMerge(rho, other.rho) &&
        PcztUtils.canMerge(rseed, other.rseed) &&
        PcztUtils.canMerge(fvk, other.fvk) &&
        PcztUtils.canMerge(witness, other.witness) &&
        PcztUtils.canMerge(alpha, other.alpha) &&
        PcztUtils.canMerge(dummySk, other.dummySk);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  OrchardPcztSpend? merge(OrchardPcztSpend other) {
    if (!canMarge(other)) return null;
    final proprietary = PcztUtils.mergeProprietary(
      this.proprietary,
      other.proprietary,
    );
    if (proprietary == null) return null;
    final recipient = this.recipient ?? other.recipient;
    final value = this.value ?? other.value;
    final rho = this.rho ?? other.rho;
    final rseed = this.rseed ?? other.rseed;
    final fvk = this.fvk ?? other.fvk;
    final witness = this.witness ?? other.witness;
    final alpha = this.alpha ?? other.alpha;
    final dummySk = this.dummySk ?? other.dummySk;
    final zip32derivation = this.zip32derivation ?? other.zip32derivation;
    final spendAuthSig = this.spendAuthSig ?? other.spendAuthSig;

    return OrchardPcztSpend(
      nullifier: nullifier,
      rk: rk,
      alpha: alpha,
      dummySk: dummySk,
      fvk: fvk,
      proprietary: proprietary,
      recipient: recipient,
      rho: rho,
      rseed: rseed,
      spendAuthSig: spendAuthSig,
      value: value,
      witness: witness,
      zip32derivation: zip32derivation,
    );
  }
}

class OrchardPcztOutput with LayoutSerializable {
  final OrchardExtractedNoteCommitment cmx;
  final OrchardTransmittedNoteCiphertext encryptedNote;
  final OrchardAddress? recipient;
  final ZAmount? value;
  final OrchardNoteRandomSeed? rseed;
  final List<int>? ock;

  Map<String, List<int>> get proprietary => _proprietary;
  Map<String, List<int>> _proprietary;
  PcztZip32Derivation? _zip32derivation;
  PcztZip32Derivation? get zip32derivation => _zip32derivation;
  String? _userAddress;
  String? get userAddress => _userAddress;

  OrchardPcztOutput({
    required this.cmx,
    required this.encryptedNote,
    this.recipient,
    this.value,
    this.rseed,
    List<int>? ock,
    PcztZip32Derivation? zip32derivation,
    String? userAddress,
    Map<String, List<int>> proprietary = const {},
  }) : _proprietary =
           proprietary.map((k, v) => MapEntry(k, v.toImutableBytes)).immutable,
       _zip32derivation = zip32derivation,
       _userAddress = userAddress,
       ock = ock?.exc(
         length: 32,
         operation: "OrchardPcztOutput",
         reason: "Invalid ock bytes length.",
       );

  factory OrchardPcztOutput.deserializeJson(Map<String, dynamic> json) {
    return OrchardPcztOutput(
      cmx: OrchardExtractedNoteCommitment.deserializeJson(
        json.valueEnsureAsMap("cmx"),
      ),
      encryptedNote: OrchardTransmittedNoteCiphertext.deserializeJson(
        json.valueEnsureAsMap("encrypted_note"),
      ),
      recipient: json.valueTo<OrchardAddress?, List<int>>(
        key: "recipient",
        parse: (v) => OrchardAddress.fromBytes(v),
      ),
      value: json.valueTo<ZAmount?, BigInt>(
        key: "value",
        parse: (v) => ZAmount(v),
      ),
      rseed: json.valueTo<OrchardNoteRandomSeed?, Map<String, dynamic>>(
        key: "rseed",
        parse: (v) => OrchardNoteRandomSeed.deserializeJson(v),
      ),
      zip32derivation: json.valueTo<PcztZip32Derivation?, Map<String, dynamic>>(
        key: "zip32_derivation",
        parse: (v) => PcztZip32Derivation.deserializeJson(v),
      ),
      proprietary: json.valueEnsureAsMap<String, List<int>>("proprietary"),
      ock: json.valueAsBytes("ock"),
      userAddress: json.valueAs("user_address"),
    );
  }

  OrchardPcztOutput clone() => OrchardPcztOutput(
    cmx: cmx,
    encryptedNote: encryptedNote,
    ock: ock,
    proprietary: proprietary,
    recipient: recipient,
    rseed: rseed,
    userAddress: userAddress,
    value: value,
    zip32derivation: zip32derivation,
  );
  OrchardPcztOutput copyWith({
    OrchardExtractedNoteCommitment? cmx,
    OrchardTransmittedNoteCiphertext? encryptedNote,
    OrchardAddress? recipient,
    ZAmount? value,
    OrchardNoteRandomSeed? rseed,
    List<int>? ock,
    PcztZip32Derivation? zip32derivation,
    String? userAddress,
    Map<String, List<int>>? proprietary,
  }) {
    return OrchardPcztOutput(
      cmx: cmx ?? this.cmx,
      encryptedNote: encryptedNote ?? this.encryptedNote,
      ock: ock ?? this.ock,
      proprietary: proprietary ?? this.proprietary,
      recipient: recipient ?? this.recipient,
      rseed: rseed ?? this.rseed,
      userAddress: userAddress ?? this.userAddress,
      value: value ?? this.value,
      zip32derivation: zip32derivation ?? this.zip32derivation,
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      OrchardExtractedNoteCommitment.layout(property: "cmx"),
      OrchardTransmittedNoteCiphertext.layout(
        property: "encrypted_note",
        pczt: true,
      ),
      LayoutConst.optional(LayoutConst.fixedBlobN(43), property: "recipient"),
      LayoutConst.optional(LayoutConst.lebU64(), property: "value"),
      LayoutConst.optional(OrchardNoteRandomSeed.layout(), property: "rseed"),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "ock"),
      LayoutConst.optional(
        PcztZip32Derivation.layout(),
        property: "zip32_derivation",
      ),
      LayoutConst.optional(LayoutConst.bcsString(), property: "user_address"),
      LayoutConst.bcsMap<String, List<int>>(
        LayoutConst.bcsString(),
        LayoutConst.bcsBytes(),
        property: "proprietary",
      ),
    ], property: property);
  }

  void setZip32Derivation(PcztZip32Derivation? derivation) {
    _zip32derivation = derivation;
  }

  /// Adds a proprietary key-value pair to the input.
  void addProprietary(String name, List<int> value) {
    final proprietary = this.proprietary.clone();
    proprietary[name] = value.clone();
    _proprietary = proprietary.immutable;
  }

  void setUserAddress(String? userAddress) {
    _userAddress = userAddress;
  }

  OrchardAddress getRecipient() {
    final value = recipient;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getRecipient",
        reason: "Missing output recipient.",
      );
    }
    return value;
  }

  ZAmount getValue() {
    final value = this.value;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getValue",
        reason: "Missing output value.",
      );
    }
    return value;
  }

  OrchardNoteRandomSeed getRseed() {
    final value = rseed;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getRseed",
        reason: "Missing output random seed.",
      );
    }
    return value;
  }

  OrchardNoteRandomSeed getOck() {
    final value = rseed;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getOck",
        reason: "Missing output outgoing cipher key.",
      );
    }
    return value;
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "proprietary": proprietary,
      "user_address": userAddress,
      "zip32_derivation": zip32derivation?.toSerializeJson(),
      "ock": ock,
      "rseed": rseed?.toSerializeJson(),
      "value": value?.value,
      "recipient": recipient?.toBytes(),
      "encrypted_note": encryptedNote.toSerializeJson(),
      "cmx": cmx.toSerializeJson(),
    };
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMerge(OrchardPcztOutput other) {
    return PcztUtils.canMerge(cmx, other.cmx) &&
        PcztUtils.canMerge(encryptedNote, other.encryptedNote) &&
        PcztUtils.canMerge(value, other.value) &&
        PcztUtils.canMerge(userAddress, other.userAddress) &&
        PcztUtils.canMerge(recipient, other.recipient) &&
        PcztUtils.canMerge(zip32derivation, other.zip32derivation) &&
        PcztUtils.canMerge(ock, other.ock) &&
        PcztUtils.canMerge(rseed, other.rseed);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  OrchardPcztOutput? merge(OrchardPcztOutput other) {
    if (!canMerge(other)) return null;
    final proprietary = PcztUtils.mergeProprietary(
      this.proprietary,
      other.proprietary,
    );
    if (proprietary == null) return null;
    final value = this.value ?? other.value;
    final userAddress = this.userAddress ?? other.userAddress;
    final recipient = this.recipient ?? other.recipient;
    final zip32derivation = this.zip32derivation ?? other.zip32derivation;
    final ock = this.ock ?? other.ock;
    final rseed = this.rseed ?? other.rseed;
    return OrchardPcztOutput(
      cmx: cmx,
      encryptedNote: encryptedNote,
      ock: ock,
      proprietary: proprietary,
      recipient: recipient,
      rseed: rseed,
      userAddress: userAddress,
      value: value,
      zip32derivation: zip32derivation,
    );
  }
}

class OrchardPcztAction with LayoutSerializable {
  final OrchardValueCommitment cvNet;
  final OrchardPcztSpend spend;
  final OrchardPcztOutput output;
  final OrchardValueCommitTrapdoor? rcv;
  const OrchardPcztAction({
    required this.cvNet,
    required this.spend,
    required this.output,
    this.rcv,
  });
  factory OrchardPcztAction.deserializeJson(Map<String, dynamic> json) {
    return OrchardPcztAction(
      cvNet: OrchardValueCommitment.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("cv_net"),
      ),
      spend: OrchardPcztSpend.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("spend"),
      ),
      output: OrchardPcztOutput.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("output"),
      ),
      rcv: json.valueTo<OrchardValueCommitTrapdoor?, Map<String, dynamic>>(
        key: "rcv",
        parse: (v) => OrchardValueCommitTrapdoor.deserializeJson(v),
      ),
    );
  }

  OrchardPcztAction copyWith({
    OrchardValueCommitment? cvNet,
    OrchardPcztSpend? spend,
    OrchardPcztOutput? output,
    OrchardValueCommitTrapdoor? rcv,
  }) {
    return OrchardPcztAction(
      cvNet: cvNet ?? this.cvNet,
      output: output ?? this.output,
      spend: spend ?? this.spend,
      rcv: rcv ?? this.rcv,
    );
  }

  OrchardPcztAction clone() =>
      OrchardPcztAction(cvNet: cvNet, spend: spend, output: output, rcv: rcv);

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      OrchardValueCommitment.layout(property: "cv_net"),
      OrchardPcztSpend.layout(property: "spend"),
      OrchardPcztOutput.layout(property: "output"),
      LayoutConst.optional(
        OrchardValueCommitTrapdoor.layout(),
        property: "rcv",
      ),
    ], property: property);
  }

  OrchardValueCommitTrapdoor getRcv() {
    final value = rcv;
    if (value == null) {
      throw ZcashErrors.orchardPcztFailed(
        reason: "getRcv",
        "Missing value commit trapdoor.",
      );
    }
    return value;
  }

  void verifyCvNet() {
    final spendValue = spend.getValue();
    final outputValue = output.getValue();
    final rcv = getRcv();
    final cvNet = OrchardValueCommitment.derive(
      value: spendValue - outputValue,
      rcv: rcv,
    );
    if (cvNet != this.cvNet) {
      throw ZcashErrors.orchardPcztFailed(
        "verifyCvNet",
        reason: "Invalid value commitment.",
      );
    }
  }

  RedPallasSpendPrivateKey _validateAndGetRsk({
    required RedPallasSpendPrivateKey ask,
    required List<int> sighash,
    bool verifyRsk = true,
  }) {
    sighash = sighash.exc(
      length: 32,
      operation: "sign",
      reason: "Invalid sighash bytes length.",
    );
    final alpha = spend.getAlpha();
    final rk = spend.rk;
    final rsk = ask.randomize(alpha);
    if (verifyRsk && rsk.publicKey != rk) {
      throw ZcashErrors.orchardPcztFailed(
        "sign",
        reason: "Invalid spend authorization key.",
      );
    }
    return rsk;
  }

  FutureOr<void> sign({
    required List<int> sighash,
    required RedPallasSpendPrivateKey ask,
    required ZcashCryptoContext context,
    bool verifyRsk = true,
  }) async {
    final rsk = _validateAndGetRsk(
      ask: ask,
      sighash: sighash,
      verifyRsk: verifyRsk,
    );
    final signature = await context.signRedPallas(rsk, sighash);
    spend.setAuthSig(signature);
  }

  Future<void> applySignature({
    required List<int> sighash,
    required ReddsaSignature signature,
    required ZcashCryptoContext context,
    bool verifySignature = true,
  }) async {
    if (verifySignature &&
        !await context.verifyRedPallasSignature(
          vk: spend.rk,
          signature: signature,
          message: sighash,
        )) {
      throw ZcashErrors.orchardPcztFailed(
        reason: "applySignature",
        "Invalid external signature.",
      );
    }
    spend.setAuthSig(signature);
  }

  void setSpendZip32Derivation(PcztZip32Derivation? derivation) =>
      spend.setZip32Derivation(derivation);
  void setOutputZip32Derivation(PcztZip32Derivation? derivation) =>
      output.setZip32Derivation(derivation);

  /// Adds a proprietary key-value pair to the sepnd.
  void addSpendProprietary(String name, List<int> value) =>
      spend.addProprietary(name, value);

  /// Adds a proprietary key-value pair to the output.
  void addOutputProprietary(String name, List<int> value) =>
      output.addProprietary(name, value);
  void setOutputUserAddress(String? userAddress) =>
      output.setUserAddress(userAddress);

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "cv_net": cvNet.toSerializeJson(),
      "spend": spend.toSerializeJson(),
      "output": output.toSerializeJson(),
      "rcv": rcv?.toSerializeJson(),
    };
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMerge(OrchardPcztAction other) {
    return PcztUtils.canMerge(rcv, other.rcv) &&
        PcztUtils.canMerge(cvNet, other.cvNet) &&
        spend.canMarge(other.spend) &&
        output.canMerge(other.output);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  OrchardPcztAction? merge(OrchardPcztAction other) {
    if (!canMerge(other)) return null;
    final output = this.output.merge(other.output);
    final spend = this.spend.merge(other.spend);
    if (output == null || spend == null) return null;
    final rcv = this.rcv ?? other.rcv;
    return OrchardPcztAction(
      cvNet: cvNet,
      spend: spend,
      output: output,
      rcv: rcv,
    );
  }
}

class OrchardPcztBundleParams implements ExtractBundleParams {
  final OrchardProtocolVersion version;
  final bool isIronwoodPool;
  const OrchardPcztBundleParams(this.version, {this.isIronwoodPool = false});

  /// Full bundle version (pool + protocol), distinguishing orchardV3 from
  /// ironwoodV3 which share circuit V3 but differ in note version and flags.
  OrchardBundleVersion get bundleVersion => OrchardBundleVersion(
    valuePool:
        isIronwoodPool ? OrchardValuePool.ironwood : OrchardValuePool.orchard,
    protocolVersion: version,
  );

  static OrchardPcztBundleParams forBranch({
    required ZcashNetworkProtocol branch,
    required bool isIronwoodPool,
  }) {
    if (branch < ZcashNetworkProtocol.nu5) {
      throw ZcashErrors.orchardFailed(
        "OrchardPcztBundleParams.forBranch",
        reason: "Unsupported orchard version",
      );
    }
    if (isIronwoodPool && branch < ZcashNetworkProtocol.nu6_3) {
      throw ZcashErrors.orchardFailed(
        "OrchardPcztBundleParams.forBranch",
        reason: "Network does not support iroonwood pool.",
      );
    }
    if (isIronwoodPool) {
      const params = OrchardPcztBundleParams(
        OrchardProtocolVersion.v3,
        isIronwoodPool: true,
      );
      return params;
    }
    // Must stay consistent with [OrchardBundleVersion.forBranch]:
    // NU5/NU6/NU6.1 use the V1 circuit, NU6.2 the V2 circuit and NU6.3 the
    // V3 circuit. Extracting a bundle with a different protocol version than
    // the one the bundle was built with makes the flag byte unrepresentable.
    final OrchardPcztBundleParams params;
    if (branch < ZcashNetworkProtocol.nu6_2) {
      params = const OrchardPcztBundleParams(
        OrchardProtocolVersion.insecureV1,
        isIronwoodPool: false,
      );
    } else if (branch < ZcashNetworkProtocol.nu6_3) {
      params = const OrchardPcztBundleParams(
        OrchardProtocolVersion.v2,
        isIronwoodPool: false,
      );
    } else {
      params = const OrchardPcztBundleParams(
        OrchardProtocolVersion.v3,
        isIronwoodPool: false,
      );
    }
    return params;
  }
}

class OrchardPcztBundle
    with LayoutSerializable
    implements
        PcztBundle<
          OrchardBundle,
          OrchardExtractedBundle,
          OrchardPcztBundleParams,
          OrchardPcztBundle
        > {
  final List<OrchardPcztAction> actions;
  final OrchardBundleFlags flags;
  @override
  final ZAmount valueSum;
  final OrchardAnchor anchor;

  /// Bundle version (pool + protocol) for flag interpretation, mirroring
  /// official `pczt::Bundle::bundle_version`. Non-serialized context:
  /// pool is known by slot, protocol by global branch.
  final OrchardBundleVersion bundleVersion;
  OrchardProof? _zkproof;
  OrchardProof? get zkproof => _zkproof;
  RedPallasBindingPrivateKey? _bsk;
  RedPallasBindingPrivateKey? get bsk => _bsk;
  OrchardPcztBundle({
    required List<OrchardPcztAction> actions,
    required this.flags,
    required this.valueSum,
    required this.anchor,
    OrchardProof? zkproof,
    RedPallasBindingPrivateKey? bsk,
    this.bundleVersion = OrchardBundleVersion.orchardV1,
  }) : actions = actions.immutable,
       _zkproof = zkproof,
       _bsk = bsk;
  factory OrchardPcztBundle.deserializeJson(
    Map<String, dynamic> json, [
    OrchardBundleVersion version = OrchardBundleVersion.orchardV1,
  ]) {
    return OrchardPcztBundle(
      actions:
          json
              .valueEnsureAsList<Map<String, dynamic>>("actions")
              .map((e) => OrchardPcztAction.deserializeJson(e))
              .toList(),
      flags: OrchardBundleFlags.deserializeJson(json.valueAs("flags"), version),
      valueSum: ZAmount.deserializeJson(json.valueAs("value_sum")),
      anchor: OrchardAnchor.deserializeJson(json.valueAs("anchor")),
      bundleVersion: version,
      zkproof: json.valueTo<OrchardProof?, Map<String, dynamic>>(
        key: "zkproof",
        parse: (v) => OrchardProof.deserializeJson(v),
      ),
      bsk: json.valueTo<RedPallasBindingPrivateKey?, List<int>>(
        key: "bsk",
        parse: (v) => RedPallasBindingPrivateKey.fromBytes(v),
      ),
    );
  }

  OrchardPcztBundle? copyWith({
    List<OrchardPcztAction>? actions,
    OrchardBundleFlags? flags,
    ZAmount? valueSum,
    OrchardAnchor? anchor,
    OrchardProof? zkproof,
    RedPallasBindingPrivateKey? bsk,
    OrchardBundleVersion? bundleVersion,
  }) {
    return OrchardPcztBundle(
      actions: actions ?? this.actions,
      flags: flags ?? this.flags,
      valueSum: valueSum ?? this.valueSum,
      anchor: anchor ?? this.anchor,
      bsk: bsk ?? this.bsk,
      zkproof: zkproof ?? this.zkproof,
      bundleVersion: bundleVersion ?? this.bundleVersion,
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.bcsVector(OrchardPcztAction.layout(), property: "actions"),
      OrchardBundleFlags.layout(property: "flags"),
      ZAmount.layout(property: "value_sum"),
      OrchardAnchor.layout(property: "anchor"),
      LayoutConst.optional(
        OrchardProof.layout(pczt: true),
        property: "zkproof",
      ),
      LayoutConst.optional(LayoutConst.fixedBlob32(), property: "bsk"),
    ], property: property);
  }

  @override
  OrchardPcztBundle clone() => OrchardPcztBundle(
    actions: actions,
    flags: flags,
    valueSum: valueSum,
    anchor: anchor,
    bsk: bsk,
    zkproof: zkproof,
    bundleVersion: bundleVersion,
  );

  RedPallasBindingPrivateKey getBsk() {
    final bsk = this.bsk;
    if (bsk == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getBsk",
        reason: "Missing bundle binding signing key.",
      );
    }
    return bsk;
  }

  OrchardProof getZkproof() {
    final zkproof = this.zkproof;
    if (zkproof == null) {
      throw ZcashErrors.orchardPcztFailed(
        "getZkproof",
        reason: "Missing bundle proof.",
      );
    }
    return zkproof;
  }

  void setBsk(RedPallasBindingPrivateKey? bsk) {
    _bsk = bsk;
  }

  void setZkProof(OrchardProof? proof) {
    _zkproof = proof;
  }

  @override
  OrchardExtractedBundle? extract({required OrchardPcztBundleParams params}) {
    final bundle = _toTxData(version: params.bundleVersion);
    if (bundle == null) return null;
    final bsk = getBsk();
    final zkproof = getZkproof();
    return OrchardExtractedBundle(
      bundle: bundle,
      proof: zkproof,
      bindingSigningKey: bsk,
    );
  }

  @override
  OrchardBundle? extractEffects({required OrchardPcztBundleParams params}) {
    return _toTxData(version: params.bundleVersion, extract: false);
  }

  /// Verifies the cross-address restriction for this bundle, mirroring
  /// official `Bundle::verify_cross_address_restriction`.
  ///
  /// If the bundle disables cross-address transfers, every action's
  /// output must be addressed to the same expanded receiver (`g_d`,
  /// `pk_d`) as its spent note. This is a no-op for bundles that permit
  /// cross-address transfers. Requires spend and output recipients on
  /// every action. Signers must call this before signing.
  void verifyCrossAddressRestriction() {
    if (flags.crossAddressEnabled) return;
    for (final (index, action) in actions.indexed) {
      final spendRecipient = action.spend.getRecipient();
      final outputRecipient = action.output.getRecipient();
      if (!OrchardUtils.sameExpandedReceiver(spendRecipient, outputRecipient)) {
        throw ZcashErrors.orchardPcztFailed(
          "verifyCrossAddressRestriction",
          reason: "Disallowed cross-address transfer.",
          details: {"index": index.toString()},
        );
      }
    }
  }

  /// Verifies that this bundle's flags are encodable for [version]:
  /// mirrors official `Flags::to_byte` returning `None`.
  /// Throws on (Orchard,V3)+cross_true, pre-V3+cross_false, Ironwood+pre-V3.
  void verifyFlagsForVersion(OrchardBundleVersion version) {
    final pool = version.valuePool;
    final protocol = version.protocolVersion;
    if (pool == OrchardValuePool.orchard &&
        protocol == OrchardProtocolVersion.v3) {
      if (flags.crossAddressEnabled) {
        throw ZcashErrors.orchardPcztFailed(
          "verifyFlagsForVersion",
          reason: "Cross-address bit set for the Orchard pool.",
        );
      }
      return;
    }
    if (pool == OrchardValuePool.ironwood) {
      if (protocol != OrchardProtocolVersion.v3) {
        throw ZcashErrors.orchardPcztFailed(
          "verifyFlagsForVersion",
          reason: "The Ironwood pool exists only from NU6.3 (protocol v3).",
        );
      }
      return;
    }
    if (!flags.crossAddressEnabled) {
      throw ZcashErrors.orchardPcztFailed(
        "verifyFlagsForVersion",
        reason: "Unrepresentable flags for pre-NU6.3 version.",
      );
    }
  }

  OrchardBundle? _toTxData({
    bool extract = true,
    required OrchardBundleVersion version,
  }) {
    if (this.actions.isEmpty) return null;
    final actions =
        this.actions.map((e) {
          final authorization = e.spend.spendAuthSig;
          if (extract && authorization == null) {
            throw ZcashErrors.orchardPcztFailed(
              "extract",
              reason: "Missing spend auth signature.",
            );
          }
          return OrchardAction(
            nf: e.spend.nullifier,
            rk: e.spend.rk,
            cmx: e.output.cmx,
            encryptedNote: e.output.encryptedNote,
            cvNet: e.cvNet,
            authorization: authorization,
          );
        }).toList();

    return OrchardBundle(
      actions: actions,
      flags: flags,
      balance: valueSum,
      anchor: anchor,
      authorization: null,
      bundleVersion: version,
    );
  }

  List<OrchardTransfableCircuit> toCircuits({
    required ZcashCryptoContext context,
    required OrchardProtocolVersion version,
  }) {
    return actions.map((e) {
      // Notes are rebuilt with the pool's version
      // (orchard pool v2 even under V3 circuits, ironwood pool v3) —
      // never the protocol version. Rebuilding with the wrong version
      // re-derives commitments/nullifiers and breaks proofs and the
      // spend/output linkage check below.
      final noteVersion = bundleVersion.valuePool.noteVersion;
      final fvk = e.spend.getFvk();
      final recipient = e.spend.getRecipient();
      final value = e.spend.getValue();
      final rho = e.spend.getRho();
      final rseed = e.spend.getRseed();
      final note = OrchardNote.build(
        recipient: recipient,
        value: value,
        rseed: rseed,
        rho: rho,
        context: context,
        version: noteVersion,
      );
      final witness = e.spend.getWitness();
      final spendInfo = OrchardSpendInfo(
        fvk: fvk,
        note: note,
        merklePath: witness,
      );
      final outRecipient = e.output.getRecipient();
      final outputValue = e.output.getValue();
      final outputRseed = e.output.getRseed();
      final alpha = e.spend.getAlpha();
      final outputNote = OrchardNote.build(
        recipient: outRecipient,
        value: outputValue,
        rseed: outputRseed,
        context: context,
        rho: OrchardRho(e.spend.nullifier.inner),
        version: noteVersion,
      );
      final rcv = e.getRcv();
      return OrchardTransfableCircuit.fromActionContext(
        spend: spendInfo,
        outputNote: outputNote,
        alpha: alpha,
        rcv: rcv,
        context: context,
      );
    }).toList();
  }

  List<OrchardCircuitInstance> toInstances(OrchardProtocolVersion version) =>
      actions
          .map(
            (e) => OrchardCircuitInstance(
              anchor: anchor,
              valueCommitment: e.cvNet,
              nullifier: e.spend.nullifier,
              rk: e.spend.rk,
              cmx: e.output.cmx,
              enableSpend: flags.spendsEnabled,
              enableOutput: flags.outputsEnabled,
              version: version,
              disableCrossAddress: !flags.crossAddressEnabled,
            ),
          )
          .toList();
  RedPallasBindingPrivateKey _verifyAndGentBsk({bool verifyBsk = true}) {
    final rcvs =
        actions.map((e) {
          return e.getRcv();
        }).toList();

    final bsk =
        rcvs.fold(OrchardValueCommitTrapdoor.zero(), (p, c) => p + c).toBsk();
    final bvk =
        (OrchardValueCommitment.from(actions.map((e) => e.cvNet).toList()) -
                OrchardValueCommitment.derive(
                  value: valueSum,
                  rcv: OrchardValueCommitTrapdoor.zero(),
                ))
            .toBvk();
    if (verifyBsk && bsk.publicKey != bvk) {
      throw ZcashErrors.orchardPcztFailed(
        "finalize",
        reason: "Value commit mismatch.",
      );
    }
    setBsk(bsk);
    return bsk;
  }

  FutureOr<void> finalize({
    required List<int> sighash,
    required ZcashCryptoContext context,
    bool verifyBsk = true,
  }) async {
    _verifyAndGentBsk(verifyBsk: verifyBsk);
    for (final action in actions) {
      final bsk = action.spend.dummySk;
      if (bsk == null) continue;
      final ask = RedPallasSpendPrivateKey.fromSpendingKey(bsk);
      await action.sign(sighash: sighash, ask: ask, context: context);
    }
  }

  Future<void> createProof({
    required ZcashCryptoContext context,
    required OrchardProtocolVersion version,
  }) async {
    final circuits = toCircuits(context: context, version: version);
    final instances = toInstances(version);
    final args =
        circuits.indexed
            .map(
              (e) =>
                  OrchardProofInputs(circuit: e.$2, instance: instances[e.$1]),
            )
            .toList();
    if (args.isEmpty) return;
    final proof = await context.createOrchardProof(
      args,
      version: version,
      disableCrossAddress: !flags.crossAddressEnabled,
    );
    setZkProof(proof);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "actions": actions.map((e) => e.toSerializeJson()).toList(),
      "flags": flags.toSerializeJsonForVersion(bundleVersion),
      "anchor": anchor.toSerializeJson(),
      "zkproof": zkproof?.toSerializeJson(),
      "value_sum": valueSum.toSerializeJson(),
      "bsk": bsk?.toBytes(),
    };
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  OrchardPcztBundle? merge({
    required OrchardPcztBundle other,
    required PcztGlobal global,
    required PcztGlobal otherGlobal,
  }) {
    if (flags != other.flags ||
        bundleVersion.valuePool != other.bundleVersion.valuePool ||
        bundleVersion.protocolVersion != other.bundleVersion.protocolVersion ||
        anchor != other.anchor ||
        !PcztUtils.canMerge(this.zkproof, other.zkproof)) {
      return null;
    }
    List<OrchardPcztAction> actions = this.actions;
    ZAmount valueSum = this.valueSum;
    switch ((bsk, other.bsk)) {
      case (RedPallasBindingPrivateKey a, RedPallasBindingPrivateKey b)
          when a != b:
        return null;
      case (null, RedPallasBindingPrivateKey _):
      case (RedPallasBindingPrivateKey _, null):
        if (actions.length != other.actions.length ||
            valueSum != other.valueSum) {
          return null;
        }
        break;
      default:
        if ((!global.shieldedModifiable() &&
                actions.length < other.actions.length) ||
            (!otherGlobal.shieldedModifiable() &&
                other.actions.length < actions.length)) {
          return null;
        }
        if (actions.length < other.actions.length) {
          actions = [...actions, ...other.actions.sublist(actions.length)];
          valueSum = other.valueSum;
        }
        break;
    }
    List<OrchardPcztAction> mergedActions = [];
    for (final i in actions.indexed) {
      final merge = i.$2.merge(other.actions[i.$1]);
      if (merge == null) return null;
      mergedActions.add(merge);
    }
    final zkproof = this.zkproof ?? other.zkproof;
    return OrchardPcztBundle(
      actions: mergedActions,
      flags: flags,
      valueSum: valueSum,
      anchor: anchor,
      bsk: bsk,
      zkproof: zkproof,
      bundleVersion: bundleVersion,
    );
  }
}

class OrchardExtractedBundle implements ExtractedBundle<OrchardBundle> {
  @override
  final OrchardBundle bundle;
  final OrchardProof proof;
  final RedPallasBindingPrivateKey bindingSigningKey;
  const OrchardExtractedBundle({
    required this.bundle,
    required this.proof,
    required this.bindingSigningKey,
  });
  OrchardBundle _buildBundle(ReddsaSignature authorization) {
    return OrchardBundle(
      actions: bundle.actions,
      flags: bundle.flags,
      balance: bundle.balance,
      anchor: bundle.anchor,
      bundleVersion: bundle.bundleVersion,
      authorization: OrchardBundleAuthorization(
        proof: proof,
        bindingSignature: authorization,
      ),
    );
  }

  Future<OrchardBundle> buildBindingAutorization({
    required List<int> sighash,
    required ZcashCryptoContext context,
    bool verifyBindingSignature = true,
  }) async {
    for (final i in bundle.actions) {
      final signature = i.authorization;
      if (signature == null) {
        throw ZcashErrors.orchardPcztFailed(
          "buildBindingAutorization",
          reason: "Missing action autorization.",
        );
      }
      if (verifyBindingSignature) {
        if (!await context.verifyRedPallasSignature(
          vk: i.rk,
          signature: signature,
          message: sighash,
        )) {
          throw ZcashErrors.orchardPcztFailed(
            "buildBindingAutorization",
            reason: "Binding signature verification failed.",
          );
        }
      }
    }
    final authorization = await context.signRedPallas(
      bindingSigningKey,
      sighash,
    );
    return _buildBundle(authorization);
  }

  @override
  ZAmount get valueSum => bundle.balance;
}
