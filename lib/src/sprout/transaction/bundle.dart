import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/transaction/exception/exception.dart';
import 'package:zcash_dart/src/transaction/types/bundle.dart';

enum SproutProofType {
  groth(48 + 96 + 48),
  pHGR(33 + 33 + 65 + 33 + 33 + 33 + 33 + 33);

  final int length;
  const SproutProofType(this.length);
  static SproutProofType fromLength(int? length) {
    return values.firstWhere((e) => e.length == length,
        orElse: () => throw ItemNotFoundException(value: length));
  }
}

abstract class SproutProof with LayoutSerializable {
  final List<int> inner;
  final SproutProofType type;

  SproutProof({required List<int> inner, required this.type})
      : inner = inner
            .exc(
              length: type.length,
              operation: "SproutProof",
              reason: "Invalid proof bytes length.",
            )
            .asImmutableBytes;
  factory SproutProof.deserializeJson(Map<String, dynamic> json) {
    final inner = json.valueAsBytes<List<int>>("inner");
    final type = SproutProofType.fromLength(inner.length);
    return switch (type) {
      SproutProofType.groth => SproutProofGroth(inner: inner),
      SproutProofType.pHGR => SproutProofPHGR(inner: inner)
    };
  }
  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner};
  }
}

class SproutProofGroth extends SproutProof {
  SproutProofGroth({required super.inner}) : super(type: SproutProofType.groth);
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(SproutProofType.groth.length, property: "inner"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}

class SproutProofPHGR extends SproutProof {
  SproutProofPHGR({required super.inner}) : super(type: SproutProofType.pHGR);
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(SproutProofType.pHGR.length, property: "inner"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}

class SproutJsDescription with LayoutSerializable {
  final BigInt vpubOld;
  final BigInt vpubNew;
  final List<int> anchor;
  final List<List<int>> nullifiers;
  final List<List<int>> commitments;
  final List<int> ephemeralKey;
  final List<int> randomSeed;
  final List<List<int>> macs;
  final SproutProof proof;
  final List<List<int>> ciphertexts;
  factory SproutJsDescription.deserializeJson(Map<String, dynamic> json) {
    return SproutJsDescription(
        vpubOld: json.valueAsBigInt("vpub_old"),
        vpubNew: json.valueAsBigInt("vpub_new"),
        proof: SproutProof.deserializeJson(
            json.valueEnsureAsMap<String, dynamic>("proof")),
        anchor: json.valueAsBytes("anchor"),
        nullifiers: json.valueEnsureAsList<List<int>>("nullifiers"),
        commitments: json.valueEnsureAsList<List<int>>("commitments"),
        ephemeralKey: json.valueAs("ephemeral_key"),
        randomSeed: json.valueAs("random_seed"),
        macs: json.valueEnsureAsList<List<int>>("macs"),
        ciphertexts: json.valueEnsureAsList<List<int>>("ciphertexts"));
  }
  SproutJsDescription({
    required this.vpubOld,
    required this.vpubNew,
    required this.proof,
    required List<int> anchor,
    required List<List<int>> nullifiers,
    required List<List<int>> commitments,
    required List<int> ephemeralKey,
    required List<int> randomSeed,
    required List<List<int>> macs,
    required List<List<int>> ciphertexts,
  })  : anchor = anchor
            .exc(
              length: 32,
              operation: "SproutJsDescription",
              reason: "Invalid anchor bytes length.",
            )
            .asImmutableBytes,
        nullifiers = nullifiers
            .map((e) => e
                .exc(
                  length: 32,
                  operation: "SproutJsDescription",
                  reason: "Invalid nullifier bytes length.",
                )
                .asImmutableBytes)
            .toList()
            .exc(
              length: 2,
              operation: "SproutJsDescription",
              reason: "Invalid nullifiers length.",
            )
            .toImutableList,
        commitments = commitments
            .map((e) => e
                .exc(
                  length: 32,
                  operation: "SproutJsDescription",
                  reason: "Invalid commitment bytes length.",
                )
                .asImmutableBytes)
            .toList()
            .exc(
              length: 2,
              operation: "SproutJsDescription",
              reason: "Invalid commitments length.",
            )
            .toImutableList,
        ephemeralKey = ephemeralKey
            .exc(
              length: 32,
              operation: "SproutJsDescription",
              reason: "Invalid ephemeralKey bytes length.",
            )
            .asImmutableBytes,
        randomSeed = randomSeed
            .exc(
              length: 32,
              operation: "SproutJsDescription",
              reason: "Invalid randomSeed bytes length.",
            )
            .asImmutableBytes,
        macs = macs
            .map((e) => e
                .exc(
                  length: 32,
                  operation: "SproutJsDescription",
                  reason: "Invalid mac bytes length.",
                )
                .asImmutableBytes)
            .toList()
            .exc(
              length: 2,
              operation: "SproutJsDescription",
              reason: "Invalid macs length.",
            )
            .toImutableList,
        ciphertexts = ciphertexts
            .map((e) => e
                .exc(
                  length: 601,
                  operation: "SproutJsDescription",
                  reason: "Invalid ciphertext bytes length.",
                )
                .asImmutableBytes)
            .toList()
            .exc(
              length: 2,
              operation: "SproutJsDescription",
              reason: "Invalid ciphertexts length.",
            )
            .toImutableList;

  static Layout<Map<String, dynamic>> layout(
      {String? property, SproutProofType? proof}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.u64(property: property),
          property: "vpub_old"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.u64(property: property),
          property: "vpub_new"),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              LayoutConst.fixedBlob32(property: property),
          property: "anchor"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.array(
              LayoutConst.fixedBlob32(), 2,
              property: property),
          property: "nullifiers"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.array(
              LayoutConst.fixedBlob32(), 2,
              property: property),
          property: "commitments"),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              LayoutConst.fixedBlob32(property: property),
          property: "ephemeral_key"),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              LayoutConst.fixedBlob32(property: property),
          property: "random_seed"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.array(
              LayoutConst.fixedBlob32(), 2,
              property: property),
          property: "macs"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            if (proof == null) {
              if (params.action.isDecode) {
                final proofData = params.sourceOrResult
                    .valueEnsureAsMap<String, dynamic>("proof")
                    .valueAsList<List>("inner");
                proof = SproutProofType.values
                    .firstWhereNullable((e) => e.length == proofData.length);
              }
            }
            return switch (proof) {
              SproutProofType.groth =>
                SproutProofGroth.layout(property: property),
              SproutProofType.pHGR =>
                SproutProofPHGR.layout(property: property),
              _ => throw ZTransactionSerializationError.serializationFailed(
                  "proof")
            };
          },
          property: "proof"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.array(
              LayoutConst.fixedBlobN(601, property: property), 2,
              property: property),
          property: "ciphertexts"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "vpub_old": vpubOld,
      "vpub_new": vpubNew,
      "anchor": anchor,
      "nullifiers": nullifiers,
      "commitments": commitments,
      "ephemeral_key": ephemeralKey,
      "random_seed": randomSeed,
      "macs": macs,
      "proof": proof.toSerializeJson(),
      "ciphertexts": ciphertexts
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property, proof: proof.type);
  }
}

class SproutBundle with LayoutSerializable implements Bundle<SproutBundle> {
  final List<SproutJsDescription> joinsplits;
  final List<int> joinsplitPubkey;
  final List<int> joinsplitSig;
  factory SproutBundle.empty() =>
      SproutBundle._(joinsplitPubkey: [], joinsplitSig: [], joinsplits: []);
  const SproutBundle._(
      {this.joinsplitPubkey = const [],
      this.joinsplitSig = const [],
      this.joinsplits = const []});
  SproutBundle({
    required List<SproutJsDescription> joinsplits,
    required List<int> joinsplitPubkey,
    required List<int> joinsplitSig,
  })  : joinsplits = joinsplits.immutable,
        joinsplitPubkey = joinsplitPubkey
            .exc(
              length: 32,
              operation: "SproutBundle",
              reason: "Invalid joinsplitPubkey bytes length.",
            )
            .asImmutableBytes,
        joinsplitSig = joinsplitSig
            .exc(
              length: 64,
              operation: "SproutBundle",
              reason: "Invalid joinsplitSig bytes length.",
            )
            .asImmutableBytes;
  factory SproutBundle.deserializeJson(Map<String, dynamic> json) {
    return SproutBundle(
        joinsplits: json
            .valueEnsureAsList<Map<String, dynamic>>("joinsplits")
            .map(SproutJsDescription.deserializeJson)
            .toList(),
        joinsplitPubkey: json.valueAsBytes("joinsplit_pubkey"),
        joinsplitSig: json.valueAsBytes("joinsplit_sig"));
  }

  static Layout<Map<String, dynamic>> layout(
      {SproutProofType? proof, String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder(
          layout: (property, params) {
            return LayoutConst.varintVector(
                SproutJsDescription.layout(proof: proof),
                property: property);
          },
          property: "joinsplits"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            final joinsplits =
                params.sourceOrResult.valueAsList<List>("joinsplits");
            if (joinsplits.isEmpty) {
              return LayoutConst.none(property: property);
            }
            return LayoutConst.fixedBlob32(property: property);
          },
          property: "joinsplit_pubkey"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            final joinsplits =
                params.sourceOrResult.valueAsList<List>("joinsplits");
            if (joinsplits.isEmpty) {
              return LayoutConst.none(property: property);
            }
            return LayoutConst.fixedBlobN(64, property: property);
          },
          property: "joinsplit_sig")
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "joinsplits": joinsplits.map((e) => e.toSerializeJson()).toList(),
      "joinsplit_pubkey": joinsplitPubkey,
      "joinsplit_sig": joinsplitSig
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}
