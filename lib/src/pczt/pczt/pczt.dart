import 'dart:typed_data';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/merkle/merkle.dart';
import 'package:zcash_dart/src/pczt/exception/exception.dart';
import 'package:zcash_dart/src/pczt/pczt/combiner.dart';
import 'package:zcash_dart/src/pczt/pczt/finalizer.dart';
import 'package:zcash_dart/src/pczt/pczt/prover.dart';
import 'package:zcash_dart/src/pczt/pczt/signer.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';
import 'package:zcash_dart/src/orchard/transaction/bundle.dart';
import 'package:zcash_dart/src/orchard/pczt/pczt.dart';
import 'package:zcash_dart/src/pczt/constants/cosntants.dart';
import 'package:zcash_dart/src/pczt/pczt/extractor.dart';
import 'package:zcash_dart/src/pczt/types/global.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/sapling/pczt/pczt.dart';
import 'package:zcash_dart/src/transparent/pczt/pczt.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/value/value.dart';

class Pczt
    with
        LayoutSerializable,
        PcztCombiner,
        PcztExtractor,
        PcztIoFinalizer,
        PcztProver,
        PcztSigner,
        PcztSpendFinalizer
    implements PcztV1 {
  @override
  final PcztGlobal global;
  @override
  final TransparentPcztBundle transparent;
  @override
  final SaplingPcztBundle sapling;
  @override
  final OrchardPcztBundle orchard;
  const Pczt(
      {required this.global,
      required this.transparent,
      required this.sapling,
      required this.orchard});
  factory Pczt.fromHex(String hexBytes) {
    return Pczt.deserialize(BytesUtils.fromHexString(hexBytes));
  }
  factory Pczt.deserialize(List<int> bytes) {
    if (bytes.length < 8 ||
        !BytesUtils.bytesEqual(bytes.sublist(0, 4), PcztConstants.magicBytes)) {
      throw PcztException.failed("deserialize",
          reason: "Invalid Pczt encoding bytes.");
    }
    final version =
        IntUtils.fromBytes(bytes.sublist(4, 8), byteOrder: Endian.little);
    if (version != PcztConstants.pcztVersion) {
      throw PcztException.failed("deserialize",
          reason: "Unsupported pczt version.");
    }
    try {
      final decode = LayoutSerializable.deserialize(
          bytes: bytes.sublist(8), layout: layout());
      return Pczt.deserializeJson(decode);
    } on BlockchainUtilsException catch (e) {
      throw PcztException.failed("deserialize",
          reason: "Invalid Pczt encoding bytes.",
          details: {"error": e.toString()});
    }
  }
  factory Pczt.deserializeJson(Map<String, dynamic> json) {
    return Pczt(
        global: PcztGlobal.deserializeJson(json.valueAs("global")),
        transparent:
            TransparentPcztBundle.deserializeJson(json.valueAs("transparent")),
        sapling: SaplingPcztBundle.deserializeJson(json.valueAs("sapling")),
        orchard: OrchardPcztBundle.deserializeJson(json.valueAs("orchard")));
  }

  factory Pczt.build(
      {required ZCashNetwork network,
      required int locktime,
      required int expiryHeight,
      TransparentPcztBundle? transparent,
      SaplingPcztBundle? sapling,
      OrchardPcztBundle? orchard,
      TxVersionType txVersion = TxVersionType.v5,
      NetworkUpgrade networkUpgrade = NetworkUpgrade.nu6_1}) {
    int txModifiable = 0;
    if (transparent != null &&
        transparent.inputs.any((e) =>
            e.sighashType == BitcoinOpCodeConst.sighashSingle ||
            e.sighashType == BitcoinOpCodeConst.sighashSingleAnyOneCanPay)) {
      txModifiable = PcztConstants.flagHasSighashSingle;
    }
    final config = network.config();

    final global = PcztGlobal(
        txVersion: txVersion.txVesion,
        versionGroupId: txVersion.groupId ?? 0,
        consensusBranchId: networkUpgrade.branchId,
        expiryHeight: expiryHeight,
        coinType: config.coinIdx,
        txModifiable: txModifiable,
        proprietary: {});
    transparent ??= TransparentPcztBundle();
    sapling ??= SaplingPcztBundle(
        spends: [],
        outputs: [],
        valueSum: ZAmount.zero(),
        anchor: SaplingAnchor.emptyTree());
    orchard ??= OrchardPcztBundle(
        actions: [],
        flags: OrchardBundleFlags.enabled,
        valueSum: ZAmount.zero(),
        anchor: OrchardAnchor.emptyTree());
    return Pczt(
      global: global,
      transparent: transparent,
      sapling: sapling,
      orchard: orchard,
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      PcztGlobal.layout(property: "global"),
      TransparentPcztBundle.layout(propery: "transparent"),
      SaplingPcztBundle.layout(property: "sapling"),
      OrchardPcztBundle.layout(property: "orchard")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "global": global.toSerializeJson(),
      "transparent": transparent.toSerializeJson(),
      "sapling": sapling.toSerializeJson(),
      "orchard": orchard.toSerializeJson()
    };
  }

  List<int> encode() {
    return [
      ...PcztConstants.magicBytes,
      ...PcztConstants.pcztVersion.toU32LeBytes(),
      ...toSerializeBytes()
    ];
  }
}
