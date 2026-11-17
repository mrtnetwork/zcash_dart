import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:zcash_dart/src/sapling/utils/utils.dart';

class SaplingProofGenerationKey with LayoutSerializable, Equality {
  final BuBytes _akBytes;
  final BuBytes _nskBytes;
  RedJubJubSpendPublicKey? _ak;

  /// Spend authority, decoded lazily once and cached.
  RedJubJubSpendPublicKey get ak =>
      _ak ??= RedJubJubSpendPublicKey.fromBytes(_akBytes);

  /// Nullifier spend scalar bytes.
  BuBytes get nsk => _nskBytes.cloneBytes();

  SaplingNullifierDerivingKey? _nk;
  SaplingProofGenerationKey({
    required RedJubJubSpendPublicKey ak,
    required List<int> nsk,
    SaplingNullifierDerivingKey? nk,
  }) : _akBytes = BuBytes.from(ak.toBytes()),
       _nskBytes = _checkScalar(nsk),
       _ak = ak,
       _nk = nk;

  static BuBytes _checkScalar(List<int> bytes) {
    final b = bytes.exc(
      length: 32,
      operation: "SaplingProofGenerationKey",
      reason: "Invalid nsk bytes length.",
    );
    if (!blockchainUtils.api.jubjub.scCheck(b)) {
      throw ZcashErrors.saplingFailed(
        "SaplingProofGenerationKey",
        reason: "Invalid nsk scalar encoding bytes.",
      );
    }
    return BuBytes.from(b);
  }

  factory SaplingProofGenerationKey.deserializeJson(Map<String, dynamic> json) {
    // Single validating parse per key; afterwards raw bytes are kept.
    final ak = RedJubJubSpendPublicKey.fromBytes(json.valueAsBytes("ak"));
    final self = SaplingProofGenerationKey(
      ak: ak,
      nsk: json.valueAsBytes("nsk"),
    );
    self._ak = ak;
    return self;
  }
  factory SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(
    SaplingExpandedSpendingKey expsk,
  ) {
    return SaplingProofGenerationKey(
      ak: expsk.ask.publicKey,
      nsk: expsk.nsk.toBytes(),
      nk: expsk.toFvk().vk.nk,
    );
  }

  SaplingViewingKey toViewingKey() {
    return SaplingViewingKey(
      ak: ak,
      nk:
          _nk ??= SaplingNullifierDerivingKey.fromBytes(
            blockchainUtils.api.jubjub.mult(
              _nskBytes,
              SaplingUtils.proofGenerationKeyGeneratorBytes,
            ),
          ),
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "ak"),
      LayoutConst.fixedBlob32(property: "nsk"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"ak": _akBytes.cloneBytes(), "nsk": _nskBytes.cloneBytes()};
  }

  @override
  List<dynamic> get variables => [_akBytes, _nskBytes];
}
