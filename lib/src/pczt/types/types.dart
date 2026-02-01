import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/pczt/pczt.dart';
import 'package:zcash_dart/src/pczt/types/global.dart';
import 'package:zcash_dart/src/sapling/pczt/pczt.dart';
import 'package:zcash_dart/src/transaction/types/bundle.dart';
import 'package:zcash_dart/src/transparent/pczt/pczt.dart';
import 'package:zcash_dart/src/value/value.dart';

abstract class PcztBundle<
    BUNDLE extends Bundle<BUNDLE>,
    EXT extends ExtractedBundle<BUNDLE>,
    PCZT extends PcztBundle<BUNDLE, EXT, PCZT>> {
  BUNDLE? extractEffects();
  EXT? extract();
  PCZT clone();
  ZAmount get valueSum;
}

abstract class ExtractedBundle<BUNDLE extends Bundle<BUNDLE>> {
  abstract final BUNDLE bundle;
  abstract final ZAmount valueSum;
}

abstract mixin class PcztV1 {
  PcztGlobal get global;
  TransparentPcztBundle get transparent;
  SaplingPcztBundle get sapling;
  OrchardPcztBundle get orchard;
}

class PcztZip32Derivation with LayoutSerializable, Equality {
  final List<int> seedFingerprint;
  final List<Bip32KeyIndex> derivationPath;
  PcztZip32Derivation(
      {required List<int> seedFingerprint,
      required List<Bip32KeyIndex> derivationPath})
      : seedFingerprint = seedFingerprint
            .exc(
                length: 32,
                operation: "PcztZip32Derivation",
                reason: "Invalid seed fingerprint bytes length.")
            .asImmutableBytes,
        derivationPath = derivationPath.immutable;
  factory PcztZip32Derivation.deserializeJson(Map<String, dynamic> json) {
    return PcztZip32Derivation(
        seedFingerprint: json.valueAsBytes("seed_fingerprint"),
        derivationPath: json
            .valueEnsureAsList<int>("derivation_path")
            .map((e) => Bip32KeyIndex(e))
            .toList());
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "seed_fingerprint"),
      LayoutConst.bcsVector(LayoutConst.lebU32(), property: "derivation_path")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "seed_fingerprint": seedFingerprint,
      "derivation_path": derivationPath.map((e) => e.index).toList()
    };
  }

  @override
  List<dynamic> get variables => [seedFingerprint, derivationPath];
}
