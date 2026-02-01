import 'dart:async';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/orchard/pczt/exception.dart';
import 'package:zcash_dart/src/orchard/builder/builder.dart';
import 'package:zcash_dart/src/pczt/types/global.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/pczt/pczt/utils.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/zk_proof/halo2/halo2.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/prover.dart';

class OrchardPcztSpend with LayoutSerializable {
  final OrchardNullifier nullifier;
  final OrchardSpendVerificationKey rk;
  final OrchardAddress? recipient;
  final ZAmount? value;
  final OrchardRho? rho;
  final OrchardNoteRandomSeed? rseed;
  final OrchardFullViewingKey? fvk;
  final OrchardMerklePath? witness;
  final VestaNativeFq? alpha;
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
      rk: OrchardSpendVerificationKey.deserializeJson(
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
      alpha: json.valueTo<VestaNativeFq?, List<int>>(
        key: "alpha",
        parse: (v) => VestaNativeFq.fromBytes(v),
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
      OrchardSpendVerificationKey.layout(property: "rk"),
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
      LayoutConst.bscMap<String, List<int>>(
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
    OrchardSpendVerificationKey? rk,
    ReddsaSignature? spendAuthSig,
    OrchardAddress? recipient,
    ZAmount? value,
    OrchardRho? rho,
    OrchardNoteRandomSeed? rseed,
    OrchardFullViewingKey? fvk,
    OrchardMerklePath? witness,
    VestaNativeFq? alpha,
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
      throw OrchardPcztException.operationFailed(
        "getValue",
        reason: "Missing spend value.",
      );
    }
    return value;
  }

  OrchardAddress getRecipient() {
    final value = recipient;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getRecipient",
        reason: "Missing spend recipient.",
      );
    }
    return value;
  }

  OrchardRho getRho() {
    final value = rho;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getRho",
        reason: "Missing spend rho.",
      );
    }
    return value;
  }

  OrchardNoteRandomSeed getRseed() {
    final value = rseed;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getRseed",
        reason: "Missing spend rseed.",
      );
    }
    return value;
  }

  OrchardFullViewingKey getFvk() {
    final value = fvk;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getFvk",
        reason: "Missing spend full view key.",
      );
    }
    return value;
  }

  OrchardMerklePath getWitness() {
    final value = witness;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getWitness",
        reason: "Missing spend witness.",
      );
    }
    return value;
  }

  VestaNativeFq getAlpha() {
    final value = alpha;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getAlpha",
        reason: "Missing spend alpha.",
      );
    }
    return value;
  }

  OrchardSpendingKey getDummySk() {
    final value = dummySk;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
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
      throw OrchardPcztException.operationFailed(
        "findFvk",
        reason: "Mismatch full viewing key.",
      );
    }
    if (fvk != null) return fvk;
    if (sFvk != null) return sFvk;
    throw OrchardPcztException.operationFailed(
      "findFvk",
      reason: "Missing orchard full viewing key.",
    );
  }

  void verifyNullifier(
    ZCashCryptoContext context, {
    OrchardFullViewingKey? fvk,
  }) {
    fvk = findFvk(fvk: fvk);
    final note = OrchardNote.build(
      recipient: getRecipient(),
      value: getValue(),
      rseed: getRseed(),
      rho: getRho(),
      context: context,
    );
    final addr = fvk.scopeForAddress(address: getRecipient(), context: context);
    if (addr == null) {
      throw OrchardPcztException.operationFailed(
        "verifyNullifier",
        reason: "Invalid full viewing key for note.",
      );
    }
    if (note.nullifier(context: context, fvk: fvk) != nullifier) {
      throw OrchardPcztException.operationFailed(
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
      "alpha": alpha?.toBytes(),
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
      LayoutConst.bscMap<String, List<int>>(
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
      throw OrchardPcztException.operationFailed(
        "getRecipient",
        reason: "Missing output recipient.",
      );
    }
    return value;
  }

  ZAmount getValue() {
    final value = this.value;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getValue",
        reason: "Missing output value.",
      );
    }
    return value;
  }

  OrchardNoteRandomSeed getRseed() {
    final value = rseed;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
        "getRseed",
        reason: "Missing output random seed.",
      );
    }
    return value;
  }

  OrchardNoteRandomSeed getOck() {
    final value = rseed;
    if (value == null) {
      throw OrchardPcztException.operationFailed(
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
      throw OrchardPcztException.operationFailed(
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
      throw OrchardPcztException.operationFailed(
        "verifyCvNet",
        reason: "Invalid value commitment.",
      );
    }
  }

  OrchardSpendAuthorizingKey _validateAndGetRsk({
    required OrchardSpendAuthorizingKey ask,
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
    final rsk = ask.randomize(VestaFq.fromBytes(alpha.toBytes()));
    if (verifyRsk && rsk.toVerificationKey() != rk) {
      throw OrchardPcztException.operationFailed(
        "sign",
        reason: "Invalid spend authorization key.",
      );
    }
    return rsk;
  }

  FutureOr<void> sign({
    required List<int> sighash,
    required OrchardSpendAuthorizingKey ask,
    required ZCashCryptoContext context,
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
    required ZCashCryptoContext context,
    bool verifySignature = true,
  }) async {
    if (verifySignature &&
        !await context.verifyRedPallasSignature(
          vk: spend.rk,
          signature: signature,
          message: sighash,
        )) {
      throw OrchardPcztException.operationFailed(
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

class OrchardPcztBundle
    with LayoutSerializable
    implements
        PcztBundle<OrchardBundle, OrchardExtractedBundle, OrchardPcztBundle> {
  final List<OrchardPcztAction> actions;
  final OrchardBundleFlags flags;
  @override
  final ZAmount valueSum;
  final OrchardAnchor anchor;
  OrchardProof? _zkproof;
  OrchardProof? get zkproof => _zkproof;
  OrchardBindingAuthorizingKey? _bsk;
  OrchardBindingAuthorizingKey? get bsk => _bsk;
  OrchardPcztBundle({
    required List<OrchardPcztAction> actions,
    required this.flags,
    required this.valueSum,
    required this.anchor,
    OrchardProof? zkproof,
    OrchardBindingAuthorizingKey? bsk,
  }) : actions = actions.immutable,
       _zkproof = zkproof,
       _bsk = bsk;
  factory OrchardPcztBundle.deserializeJson(Map<String, dynamic> json) {
    return OrchardPcztBundle(
      actions:
          json
              .valueEnsureAsList<Map<String, dynamic>>("actions")
              .map((e) => OrchardPcztAction.deserializeJson(e))
              .toList(),
      flags: OrchardBundleFlags.deserializeJson(json.valueAs("flags")),
      valueSum: ZAmount.deserializeJson(json.valueAs("value_sum")),
      anchor: OrchardAnchor.deserializeJson(json.valueAs("anchor")),
      zkproof: json.valueTo<OrchardProof?, Map<String, dynamic>>(
        key: "zkproof",
        parse: (v) => OrchardProof.deserializeJson(v),
      ),
      bsk: json.valueTo<OrchardBindingAuthorizingKey?, List<int>>(
        key: "bsk",
        parse: (v) => OrchardBindingAuthorizingKey.fromBytes(v),
      ),
    );
  }

  OrchardPcztBundle? copyWith({
    List<OrchardPcztAction>? actions,
    OrchardBundleFlags? flags,
    ZAmount? valueSum,
    OrchardAnchor? anchor,
    OrchardProof? zkproof,
    OrchardBindingAuthorizingKey? bsk,
  }) {
    return OrchardPcztBundle(
      actions: actions ?? this.actions,
      flags: flags ?? this.flags,
      valueSum: valueSum ?? this.valueSum,
      anchor: anchor ?? this.anchor,
      bsk: bsk ?? this.bsk,
      zkproof: zkproof ?? this.zkproof,
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
  );

  OrchardBindingAuthorizingKey getBsk() {
    final bsk = this.bsk;
    if (bsk == null) {
      throw OrchardPcztException.operationFailed(
        "getBsk",
        reason: "Missing bundle binding signing key.",
      );
    }
    return bsk;
  }

  OrchardProof getZkproof() {
    final zkproof = this.zkproof;
    if (zkproof == null) {
      throw OrchardPcztException.operationFailed(
        "getZkproof",
        reason: "Missing bundle proof.",
      );
    }
    return zkproof;
  }

  void setBsk(OrchardBindingAuthorizingKey? bsk) {
    _bsk = bsk;
  }

  void setZkProof(OrchardProof? proof) {
    _zkproof = proof;
  }

  @override
  OrchardExtractedBundle? extract() {
    final bundle = _toTxData();
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
  OrchardBundle? extractEffects() => _toTxData(extract: false);

  OrchardBundle? _toTxData({bool extract = true}) {
    if (this.actions.isEmpty) return null;
    final actions =
        this.actions.map((e) {
          final authorization = e.spend.spendAuthSig;
          if (extract && authorization == null) {
            throw OrchardPcztException.operationFailed(
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
    );
  }

  List<OrchardTransfableCircuit> toCircuits(ZCashCryptoContext context) =>
      actions.map((e) {
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

  List<OrchardCircuitInstance> toInstances() =>
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
            ),
          )
          .toList();
  OrchardBindingAuthorizingKey _verifyAndGentBsk({bool verifyBsk = true}) {
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
    if (verifyBsk && bsk.toVerificationKey() != bvk) {
      throw OrchardPcztException.operationFailed(
        "finalize",
        reason: "Value commit mismatch.",
      );
    }
    setBsk(bsk);
    return bsk;
  }

  FutureOr<void> finalize({
    required List<int> sighash,
    required ZCashCryptoContext context,
    bool verifyBsk = true,
  }) async {
    _verifyAndGentBsk(verifyBsk: verifyBsk);
    for (final action in actions) {
      final bsk = action.spend.dummySk;
      if (bsk == null) continue;
      final ask = OrchardSpendAuthorizingKey.fromSpendingKey(bsk);
      await action.sign(sighash: sighash, ask: ask, context: context);
    }
  }

  Future<void> createProof(ZCashCryptoContext context) async {
    final circuits = toCircuits(context);
    final instances = toInstances();
    final proof = await context.createOrchardProof(
      circuits.indexed
          .map(
            (e) => OrchardProofInputs(circuit: e.$2, instance: instances[e.$1]),
          )
          .toList(),
    );
    setZkProof(proof);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "actions": actions.map((e) => e.toSerializeJson()).toList(),
      "flags": flags.toSerializeJson(),
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
        anchor != other.anchor ||
        !PcztUtils.canMerge(this.zkproof, other.zkproof)) {
      return null;
    }
    List<OrchardPcztAction> actions = this.actions;
    ZAmount valueSum = this.valueSum;
    switch ((bsk, other.bsk)) {
      case (OrchardBindingAuthorizingKey a, OrchardBindingAuthorizingKey b)
          when a != b:
        return null;
      case (null, OrchardBindingAuthorizingKey _):
      case (OrchardBindingAuthorizingKey _, null):
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
    );
  }
}

class OrchardExtractedBundle implements ExtractedBundle<OrchardBundle> {
  @override
  final OrchardBundle bundle;
  final OrchardProof proof;
  final OrchardBindingAuthorizingKey bindingSigningKey;
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
      authorization: OrchardBundleAuthorization(
        proof: proof,
        bindingSignature: authorization,
      ),
    );
  }

  Future<OrchardBundle> buildBindingAutorization({
    required List<int> sighash,
    required ZCashCryptoContext context,
    bool verifyBindingSignature = true,
  }) async {
    for (final i in bundle.actions) {
      final signature = i.authorization;
      if (signature == null) {
        throw OrchardPcztException.operationFailed(
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
          throw OrchardPcztException.operationFailed(
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
