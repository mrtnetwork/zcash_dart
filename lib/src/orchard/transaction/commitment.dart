import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/utils/utils.dart';
import 'package:zcash_dart/src/value/value.dart';

class OrchardNullifier extends Nullifier<BuBytes> {
  OrchardNullifier(List<int> bytes)
    : super(
        bytes
            .exc(
              length: 32,
              operation: "OrchardNullifier",
              reason: "Invalid orchard nullifier bytes length.",
            )
            .asImmutableBytes,
      ) {
    // Canonical base-field check (view-only, bytes stay stored).
    PallasFp.fromBytes(inner);
  }

  factory OrchardNullifier.deserializeJson(Map<String, dynamic> json) {
    return OrchardNullifier(json.valueAsBytes("inner"));
  }
  factory OrchardNullifier.random() {
    final scalar = blockchainUtils.api.pallas.scReduce64(
      QuickCrypto.generateRandom(length: 64),
    );
    final pt = blockchainUtils.api.pallas.multBase(scalar);
    final x = PallasPoint.fromBytes(pt).toAffine().x.toBytes();
    return OrchardNullifier(x);
  }

  factory OrchardNullifier.fromBytes(List<int> bytes) =>
      OrchardNullifier(bytes);

  @override
  BuBytes toBytes() => inner.clone();

  @override
  ZcashProtocol get protocol => ZcashProtocol.orchard;
}

class OrchardNoteCommitment with Equality {
  final BuBytes inner;
  OrchardNoteCommitment(List<int> bytes)
    : inner =
          bytes
              .exc(
                length: 32,
                operation: "OrchardNoteCommitment",
                reason: "Invalid note commitment bytes length.",
              )
              .asImmutableBytes {
    // Validate point encoding (view-only).
    PallasPoint.fromBytes(inner);
  }

  OrchardExtractedNoteCommitment toExtractedNoteCommitment() {
    final x = PallasPoint.fromBytes(inner).toAffine().x;
    return OrchardExtractedNoteCommitment(x);
  }

  BuBytes toBytes() {
    return inner.clone();
  }

  @override
  List<dynamic> get variables => [inner];
}

class OrchardExtractedNoteCommitment with Equality, LayoutSerializable {
  final PallasFp inner;
  OrchardExtractedNoteCommitment(this.inner);
  factory OrchardExtractedNoteCommitment.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return OrchardExtractedNoteCommitment.fromBytes(json.valueAsBytes("inner"));
  }
  factory OrchardExtractedNoteCommitment.fromBytes(List<int> bytes) =>
      OrchardExtractedNoteCommitment(PallasFp.fromBytes(bytes));

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": toBytes()};
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  BuBytes toBytes() {
    return inner.toBytes();
  }

  @override
  List<dynamic> get variables => [inner];
}

class OrchardValueCommitTrapdoor with Equality, LayoutSerializable {
  final BuBytes inner;
  OrchardValueCommitTrapdoor(List<int> bytes)
    : inner =
          bytes
              .exc(
                length: 32,
                operation: "OrchardValueCommitTrapdoor",
                reason: "Invalid trapdoor bytes length.",
              )
              .asImmutableBytes {
    VestaFq.fromBytes(inner);
  }

  factory OrchardValueCommitTrapdoor.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return OrchardValueCommitTrapdoor.fromBytes(json.valueAsBytes("inner"));
  }

  factory OrchardValueCommitTrapdoor.zero() =>
      OrchardValueCommitTrapdoor(List.filled(32, 0));
  factory OrchardValueCommitTrapdoor.random() => OrchardValueCommitTrapdoor(
    blockchainUtils.api.pallas.scReduce64(
      QuickCrypto.generateRandom(length: 64),
    ),
  );

  factory OrchardValueCommitTrapdoor.fromBytes(List<int> bytes) {
    return OrchardValueCommitTrapdoor(bytes);
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
    return {"inner": inner.clone()};
  }

  OrchardValueCommitTrapdoor operator +(OrchardValueCommitTrapdoor other) =>
      OrchardValueCommitTrapdoor(
        blockchainUtils.api.pallas.scAdd(inner, other.inner),
      );

  /// Convert to bytes
  BuBytes toBytes() => inner.clone();

  RedPallasBindingPrivateKey toBsk() {
    return RedPallasBindingPrivateKey.fromBytes(toBytes());
  }

  @override
  List<dynamic> get variables => [inner];
}

class OrchardValueCommitment with Equality, LayoutSerializable {
  final BuBytes inner;
  OrchardValueCommitment(List<int> bytes)
    : inner =
          bytes
              .exc(
                length: 32,
                operation: "OrchardValueCommitment",
                reason: "Invalid value commitment bytes length.",
              )
              .asImmutableBytes {
    PallasPoint.fromBytes(inner);
  }

  factory OrchardValueCommitment.fromBytes(List<int> bytes) {
    return OrchardValueCommitment(bytes);
  }
  factory OrchardValueCommitment.deserializeJson(Map<String, dynamic> json) {
    return OrchardValueCommitment.fromBytes(json.valueAsBytes("inner"));
  }

  factory OrchardValueCommitment.derive({
    required ZAmount value,
    required OrchardValueCommitTrapdoor rcv,
  }) {
    final vP = blockchainUtils.api.pallas.hashToCurvePasta(
      domainPrefix: OrchardUtils.valueCommitmentPersonalization,
      message: OrchardUtils.valueCommitmentVBytes,
    );
    final rP = blockchainUtils.api.pallas.hashToCurvePasta(
      domainPrefix: OrchardUtils.valueCommitmentPersonalization,
      message: OrchardUtils.valueCommitmentRBytes,
    );
    final absValue = value.value.abs().asU64;
    BuBytes v = absValue.toLeBytes(length: 32);
    if (value.value.isNegative) {
      v = blockchainUtils.api.pallas.scNeg(v);
    }
    return OrchardValueCommitment(
      blockchainUtils.api.pallas.mulAdd(v, vP, rcv.inner, rP),
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  factory OrchardValueCommitment.identity() =>
      OrchardValueCommitment(blockchainUtils.api.pallas.identity());
  factory OrchardValueCommitment.from(List<OrchardValueCommitment> others) {
    return others.fold(OrchardValueCommitment.identity(), (p, c) => (p + c));
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": toBytes()};
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  BuBytes toBytes() => inner.clone();

  RedPallasBindingPublicKey toBvk() {
    return RedPallasBindingPublicKey.fromBytes(inner);
  }

  OrchardValueCommitment operator +(OrchardValueCommitment other) =>
      OrchardValueCommitment(
        blockchainUtils.api.pallas.add(inner, other.inner),
      );
  OrchardValueCommitment operator -(OrchardValueCommitment other) =>
      OrchardValueCommitment(
        blockchainUtils.api.pallas.sub(inner, other.inner),
      );
  @override
  List<dynamic> get variables => [inner];
}

class OrchardNoteCommitTrapdoor with Equality {
  final BuBytes inner;
  OrchardNoteCommitTrapdoor(List<int> bytes)
    : inner =
          bytes
              .exc(
                length: 32,
                operation: "OrchardNoteCommitTrapdoor",
                reason: "Invalid trapdoor bytes length.",
              )
              .asImmutableBytes {
    VestaFq.fromBytes(inner);
  }

  BuBytes toBytes() => inner.clone();

  @override
  List<dynamic> get variables => [inner];
}
