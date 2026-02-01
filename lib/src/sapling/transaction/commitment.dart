import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/pedersen_hash/pedersen_hash.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/sapling/utils/utils.dart';
import 'package:zcash_dart/src/value/value.dart';

abstract class SaplingTrapdoor with Equality {
  JubJubNativeFr get value;
  const SaplingTrapdoor();

  SaplingTrapdoorSum operator +(SaplingTrapdoor other) {
    return SaplingTrapdoorSum(value + other.value);
  }

  SaplingTrapdoorSum operator -(SaplingTrapdoor other) {
    return SaplingTrapdoorSum(value - other.value);
  }

  @override
  List<dynamic> get variables => [value];
}

class SaplingTrapdoorSum extends SaplingTrapdoor {
  @override
  final JubJubNativeFr value;
  const SaplingTrapdoorSum(this.value);

  factory SaplingTrapdoorSum.zero() =>
      SaplingTrapdoorSum(JubJubNativeFr.zero());
  SaplingBindingAuthorizingKey toBsk() =>
      SaplingBindingAuthorizingKey.fromBytes(value.toBytes());
}

class SaplingValueCommitTrapdoor extends SaplingTrapdoor
    with LayoutSerializable {
  @override
  final JubJubNativeFr value;
  const SaplingValueCommitTrapdoor(this.value);

  factory SaplingValueCommitTrapdoor.fromBytes(List<int> bytes) {
    return SaplingValueCommitTrapdoor(JubJubNativeFr.fromBytes(bytes));
  }
  factory SaplingValueCommitTrapdoor.deserializeJson(
      Map<String, dynamic> json) {
    return SaplingValueCommitTrapdoor.fromBytes(json.valueAsBytes("inner"));
  }
  factory SaplingValueCommitTrapdoor.random() =>
      SaplingValueCommitTrapdoor(JubJubNativeFr.random());

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
    return {"inner": value.toBytes()};
  }

  List<int> toBytes() => value.toBytes();
}

abstract class SaplingBaseValueCommitment with Equality {
  JubJubNativePoint get inner;
  const SaplingBaseValueCommitment();

  SaplingCommitmentSum operator +(SaplingBaseValueCommitment other) {
    return SaplingCommitmentSum(inner + other.inner);
  }

  SaplingCommitmentSum operator -(SaplingBaseValueCommitment other) {
    return SaplingCommitmentSum(inner - other.inner);
  }
}

class SaplingValueCommitment extends SaplingBaseValueCommitment
    with LayoutSerializable {
  @override
  final JubJubNativePoint inner;
  const SaplingValueCommitment(this.inner);
  factory SaplingValueCommitment.deserializeJson(Map<String, dynamic> json) {
    return SaplingValueCommitment(
        JubJubNativePoint.fromBytes(json.valueAsBytes("inner")));
  }
  factory SaplingValueCommitment.fromBytes(List<int> bytes) {
    final point = JubJubNativePoint.fromBytes(bytes);
    if (point.isSmallOrder()) {
      throw SaplingException.operationFailed("SaplingValueCommitment",
          reason: "Invalid value commitment point encoding bytes.");
    }
    return SaplingValueCommitment(point);
  }
  factory SaplingValueCommitment.derive(
      {required ZAmount value, required SaplingValueCommitTrapdoor rcv}) {
    final cv = (SaplingUtils.valueCommitmentValueGeneratorNative *
            JubJubNativeFr(value.value)) +
        (SaplingUtils.valueCommitmentRandomnessGeneratorNative * rcv.value);
    return SaplingValueCommitment(cv);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  @override
  List<dynamic> get variables => [inner];

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": toBytes()};
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  List<int> toBytes() => inner.toBytes();
}

class SaplingCommitmentSum extends SaplingBaseValueCommitment {
  @override
  final JubJubNativePoint inner;
  const SaplingCommitmentSum(this.inner);

  factory SaplingCommitmentSum.zero() =>
      SaplingCommitmentSum(JubJubNativePoint.identity());

  SaplingBindingVerificationKey toBvk(ZAmount valueBalance) {
    final vBigint = valueBalance.toI64();
    JubJubNativeFr v = JubJubNativeFr(vBigint.abs());
    if (vBigint.isNegative) {
      v = -v;
    }
    final bvk = inner - SaplingUtils.valueCommitmentValueGeneratorNative * v;
    return SaplingBindingVerificationKey.fromBytes(bvk.toBytes());
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingNoteCommitTrapdoor with Equality {
  final JubJubNativeFr inner;
  const SaplingNoteCommitTrapdoor(this.inner);

  @override
  List<dynamic> get variables => [inner];

  List<int> toBytes() => inner.toBytes();
}

class SaplingNoteCommitment with Equality {
  final JubJubNativePoint inner;
  const SaplingNoteCommitment(this.inner);
  factory SaplingNoteCommitment.fromBytes(List<int> bytes) {
    return SaplingNoteCommitment(JubJubNativePoint.fromBytes(bytes));
  }

  static JubJubNativePoint _derive({
    required List<int> gD,
    required List<int> pkD,
    required ZAmount v,
    required SaplingNoteCommitTrapdoor rcm,
    required ZCashCryptoContext context,
  }) {
    return SaplingUtils.windowedPedersenCommitNative(
        personalization: PersonalizationNoteCommitment(),
        context: context,
        s: [
          ...v.toBits(),
          ...BytesUtils.bytesToBits(gD.exc(
              length: 32,
              operation: "SaplingNoteCommitment",
              reason: "Invalid gd bytes length.")),
          ...BytesUtils.bytesToBits(pkD.exc(
            length: 32,
            operation: "SaplingNoteCommitment",
            reason: "Invalid pkD bytes length.",
          )),
        ],
        r: rcm.inner);
  }

  factory SaplingNoteCommitment.deriv({
    required List<int> gD,
    required List<int> pkD,
    required ZAmount v,
    required SaplingNoteCommitTrapdoor rcm,
    required ZCashCryptoContext context,
  }) {
    final result = _derive(gD: gD, pkD: pkD, v: v, rcm: rcm, context: context);
    return SaplingNoteCommitment(result);
  }

  List<int> toBytes() {
    return inner.toBytes();
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingExtractedNoteCommitment with Equality, LayoutSerializable {
  final JubJubNativeFq inner;
  const SaplingExtractedNoteCommitment(this.inner);
  factory SaplingExtractedNoteCommitment.fromBytes(List<int> bytes) {
    return SaplingExtractedNoteCommitment(JubJubNativeFq.fromBytes(bytes));
  }

  factory SaplingExtractedNoteCommitment.deserializeJson(
      Map<String, dynamic> json) {
    return SaplingExtractedNoteCommitment.fromBytes(json.valueAsBytes("inner"));
  }
  factory SaplingExtractedNoteCommitment.fromNoteCommitment(
      SaplingNoteCommitment com) {
    return SaplingExtractedNoteCommitment(com.inner.toAffine().u);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([LayoutConst.fixedBlob32(property: "inner")],
        property: property);
  }

  List<int> toBytes() {
    return inner.toBytes();
  }

  @override
  List<dynamic> get variables => [inner];

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": toBytes()};
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}

enum SaplingRSeedType {
  beforeZip212(0),
  afterZip212(1);

  final int value;
  const SaplingRSeedType(this.value);
  static SaplingRSeedType fromValue(int? value) =>
      values.firstWhere((e) => e.value == value,
          orElse: () => throw ItemNotFoundException(value: value));
}

sealed class SaplingRSeed with Equality, LayoutSerializable {
  final SaplingRSeedType type;
  const SaplingRSeed(this.type);
  SaplingNoteCommitTrapdoor rcm();
  JubJubNativeFr? deriveEsk();
  List<int> toBytes();

  factory SaplingRSeed.deserializeJson(Map<String, dynamic> json) {
    final type = SaplingRSeedType.fromValue(json.valueAsInt("type"));
    final List<int> rseed = json.valueAsBytes("rseed");
    return switch (type) {
      SaplingRSeedType.afterZip212 => SaplingRSeedAfterZip212(rseed),
      SaplingRSeedType.beforeZip212 => SaplingRSeedBeforeZip212.fromBytes(rseed)
    };
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.u8(property: "type"),
      LayoutConst.fixedBlob32(property: "rseed"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"type": type, "rseed": toBytes()};
  }
}

class SaplingRSeedBeforeZip212 extends SaplingRSeed {
  final JubJubNativeFr inner;
  const SaplingRSeedBeforeZip212(this.inner)
      : super(SaplingRSeedType.beforeZip212);
  factory SaplingRSeedBeforeZip212.fromBytes(List<int> bytes) {
    return SaplingRSeedBeforeZip212(JubJubNativeFr.fromBytes(bytes));
  }

  @override
  SaplingNoteCommitTrapdoor rcm() {
    return SaplingNoteCommitTrapdoor(inner);
  }

  @override
  JubJubNativeFr? deriveEsk() {
    return null;
  }

  @override
  List<int> toBytes() {
    return inner.toBytes();
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingRSeedAfterZip212 extends SaplingRSeed {
  final List<int> inner;
  SaplingRSeedAfterZip212(List<int> bytes)
      : inner = bytes.exc(
            length: 32,
            operation: "SaplingRSeedAfterZip212",
            reason: "Invalid rseed bytes length."),
        super(SaplingRSeedType.afterZip212);
  factory SaplingRSeedAfterZip212.random() =>
      SaplingRSeedAfterZip212(QuickCrypto.generateRandom());
  @override
  SaplingNoteCommitTrapdoor rcm() {
    return SaplingNoteCommitTrapdoor(
        JubJubNativeFr.fromBytes64(PrfExpand.saplingRcm.apply(inner)));
  }

  @override
  JubJubNativeFr deriveEsk() {
    return JubJubNativeFr.fromBytes64(PrfExpand.saplingEsk.apply(inner));
  }

  @override
  List<int> toBytes() {
    return inner.clone();
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingNullifier extends Nullifier<List<int>> {
  SaplingNullifier(List<int> bytes)
      : super(bytes.exc(
            length: 32,
            operation: "SaplingNullifier",
            reason: "Invalid sapling nullifier bytes length."));
  factory SaplingNullifier.deserializeJson(Map<String, dynamic> json) {
    return SaplingNullifier(json.valueAsBytes("inner"));
  }

  @override
  List<int> toBytes() => inner.clone();
}
