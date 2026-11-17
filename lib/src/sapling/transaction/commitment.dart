import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/value/value.dart';

abstract class SaplingTrapdoor with Equality {
  BuBytes get value;
  const SaplingTrapdoor();

  SaplingTrapdoorSum operator +(SaplingTrapdoor other) {
    return SaplingTrapdoorSum(
      blockchainUtils.api.jubjub.scAdd(value, other.value),
    );
  }

  SaplingTrapdoorSum operator -(SaplingTrapdoor other) {
    return SaplingTrapdoorSum(
      blockchainUtils.api.jubjub.scSub(value, other.value),
    );
  }

  @override
  List<dynamic> get variables => [value];
}

class SaplingTrapdoorSum extends SaplingTrapdoor {
  @override
  final BuBytes value;
  const SaplingTrapdoorSum(this.value);

  factory SaplingTrapdoorSum.zero() => SaplingTrapdoorSum(BuBytes.zero(32));
  RedJubJubBindingPrivateKey toBsk() =>
      RedJubJubBindingPrivateKey.fromBytes(value);
}

class SaplingValueCommitTrapdoor extends SaplingTrapdoor
    with LayoutSerializable {
  @override
  final BuBytes value;
  const SaplingValueCommitTrapdoor(this.value);

  static BuBytes _checkScalar(List<int> bytes) {
    final b = bytes.exc(
      length: 32,
      operation: "SaplingValueCommitTrapdoor",
      reason: "Invalid trapdoor bytes length.",
    );
    if (!blockchainUtils.api.jubjub.scCheck(b)) {
      throw ZcashErrors.saplingFailed(
        "SaplingValueCommitTrapdoor",
        reason: "Invalid scalar encoding bytes.",
      );
    }
    return BuBytes.from(b);
  }

  factory SaplingValueCommitTrapdoor.fromBytes(List<int> bytes) {
    return SaplingValueCommitTrapdoor(_checkScalar(bytes));
  }
  factory SaplingValueCommitTrapdoor.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return SaplingValueCommitTrapdoor.fromBytes(json.valueAsBytes("inner"));
  }
  factory SaplingValueCommitTrapdoor.random() => SaplingValueCommitTrapdoor(
    blockchainUtils.api.jubjub.scReduce64(
      QuickCrypto.generateRandom(length: 64),
    ),
  );

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
    return {"inner": value.cloneBytes()};
  }

  BuBytes toBytes() => value.cloneBytes();
}

abstract class SaplingBaseValueCommitment with Equality {
  BuBytes get inner;
  const SaplingBaseValueCommitment();

  SaplingCommitmentSum operator +(SaplingBaseValueCommitment other) {
    return SaplingCommitmentSum(
      blockchainUtils.api.jubjub.add(inner, other.inner),
    );
  }

  SaplingCommitmentSum operator -(SaplingBaseValueCommitment other) {
    return SaplingCommitmentSum(
      blockchainUtils.api.jubjub.sub(inner, other.inner),
    );
  }
}

class SaplingValueCommitment extends SaplingBaseValueCommitment
    with LayoutSerializable {
  @override
  final BuBytes inner;
  const SaplingValueCommitment(this.inner);
  factory SaplingValueCommitment.deserializeJson(Map<String, dynamic> json) {
    return SaplingValueCommitment.fromBytes(json.valueAsBytes("inner"));
  }
  factory SaplingValueCommitment.fromBytes(List<int> bytes) {
    final b = bytes.exc(
      length: 32,
      operation: "SaplingValueCommitment",
      reason: "Invalid value commitment bytes length.",
    );
    final point = JubJubPoint.fromBytes(b);
    if (point.isSmallOrder()) {
      throw ZcashErrors.saplingFailed(
        "SaplingValueCommitment",
        reason: "Invalid value commitment point encoding bytes.",
      );
    }
    return SaplingValueCommitment(BuBytes.from(b));
  }
  factory SaplingValueCommitment.derive({
    required ZAmount value,
    required SaplingValueCommitTrapdoor rcv,
  }) {
    var n = value.value;
    if (n.isNegative) {
      throw ZcashErrors.saplingFailed(
        "SaplingValueCommitment.derive",
        reason: "Negative value.",
      );
    }
    final vBytes = List<int>.filled(32, 0);
    for (var i = 0; i < 8; i++) {
      vBytes[i] = (n & BigInt.from(0xff)).toInt();
      n >>= 8;
    }
    final vG = blockchainUtils.api.jubjub.mult(
      vBytes,
      SaplingUtils.valueCommitmentValueGeneratorBytes,
    );
    final rG = blockchainUtils.api.jubjub.mult(
      rcv.value,
      SaplingUtils.valueCommitmentRandomnessGeneratorBytes,
    );
    return SaplingValueCommitment(blockchainUtils.api.jubjub.add(vG, rG));
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

  BuBytes toBytes() => inner.cloneBytes();
}

class SaplingCommitmentSum extends SaplingBaseValueCommitment {
  @override
  final BuBytes inner;
  const SaplingCommitmentSum(this.inner);

  factory SaplingCommitmentSum.zero() =>
      SaplingCommitmentSum(blockchainUtils.api.jubjub.identity());

  RedJubJubBindingPublicKey toBvk(ZAmount valueBalance) {
    final vBigint = valueBalance.toI64();
    var n = vBigint.abs();
    final vBytes = List<int>.filled(32, 0);
    for (var i = 0; i < 8; i++) {
      vBytes[i] = (n & BigInt.from(0xff)).toInt();
      n >>= 8;
    }
    BuBytes v = BuBytes.from(vBytes);
    if (vBigint.isNegative) {
      v = blockchainUtils.api.jubjub.scNeg(v);
    }
    final vG = blockchainUtils.api.jubjub.mult(
      v,
      SaplingUtils.valueCommitmentValueGeneratorBytes,
    );
    final bvk = blockchainUtils.api.jubjub.sub(inner, vG);
    return RedJubJubBindingPublicKey.fromBytes(bvk);
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingNoteCommitTrapdoor with Equality {
  final BuBytes inner;
  const SaplingNoteCommitTrapdoor(this.inner);

  @override
  List<dynamic> get variables => [inner];

  BuBytes toBytes() => inner.cloneBytes();
}

class SaplingNoteCommitment with Equality {
  final BuBytes inner;
  const SaplingNoteCommitment(this.inner);
  factory SaplingNoteCommitment.fromBytes(List<int> bytes) {
    final b = bytes.exc(
      length: 32,
      operation: "SaplingNoteCommitment",
      reason: "Invalid note commitment bytes length.",
    );
    JubJubPoint.fromBytes(b);
    return SaplingNoteCommitment(BuBytes.from(b));
  }

  static BuBytes _derive({
    required List<int> gD,
    required List<int> pkD,
    required ZAmount v,
    required SaplingNoteCommitTrapdoor rcm,
    required ZcashCryptoContext context,
  }) {
    return SaplingUtils.windowedPedersenCommitBytes(
      personalization: PersonalizationNoteCommitment(),
      context: context,
      s: [
        ...v.toBits(),
        ...BytesUtils.bytesToBits(
          gD.exc(
            length: 32,
            operation: "SaplingNoteCommitment",
            reason: "Invalid gd bytes length.",
          ),
        ),
        ...BytesUtils.bytesToBits(
          pkD.exc(
            length: 32,
            operation: "SaplingNoteCommitment",
            reason: "Invalid pkD bytes length.",
          ),
        ),
      ],
      r32: rcm.inner,
    );
  }

  factory SaplingNoteCommitment.deriv({
    required List<int> gD,
    required List<int> pkD,
    required ZAmount v,
    required SaplingNoteCommitTrapdoor rcm,
    required ZcashCryptoContext context,
  }) {
    final result = _derive(gD: gD, pkD: pkD, v: v, rcm: rcm, context: context);
    return SaplingNoteCommitment(result);
  }

  BuBytes toBytes() {
    return inner.cloneBytes();
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingExtractedNoteCommitment with Equality, LayoutSerializable {
  final JubJubFq inner;
  const SaplingExtractedNoteCommitment(this.inner);
  factory SaplingExtractedNoteCommitment.fromBytes(List<int> bytes) {
    return SaplingExtractedNoteCommitment(JubJubFq.fromBytes(bytes));
  }

  factory SaplingExtractedNoteCommitment.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return SaplingExtractedNoteCommitment.fromBytes(json.valueAsBytes("inner"));
  }
  factory SaplingExtractedNoteCommitment.fromNoteCommitment(
    SaplingNoteCommitment com,
  ) {
    return SaplingExtractedNoteCommitment(
      JubJubPoint.fromBytes(com.inner).toAffine().u,
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  BuBytes toBytes() {
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
  static SaplingRSeedType fromValue(int? value) => values.firstWhere(
    (e) => e.value == value,
    orElse:
        () =>
            throw BuError(
              DefaultErrorType.notFound,
              "No matching item found for the given value. $value",
            ),
  );
}

sealed class SaplingRSeed with Equality, LayoutSerializable {
  final SaplingRSeedType type;
  const SaplingRSeed(this.type);
  SaplingNoteCommitTrapdoor rcm();
  BuBytes? deriveEsk();
  BuBytes toBytes();

  factory SaplingRSeed.deserializeJson(Map<String, dynamic> json) {
    final type = SaplingRSeedType.fromValue(json.valueAsInt("type"));
    final List<int> rseed = json.valueAsBytes("rseed");
    return switch (type) {
      SaplingRSeedType.afterZip212 => SaplingRSeedAfterZip212(rseed),
      SaplingRSeedType.beforeZip212 => SaplingRSeedBeforeZip212.fromBytes(
        rseed,
      ),
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
    return {"type": type.value, "rseed": toBytes()};
  }
}

class SaplingRSeedBeforeZip212 extends SaplingRSeed {
  final BuBytes inner;
  const SaplingRSeedBeforeZip212(this.inner)
    : super(SaplingRSeedType.beforeZip212);
  factory SaplingRSeedBeforeZip212.fromBytes(List<int> bytes) {
    final b = bytes.exc(
      length: 32,
      operation: "SaplingRSeedBeforeZip212",
      reason: "Invalid rseed bytes length.",
    );
    if (!blockchainUtils.api.jubjub.scCheck(b)) {
      throw ZcashErrors.saplingFailed(
        "SaplingRSeedBeforeZip212",
        reason: "Invalid scalar encoding bytes.",
      );
    }
    return SaplingRSeedBeforeZip212(BuBytes.from(b));
  }

  @override
  SaplingNoteCommitTrapdoor rcm() {
    return SaplingNoteCommitTrapdoor(inner);
  }

  @override
  BuBytes? deriveEsk() {
    return null;
  }

  @override
  BuBytes toBytes() {
    return inner.cloneBytes();
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingRSeedAfterZip212 extends SaplingRSeed {
  final BuBytes inner;
  SaplingRSeedAfterZip212(List<int> bytes)
    : inner =
          bytes
              .exc(
                length: 32,
                operation: "SaplingRSeedAfterZip212",
                reason: "Invalid rseed bytes length.",
              )
              .asImmutableBytes,
      super(SaplingRSeedType.afterZip212);
  factory SaplingRSeedAfterZip212.random() =>
      SaplingRSeedAfterZip212(QuickCrypto.generateRandom());
  @override
  SaplingNoteCommitTrapdoor rcm() {
    return SaplingNoteCommitTrapdoor(
      blockchainUtils.api.jubjub.scReduce64(PrfExpand.saplingRcm.apply(inner)),
    );
  }

  @override
  BuBytes deriveEsk() {
    return blockchainUtils.api.jubjub.scReduce64(
      PrfExpand.saplingEsk.apply(inner),
    );
  }

  @override
  BuBytes toBytes() {
    return inner.clone();
  }

  @override
  List<dynamic> get variables => [inner];
}

class SaplingNullifier extends Nullifier<BuBytes> {
  SaplingNullifier(List<int> bytes)
    : super(
        bytes
            .exc(
              length: 32,
              operation: "SaplingNullifier",
              reason: "Invalid sapling nullifier bytes length.",
            )
            .asImmutableBytes,
      );
  factory SaplingNullifier.deserializeJson(Map<String, dynamic> json) {
    return SaplingNullifier(json.valueAsBytes("inner"));
  }

  @override
  BuBytes toBytes() => inner.clone();
  @override
  ZcashProtocol get protocol => ZcashProtocol.sapling;
}
