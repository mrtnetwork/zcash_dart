import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/utils/utils.dart';
import 'package:zcash_dart/src/value/value.dart';

class OrchardNullifier extends Nullifier<PallasNativeFp> {
  const OrchardNullifier(super.inner);

  factory OrchardNullifier.deserializeJson(Map<String, dynamic> json) {
    return OrchardNullifier.fromBytes(json.valueAsBytes("inner"));
  }
  factory OrchardNullifier.random() =>
      OrchardNullifier(PallasNativePoint.random().x);

  factory OrchardNullifier.fromBytes(List<int> bytes) =>
      OrchardNullifier(PallasNativeFp.fromBytes(bytes));

  @override
  List<int> toBytes() => inner.toBytes();
}

class OrchardNoteCommitment with Equality {
  final PallasNativePoint inner;
  OrchardNoteCommitment(this.inner);

  OrchardExtractedNoteCommitment toExtractedNoteCommitment() {
    return OrchardExtractedNoteCommitment(inner.toAffine().x);
  }

  List<int> toBytes() {
    return inner.toBytes();
  }

  @override
  List<dynamic> get variables => [inner];
}

class OrchardExtractedNoteCommitment with Equality, LayoutSerializable {
  final PallasNativeFp inner;
  OrchardExtractedNoteCommitment(this.inner);
  factory OrchardExtractedNoteCommitment.deserializeJson(
      Map<String, dynamic> json) {
    return OrchardExtractedNoteCommitment.fromBytes(json.valueAsBytes("inner"));
  }
  factory OrchardExtractedNoteCommitment.fromBytes(List<int> bytes) =>
      OrchardExtractedNoteCommitment(PallasNativeFp.fromBytes(bytes));

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

  List<int> toBytes() {
    return inner.toBytes();
  }

  @override
  List<dynamic> get variables => [inner];
}

class OrchardValueCommitTrapdoor with Equality, LayoutSerializable {
  final VestaNativeFq inner;
  const OrchardValueCommitTrapdoor(this.inner);

  factory OrchardValueCommitTrapdoor.deserializeJson(
      Map<String, dynamic> json) {
    return OrchardValueCommitTrapdoor.fromBytes(json.valueAsBytes("inner"));
  }

  factory OrchardValueCommitTrapdoor.zero() =>
      OrchardValueCommitTrapdoor(VestaNativeFq.zero());
  factory OrchardValueCommitTrapdoor.random() =>
      OrchardValueCommitTrapdoor(VestaNativeFq.random());

  factory OrchardValueCommitTrapdoor.fromBytes(List<int> bytes) {
    return OrchardValueCommitTrapdoor(VestaNativeFq.fromBytes(bytes));
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
    return {"inner": inner.toBytes()};
  }

  OrchardValueCommitTrapdoor operator +(OrchardValueCommitTrapdoor other) =>
      OrchardValueCommitTrapdoor(inner + other.inner);

  /// Convert to bytes
  List<int> toBytes() => inner.toBytes();

  OrchardBindingAuthorizingKey toBsk() {
    return OrchardBindingAuthorizingKey.fromBytes(toBytes());
  }

  @override
  List<dynamic> get variables => [inner];
}

class OrchardValueCommitment with Equality, LayoutSerializable {
  final PallasNativePoint inner;
  const OrchardValueCommitment(this.inner);

  factory OrchardValueCommitment.fromBytes(List<int> bytes) {
    return OrchardValueCommitment(PallasNativePoint.fromBytes(bytes));
  }
  factory OrchardValueCommitment.deserializeJson(Map<String, dynamic> json) {
    return OrchardValueCommitment.fromBytes(json.valueAsBytes("inner"));
  }

  factory OrchardValueCommitment.derive(
      {required ZAmount value, required OrchardValueCommitTrapdoor rcv}) {
    final vP = PallasNativePoint.hashToCurve(
        domainPrefix: OrchardUtils.valueCommitmentPersonalization,
        message: OrchardUtils.valueCommitmentVBytes);
    final rP = PallasNativePoint.hashToCurve(
        domainPrefix: OrchardUtils.valueCommitmentPersonalization,
        message: OrchardUtils.valueCommitmentRBytes);
    final absValue = value.value.abs().asU64;
    VestaNativeFq v = VestaNativeFq.nP(absValue);
    if (value.value.isNegative) {
      v = -v;
    }
    return OrchardValueCommitment((vP * v + rP * rcv.inner));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  factory OrchardValueCommitment.identity() =>
      OrchardValueCommitment(PallasNativePoint.identity());
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

  List<int> toBytes() => inner.toBytes();

  OrchardBindingVerificationKey toBvk() {
    return OrchardBindingVerificationKey(inner);
  }

  OrchardValueCommitment operator +(OrchardValueCommitment other) =>
      OrchardValueCommitment((inner + other.inner));
  OrchardValueCommitment operator -(OrchardValueCommitment other) =>
      OrchardValueCommitment((inner - other.inner));
  @override
  List<dynamic> get variables => [inner];
}

class OrchardNoteCommitTrapdoor with Equality {
  final VestaNativeFq inner;
  const OrchardNoteCommitTrapdoor(this.inner);

  @override
  List<dynamic> get variables => [inner];
}
