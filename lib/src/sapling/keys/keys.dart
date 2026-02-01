import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/sapling/utils/utils.dart';

class SaplingProofGenerationKey with LayoutSerializable, Equality {
  final SaplingSpendVerificationKey ak;
  final JubJubNativeFr nsk;

  SaplingNullifierDerivingKey? _nk;
  SaplingProofGenerationKey(
      {required this.ak, required this.nsk, SaplingNullifierDerivingKey? nk})
      : _nk = nk;
  factory SaplingProofGenerationKey.deserializeJson(Map<String, dynamic> json) {
    return SaplingProofGenerationKey(
        ak: SaplingSpendVerificationKey.fromBytes(json.valueAsBytes("ak")),
        nsk: JubJubNativeFr.fromBytes(json.valueAsBytes("nsk")));
  }
  factory SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(
      SaplingExpandedSpendingKey expsk) {
    return SaplingProofGenerationKey(
        ak: expsk.ask.toVerificationKey(),
        nsk: JubJubNativeFr.fromBytes(expsk.nsk.toBytes()),
        nk: expsk.toFvk().vk.nk);
  }

  SaplingViewingKey toViewingKey() {
    return SaplingViewingKey(
        ak: ak,
        nk: _nk ??= SaplingNullifierDerivingKey(
            SaplingUtils.proofGenerationKeyGeneratorNative * nsk));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "ak"),
      LayoutConst.fixedBlob32(property: "nsk")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"ak": ak.toBytes(), "nsk": nsk.toBytes()};
  }

  @override
  List<dynamic> get variables => [ak, nsk];
}
