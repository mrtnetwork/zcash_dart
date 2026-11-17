import 'dart:typed_data';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/merkle/merkle.dart';
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

  /// The Ironwood PCZT bundle (NU6.3 second Orchard-family slot).
  /// Null means absent. Serialized as a trailing field: when null the
  /// encoding is byte-identical to the legacy 4-field layout.
  @override
  final OrchardPcztBundle? ironwood;
  const Pczt({
    required this.global,
    required this.transparent,
    required this.sapling,
    required this.orchard,
    this.ironwood,
  });
  factory Pczt.fromHex(String hexBytes) {
    return Pczt.deserialize(BytesUtils.fromHexString(hexBytes));
  }
  factory Pczt.deserialize(List<int> bytes) {
    if (bytes.length < 8 ||
        !BytesUtils.bytesEqual(bytes.sublist(0, 4), PcztConstants.magicBytes)) {
      throw ZcashErrors.pcztFailed(
        "deserialize",
        reason: "Invalid Pczt encoding bytes.",
      );
    }
    final version = IntUtils.fromBytes(
      bytes.sublist(4, 8),
      byteOrder: Endian.little,
    );
    if (version != PcztConstants.pcztVersion) {
      throw ZcashErrors.pcztFailed(
        "deserialize",
        reason: "Unsupported pczt version.",
      );
    }
    try {
      // Prefer the layout with the trailing Ironwood bundle; fall back
      // to the legacy 4-field layout for PCZTs written before NU6.3.
      try {
        final decode = LayoutSerializable.deserialize(
          bytes: bytes.sublist(8),
          layout: layout(),
        );
        return Pczt.deserializeJson(decode);
      } on BuError {
        final decode = LayoutSerializable.deserialize(
          bytes: bytes.sublist(8),
          layout: legacyLayout(),
        );
        return Pczt.deserializeJson(decode);
      }
    } on BuError catch (e) {
      throw ZcashErrors.pcztFailed(
        "deserialize",
        reason: "Invalid Pczt encoding bytes.",
        details: {"error": e.toString()},
      );
    }
  }
  factory Pczt.deserializeJson(Map<String, dynamic> json) {
    final global = PcztGlobal.deserializeJson(json.valueAs("global"));
    OrchardBundleVersion orchardVersion = OrchardBundleVersion.orchardV1;
    OrchardBundleVersion ironwoodVersion = OrchardBundleVersion.ironwoodV3;
    try {
      final branch = global.getBranchId();
      orchardVersion =
          OrchardBundleVersion.forBranch(branch) ??
          OrchardBundleVersion.orchardV1;
      ironwoodVersion =
          OrchardBundleVersion.forBranch(branch, isIronwoodPool: true) ??
          OrchardBundleVersion.ironwoodV3;
    } catch (_) {
      // Unknown branch: keep legacy defaults; validate() will fail fast.
    }
    return Pczt(
      global: global,
      transparent: TransparentPcztBundle.deserializeJson(
        json.valueAs("transparent"),
      ),
      sapling: SaplingPcztBundle.deserializeJson(json.valueAs("sapling")),
      orchard: OrchardPcztBundle.deserializeJson(
        json.valueAs("orchard"),
        orchardVersion,
      ),
      ironwood: json.valueTo<OrchardPcztBundle?, Map<String, dynamic>>(
        key: "ironwood",
        parse: (v) => OrchardPcztBundle.deserializeJson(v, ironwoodVersion),
      ),
    );
  }

  factory Pczt.build({
    required ZcashNetwork network,
    required int locktime,
    required int expiryHeight,
    TransparentPcztBundle? transparent,
    SaplingPcztBundle? sapling,
    OrchardPcztBundle? orchard,
    OrchardPcztBundle? ironwood,
    TxVersionType txVersion = TxVersionType.v5,
    ZcashNetworkProtocol networkUpgrade = ZcashNetworkProtocol.nu6_3,
  }) {
    int txModifiable = 0;
    if (transparent != null &&
        transparent.inputs.any(
          (e) =>
              e.sighashType == BitcoinOpCodeConst.sighashSingle ||
              e.sighashType == BitcoinOpCodeConst.sighashSingleAnyOneCanPay,
        )) {
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
      proprietary: {},
    );
    final orchardVersion =
        OrchardBundleVersion.forBranch(networkUpgrade) ??
        OrchardBundleVersion.orchardV1;
    final ironwoodVersion =
        OrchardBundleVersion.forBranch(networkUpgrade, isIronwoodPool: true) ??
        OrchardBundleVersion.ironwoodV3;
    transparent ??= TransparentPcztBundle();
    sapling ??= SaplingPcztBundle(
      spends: [],
      outputs: [],
      valueSum: ZAmount.zero(),
      anchor: SaplingAnchor.emptyTree(),
    );
    orchard ??= OrchardPcztBundle(
      actions: [],
      flags: orchardVersion.defaultFlags(),
      valueSum: ZAmount.zero(),
      anchor: OrchardAnchor.emptyTree(),
      bundleVersion: orchardVersion,
    );
    ironwood = ironwood?.copyWith(bundleVersion: ironwoodVersion);
    // Ensure caller-supplied orchard bundle carries the branch-derived version
    // so flag encoding (0x04 bit) matches official `flag_byte`.
    orchard = orchard.copyWith(bundleVersion: orchardVersion) ?? orchard;
    final pczt = Pczt(
      global: global,
      transparent: transparent,
      sapling: sapling,
      orchard: orchard,
      ironwood: ironwood,
    );
    pczt.validate();
    return pczt;
  }

  /// Validates global/slot/flag consistency, so malformed PCZTs fail
  /// fast instead of producing consensus-invalid transactions.
  ///
  /// Checks: transaction version valid in the consensus branch; V6
  /// required with a non-empty Ironwood bundle and Ironwood forbidden
  /// before NU6.3; per-slot flag encodability under the branch-derived
  /// bundle version; cross-address restriction per action.
  /// Throws [BuError] on the first violation.
  void validate() {
    final version = global.getTxVersion();
    final branch = global.getBranchId();
    if (!version.type.validInBranch(branch)) {
      throw ZcashErrors.pcztFailed(
        "validate",
        reason: "Transaction version not valid in consensus branch.",
        details: {"version": version.type.name, "branch": branch.name},
      );
    }
    final iron = ironwood;
    final hasIronwood = iron != null && iron.actions.isNotEmpty;
    if (hasIronwood) {
      if (version.type != TxVersionType.v6) {
        throw ZcashErrors.pcztFailed(
          "validate",
          reason: "Ironwood bundle requires transaction version 6.",
        );
      }
      if (!branch.hasIronwood()) {
        throw ZcashErrors.pcztFailed(
          "validate",
          reason: "Ironwood bundle before NU6.3 activation.",
          details: {"branch": branch.name},
        );
      }
    }
    final orchardVersion =
        OrchardBundleVersion.forBranch(branch) ??
        OrchardBundleVersion.orchardV1;
    orchard.verifyFlagsForVersion(orchardVersion);
    orchard.verifyCrossAddressRestriction();
    if (iron != null) {
      final ironVersion =
          OrchardBundleVersion.forBranch(branch, isIronwoodPool: true) ??
          OrchardBundleVersion.ironwoodV3;
      iron.verifyFlagsForVersion(ironVersion);
      iron.verifyCrossAddressRestriction();
    }
  }

  static Layout<Map<String, dynamic>> legacyLayout({String? property}) {
    return LayoutConst.struct([
      PcztGlobal.layout(property: "global"),
      TransparentPcztBundle.layout(propery: "transparent"),
      SaplingPcztBundle.layout(property: "sapling"),
      OrchardPcztBundle.layout(property: "orchard"),
    ], property: property);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      PcztGlobal.layout(property: "global"),
      TransparentPcztBundle.layout(propery: "transparent"),
      SaplingPcztBundle.layout(property: "sapling"),
      OrchardPcztBundle.layout(property: "orchard"),
      LayoutConst.optional(OrchardPcztBundle.layout(), property: "ironwood"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    // Null Ironwood encodes with the legacy layout so bytes stay
    // identical to pre-NU6.3 PCZTs.
    if (ironwood == null) return legacyLayout(property: property);
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "global": global.toSerializeJson(),
      "transparent": transparent.toSerializeJson(),
      "sapling": sapling.toSerializeJson(),
      "orchard": orchard.toSerializeJson(),
      "ironwood": ironwood?.toSerializeJson(),
    };
  }

  List<int> encode() {
    return [
      ...PcztConstants.magicBytes,
      ...PcztConstants.pcztVersion.toU32LeBytes(),
      ...toSerializeBytes(),
    ];
  }
}
