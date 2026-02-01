import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';
import 'package:zcash_dart/src/transaction/types/bundle.dart';
import 'package:zcash_dart/src/value/value.dart';

class GrothProofBytes with LayoutSerializable, Equality {
  static const int grothProofSize = 48 + 96 + 48;
  final List<int> inner;
  GrothProofBytes(List<int> inner)
      : inner = inner
            .exc(
                length: grothProofSize,
                operation: "GrothProofBytes",
                reason: "Invalid proof bytes length.")
            .asImmutableBytes;
  factory GrothProofBytes.deserializeJson(Map<String, dynamic> json) {
    return GrothProofBytes(json.valueAsBytes("inner"));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct(
        [LayoutConst.fixedBlobN(grothProofSize, property: "inner")],
        property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner};
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingSpendDescription with LayoutSerializable {
  final SaplingValueCommitment cv;
  final SaplingNullifier nullifier;
  final SaplingSpendVerificationKey rk;
  final SaplingAnchor anchor;
  final GrothProofBytes? zkProof;
  final ReddsaSignature? authSig;
  const SaplingSpendDescription(
      {required this.cv,
      required this.anchor,
      required this.nullifier,
      required this.rk,
      this.zkProof,
      this.authSig});
  factory SaplingSpendDescription.deserializeJson(Map<String, dynamic> json) {
    return SaplingSpendDescription(
        cv: SaplingValueCommitment.deserializeJson(json.valueAs("cv")),
        anchor: SaplingAnchor.deserializeJson(json.valueAs("anchor")),
        nullifier: SaplingNullifier.deserializeJson(json.valueAs("nullifier")),
        rk: SaplingSpendVerificationKey.deserializeJson(json.valueAs("rk")),
        authSig: json.valueTo<ReddsaSignature, Map<String, dynamic>>(
            key: "auth_sig", parse: (v) => ReddsaSignature.deserializeJson(v)),
        zkProof: json.valueTo<GrothProofBytes, Map<String, dynamic>>(
            key: "zk_proof", parse: (v) => GrothProofBytes.deserializeJson(v)));
  }
  static Layout<Map<String, dynamic>> layoutV5({String? property}) {
    return LayoutConst.struct([
      SaplingValueCommitment.layout(property: "cv"),
      Nullifier.layout(property: "nullifier"),
      SaplingSpendVerificationKey.layout(property: "rk"),
    ], property: property);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              SaplingValueCommitment.layout(property: property),
          property: "cv"),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              SaplingAnchor.layout(property: property),
          property: "anchor"),
      LazyStructLayoutBuilder(
          layout: (property, params) => Nullifier.layout(property: property),
          property: "nullifier"),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              SaplingSpendVerificationKey.layout(property: property),
          property: "rk"),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              GrothProofBytes.layout(property: property),
          property: "zk_proof"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            if (params.action.isDecode ||
                params.sourceOrResult.hasValue("auth_sig")) {
              return ReddsaSignature.layout(property: property);
            }
            return LayoutConst.none();
          },
          property: "auth_sig"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson(
      {TxVersionType version = TxVersionType.v4, bool withAuthSig = true}) {
    bool isV5 = version == TxVersionType.v5;
    if (!isV5 && (zkProof == null || (withAuthSig && authSig == null))) {
      throw SaplingException.operationFailed("toSerializeJson",
          reason: "Missing spend autorization.");
    }
    return {
      "cv": cv.toSerializeJson(),
      "rk": rk.toSerializeJson(),
      "nullifier": nullifier.toSerializeJson(),
      if (!isV5) ...{
        "zk_proof": zkProof?.toSerializeJson(),
        "auth_sig": withAuthSig ? authSig?.toSerializeJson() : null,
        "anchor": anchor.toSerializeJson(),
      },
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout(
      {TxVersionType version = TxVersionType.v4, String? property}) {
    if (version == TxVersionType.v5) {
      return layoutV5(property: property);
    }
    return layout(property: property);
  }

  @override
  List<int> toSerializeBytes(
      {TxVersionType version = TxVersionType.v4,
      bool withAuthSig = true,
      String? property}) {
    final layout = toLayout(property: property, version: version);
    return layout
        .serialize(toSerializeJson(version: version, withAuthSig: withAuthSig));
  }
}

class SaplingOutputDescription extends SaplingShildOutput
    with LayoutSerializable {
  final SaplingValueCommitment cv;
  final SaplingExtractedNoteCommitment cmu;
  @override
  final EphemeralKeyBytes ephemeralKey;
  @override
  final List<int> encCiphertext;
  final List<int> outCiphertext;
  final GrothProofBytes? zkproof;
  SaplingOutputDescription(
      {required this.cv,
      required this.cmu,
      required this.ephemeralKey,
      required List<int> encCiphertext,
      required List<int> outCiphertext,
      this.zkproof})
      : encCiphertext = encCiphertext
            .exc(
              length: NoteEncryptionConst.encCiphertextSize,
              operation: "SaplingOutputDescription",
              reason: "Invalid enc cipher text bytes length.",
            )
            .asImmutableBytes,
        outCiphertext = outCiphertext
            .exc(
              length: NoteEncryptionConst.outCiphertextSize,
              operation: "SaplingOutputDescription",
              reason: "Invalid out cipher text bytes length.",
            )
            .asImmutableBytes;
  factory SaplingOutputDescription.deserializeJson(Map<String, dynamic> json) {
    return SaplingOutputDescription(
        cv: SaplingValueCommitment.deserializeJson(json.valueAs("cv")),
        cmu:
            SaplingExtractedNoteCommitment.deserializeJson(json.valueAs("cmu")),
        ephemeralKey:
            EphemeralKeyBytes.deserializeJson(json.valueAs("ephemeral_key")),
        encCiphertext: json.valueAs("enc_cipher_text"),
        outCiphertext: json.valueAs("out_cipher_text"),
        zkproof: json.valueTo<GrothProofBytes, Map<String, dynamic>>(
            key: "zk_proof", parse: (v) => GrothProofBytes.deserializeJson(v)));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      SaplingValueCommitment.layout(property: "cv"),
      SaplingExtractedNoteCommitment.layout(property: "cmu"),
      EphemeralKeyBytes.layout(property: "ephemeral_key"),
      LayoutConst.fixedBlobN(NoteEncryptionConst.encCiphertextSize,
          property: "enc_cipher_text"),
      LayoutConst.fixedBlobN(NoteEncryptionConst.outCiphertextSize,
          property: "out_cipher_text"),
      GrothProofBytes.layout(property: "zk_proof")
    ], property: property);
  }

  static Layout<Map<String, dynamic>> layoutV5({String? property}) {
    return LayoutConst.struct([
      SaplingValueCommitment.layout(property: "cv"),
      SaplingExtractedNoteCommitment.layout(property: "cmu"),
      EphemeralKeyBytes.layout(property: "ephemeral_key"),
      LayoutConst.fixedBlobN(NoteEncryptionConst.encCiphertextSize,
          property: "enc_cipher_text"),
      LayoutConst.fixedBlobN(NoteEncryptionConst.outCiphertextSize,
          property: "out_cipher_text"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson(
      {TxVersionType verion = TxVersionType.v4}) {
    final isV5 = verion == TxVersionType.v5;
    if (!isV5 && zkproof == null) {
      throw SaplingException.operationFailed("toSerializeJson",
          reason: "Missing sapling output zkproof.");
    }
    return {
      "cv": cv.toSerializeJson(),
      "cmu": cmu.toSerializeJson(),
      "ephemeral_key": ephemeralKey.toSerializeJson(),
      "enc_cipher_text": encCiphertext,
      "out_cipher_text": outCiphertext,
      if (!isV5) "zk_proof": zkproof?.toSerializeJson()
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout(
      {TxVersionType verion = TxVersionType.v4, String? property}) {
    if (verion == TxVersionType.v5) {
      return layoutV5(property: property);
    }
    return layout(property: property);
  }

  @override
  SaplingExtractedNoteCommitment cmstar() {
    return cmu;
  }

  @override
  List<int> cmstarBytes() {
    return cmu.toBytes();
  }

  @override
  List<int> get encCiphertextCompact =>
      encCiphertext.sublist(0, NoteEncryptionConst.compactNoteSize);
}

class SaplingBundleAuthorization with LayoutSerializable {
  final ReddsaSignature bindingSignature;
  const SaplingBundleAuthorization({required this.bindingSignature});
  factory SaplingBundleAuthorization.deserializeJson(
      Map<String, dynamic> json) {
    return SaplingBundleAuthorization(
        bindingSignature:
            ReddsaSignature.deserializeJson(json.valueAs("binding_sig")));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              ReddsaSignature.layout(property: property),
          property: "binding_sig")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"binding_sig": bindingSignature.toSerializeJson()};
  }
}

class SaplingBundle with LayoutSerializable implements Bundle<SaplingBundle> {
  final List<SaplingSpendDescription> shieldedSpends;
  final List<SaplingOutputDescription> shieldedOutputs;
  final ZAmount valueBalance;
  final SaplingBundleAuthorization? authorization;
  SaplingBundle(
      {required List<SaplingSpendDescription> shieldedSpends,
      required List<SaplingOutputDescription> shieldedOutputs,
      required this.valueBalance,
      this.authorization})
      : shieldedOutputs = shieldedOutputs.immutable,
        shieldedSpends = shieldedSpends.immutable;
  factory SaplingBundle.deserializeJson(Map<String, dynamic> json) {
    bool isV5 = json.hasValue("binding_sig");
    if (isV5) {
      final bindingSig = SaplingBundleAuthorization.deserializeJson(
          json.valueAs("binding_sig"));
      final vOutputProofs = json
          .valueEnsureAsList<Map<String, dynamic>>("v_output_proofs")
          .map(GrothProofBytes.deserializeJson)
          .toList();
      final vSpendProofs = json
          .valueEnsureAsList<Map<String, dynamic>>("v_spend_proofs")
          .map(GrothProofBytes.deserializeJson)
          .toList();
      final spendAuthSignature = json
          .valueEnsureAsList<Map<String, dynamic>>("v_spend_auth_sigs")
          .map(ReddsaSignature.deserializeJson)
          .toList();
      return SaplingBundle(
          shieldedSpends: json
              .valueEnsureAsList<Map<String, dynamic>>("shielded_spends")
              .indexed
              .map((e) => SaplingSpendDescription(
                  cv: SaplingValueCommitment.deserializeJson(
                      e.$2.valueAs("cv")),
                  anchor: SaplingAnchor.deserializeJson(json.valueAs("anchor")),
                  nullifier: SaplingNullifier.deserializeJson(
                      e.$2.valueAs("nullifier")),
                  rk: SaplingSpendVerificationKey.deserializeJson(
                      e.$2.valueAs("rk")),
                  authSig: spendAuthSignature.elementAt(e.$1),
                  zkProof: vSpendProofs.elementAt(e.$1)))
              .toList(),
          shieldedOutputs: json
              .valueEnsureAsList<Map<String, dynamic>>("shielded_outputs")
              .indexed
              .map(
            (e) {
              final json = e.$2;
              return SaplingOutputDescription(
                  cv: SaplingValueCommitment.deserializeJson(
                      json.valueAs("cv")),
                  cmu: SaplingExtractedNoteCommitment.deserializeJson(
                      json.valueAs("cmu")),
                  ephemeralKey: EphemeralKeyBytes.deserializeJson(
                      json.valueAs("ephemeral_key")),
                  encCiphertext: json.valueAs("enc_cipher_text"),
                  outCiphertext: json.valueAs("out_cipher_text"),
                  zkproof: vOutputProofs.elementAt(e.$1));
            },
          ).toList(),
          valueBalance: ZAmount(json.valueAsBigInt("value_balance")),
          authorization: bindingSig);
    }
    return SaplingBundle(
        shieldedSpends: json
            .valueEnsureAsList<Map<String, dynamic>>("shielded_spends")
            .map(SaplingSpendDescription.deserializeJson)
            .toList(),
        shieldedOutputs: json
            .valueEnsureAsList<Map<String, dynamic>>("shielded_outputs")
            .map(SaplingOutputDescription.deserializeJson)
            .toList(),
        valueBalance: ZAmount(json.valueAsBigInt("value_balance")),
        authorization: null);
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.i64(property: property),
          property: "value_balance"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.varintVector(
              SaplingSpendDescription.layout(property: property)),
          property: "shielded_spends"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.varintVector(
              SaplingOutputDescription.layout(property: property)),
          property: "shielded_outputs"),
    ], property: property);
  }

  static Layout<Map<String, dynamic>> layoutV5({String? property}) {
    int spends = 0;
    int outputs = 0;
    bool haveSpends() => spends > 0;
    bool haveOutputs() => outputs > 0;
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder<List<Map<String, dynamic>>, LayoutRepository>(
        layout: (property, params) => LayoutConst.varintVector(
            SaplingSpendDescription.layoutV5(property: property)),
        property: "shielded_spends",
        finalizeDecode: (layoutResult, structResult, repository) {
          spends = layoutResult.length;
          return layoutResult;
        },
        finalizeEncode: (source, structSource, repository) {
          spends = source.length;
        },
      ),
      LazyStructLayoutBuilder<List<Map<String, dynamic>>, LayoutRepository>(
        layout: (property, params) => LayoutConst.varintVector(
            SaplingOutputDescription.layoutV5(property: property)),
        property: "shielded_outputs",
        finalizeEncode: (source, structSource, repository) {
          outputs = source.length;
        },
        finalizeDecode: (layoutResult, structResult, repository) {
          outputs = layoutResult.length;

          return layoutResult;
        },
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          if (haveSpends() || haveOutputs()) {
            return LayoutConst.i64(property: property);
          }
          return LayoutConst.none(property: property);
        },
        property: "value_balance",
        finalizeDecode: (layoutResult, structResult, repository) {
          return layoutResult;
        },
      ),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            if (haveSpends()) {
              return SaplingAnchor.layout(property: property);
            }
            return LayoutConst.none(property: property);
          },
          property: "anchor"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            return LayoutConst.array(GrothProofBytes.layout(), spends,
                property: property);
          },
          property: "v_spend_proofs"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            return LayoutConst.array(ReddsaSignature.layout(), spends,
                property: property);
          },
          property: "v_spend_auth_sigs"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            return LayoutConst.array(GrothProofBytes.layout(), outputs,
                property: property);
          },
          property: "v_output_proofs"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            if (haveSpends() || haveOutputs()) {
              return SaplingBundleAuthorization.layout(property: property);
            }
            return LayoutConst.none(property: property);
          },
          property: "binding_sig"),
    ], property: property);
  }

  SaplingBundle copyWith(
      {List<SaplingSpendDescription>? shieldedSpends,
      final List<SaplingOutputDescription>? shieldedOutputs,
      final ZAmount? valueBalance,
      final SaplingBundleAuthorization? authorization}) {
    return SaplingBundle(
        shieldedSpends: shieldedSpends ?? this.shieldedSpends,
        shieldedOutputs: shieldedOutputs ?? this.shieldedOutputs,
        valueBalance: valueBalance ?? this.valueBalance,
        authorization: authorization ?? this.authorization);
  }

  @override
  Map<String, dynamic> toSerializeJson(
      {TxVersionType version = TxVersionType.v4}) {
    bool isV5 = version == TxVersionType.v5;
    bool haveSpend = shieldedSpends.isNotEmpty;
    bool haveOutput = shieldedOutputs.isNotEmpty;
    if (isV5 &&
        haveSpend &&
        shieldedSpends.any((e) => e.zkProof == null || e.authSig == null)) {
      throw SaplingException.operationFailed("toSerializeJson",
          reason: "Missing sapling spend autorization.");
    }
    if (isV5 && haveOutput && shieldedOutputs.any((e) => e.zkproof == null)) {
      throw SaplingException.operationFailed("toSerializeJson",
          reason: "Missing sapling output zkproof.");
    }
    return {
      "shielded_spends": shieldedSpends
          .map((e) => e.toSerializeJson(version: version))
          .toList(),
      "shielded_outputs": shieldedOutputs
          .map((e) => e.toSerializeJson(verion: version))
          .toList(),
      "value_balance": valueBalance.value,
      if (version == TxVersionType.v5) ...{
        "anchor": shieldedSpends.firstOrNull?.anchor.toSerializeJson(),
        "v_spend_proofs":
            shieldedSpends.map((e) => e.zkProof?.toSerializeJson()).toList(),
        "v_spend_auth_sigs":
            shieldedSpends.map((e) => e.authSig?.toSerializeJson()).toList(),
        "v_output_proofs":
            shieldedOutputs.map((e) => e.zkproof?.toSerializeJson()).toList(),
        "binding_sig": authorization?.toSerializeJson()
      },
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout(
      {TxVersionType version = TxVersionType.v4, String? property}) {
    if (version == TxVersionType.v5) {
      return layoutV5(property: property);
    }
    return layout(property: property);
  }
}
