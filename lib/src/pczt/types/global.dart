import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/pczt/exception/exception.dart';
import 'package:zcash_dart/src/pczt/constants/cosntants.dart';
import 'package:zcash_dart/src/pczt/pczt/utils.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';

class PcztGlobal with LayoutSerializable, Equality {
  final int txVersion;
  final int versionGroupId;
  final int consensusBranchId;
  final int? fallbackLockTime;
  final int expiryHeight;
  final int coinType;
  int _txModifiable;
  int get txModifiable => _txModifiable;
  final Map<String, List<int>> _proprietary;
  Map<String, List<int>> get proprietary => _proprietary;
  PcztGlobal(
      {required this.txVersion,
      required this.versionGroupId,
      required this.consensusBranchId,
      this.fallbackLockTime,
      required this.expiryHeight,
      required this.coinType,
      required int txModifiable,
      Map<String, List<int>> proprietary = const {}})
      : _txModifiable = txModifiable,
        _proprietary = proprietary
            .map((k, v) => MapEntry(k, v.asImmutableBytes))
            .immutable;
  factory PcztGlobal.defaultGlobal(ZCashNetwork network, int expiryHeight) {
    return PcztGlobal(
        txVersion: TxVersionType.v5.txVesion,
        versionGroupId: TxVersionType.v5.groupId!,
        consensusBranchId: NetworkUpgrade.nu6_1.branchId,
        expiryHeight: expiryHeight,
        coinType: network.config().coinIdx,
        txModifiable: PcztConstants.initialTxModifiable);
  }

  PcztGlobal clone() => PcztGlobal(
      txVersion: txVersion,
      versionGroupId: versionGroupId,
      consensusBranchId: consensusBranchId,
      expiryHeight: expiryHeight,
      coinType: coinType,
      txModifiable: txModifiable,
      proprietary: proprietary);
  factory PcztGlobal.deserializeJson(Map<String, dynamic> json) {
    return PcztGlobal(
        txVersion: json.valueAs("tx_version"),
        versionGroupId: json.valueAs("version_group_id"),
        consensusBranchId: json.valueAs("consensus_branch_id"),
        fallbackLockTime: json.valueAs("fallback_lock_time"),
        expiryHeight: json.valueAs("expiry_height"),
        coinType: json.valueAs("coin_type"),
        txModifiable: json.valueAs("tx_modifiable"),
        proprietary: json.valueEnsureAsMap<String, List<int>>("proprietary"));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "tx_version"),
      LayoutConst.lebU32(property: "version_group_id"),
      LayoutConst.lebU32(property: "consensus_branch_id"),
      LayoutConst.optional(LayoutConst.lebU32(),
          property: "fallback_lock_time"),
      LayoutConst.lebU32(property: "expiry_height"),
      LayoutConst.lebU32(property: "coin_type"),
      LayoutConst.u8(property: "tx_modifiable"),
      LayoutConst.bscMap<String, List<int>>(
          LayoutConst.bcsString(), LayoutConst.bcsBytes(),
          property: "proprietary")
    ], property: property);
  }

  /// Returns whether transparent inputs can be added to or removed.
  bool inputsModifiable() {
    return (txModifiable & PcztConstants.flagTransparentInputsModifiable) != 0;
  }

  /// Returns whether transparent outputs can be added to or removed.
  bool outputsModifiable() {
    return (txModifiable & PcztConstants.flagTransparentOutputsModifiable) != 0;
  }

  /// Returns whether the transaction has a SIGHASH_SINGLE transparent signature.
  bool hasSighashSingle() {
    return (txModifiable & PcztConstants.flagHasSighashSingle) != 0;
  }

  /// Returns whether shielded spends or outputs can be added or removed.
  bool shieldedModifiable() {
    return (txModifiable & PcztConstants.flagShieldedModifiable) != 0;
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMerge(PcztGlobal other) {
    return PcztUtils.canMerge(txVersion, other.txVersion) &&
        PcztUtils.canMerge(versionGroupId, other.versionGroupId) &&
        PcztUtils.canMerge(consensusBranchId, other.consensusBranchId) &&
        PcztUtils.canMerge(fallbackLockTime, other.fallbackLockTime) &&
        PcztUtils.canMerge(expiryHeight, other.expiryHeight) &&
        PcztUtils.canMerge(coinType, other.coinType);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  PcztGlobal? merge(PcztGlobal other) {
    if (!canMerge(other)) {
      return null;
    }
    final proprietary =
        PcztUtils.mergeProprietary(this.proprietary, other.proprietary);
    if (proprietary == null) return null;
    int txModifiable = this.txModifiable;
    if ((other.txModifiable & PcztConstants.flagTransparentInputsModifiable) ==
        0) {
      txModifiable &= ~PcztConstants.flagTransparentInputsModifiable;
    }

    // Bit 1 → merges toward false
    if ((other.txModifiable & PcztConstants.flagTransparentOutputsModifiable) ==
        0) {
      txModifiable &= ~PcztConstants.flagTransparentOutputsModifiable;
    }

    // Bit 2 → merges toward true
    if ((other.txModifiable & PcztConstants.flagHasSighashSingle) != 0) {
      txModifiable |= PcztConstants.flagHasSighashSingle;
    }

    // Bits 3–6 must be zero
    final selfInvalid =
        ((txModifiable & ~PcztConstants.flagShieldedModifiable) >> 3) != 0;
    final otherInvalid =
        ((other.txModifiable & ~PcztConstants.flagShieldedModifiable) >> 3) !=
            0;

    if (selfInvalid || otherInvalid) {
      return null;
    }

    // Bit 7 → merges toward false
    if ((other.txModifiable & PcztConstants.flagShieldedModifiable) == 0) {
      txModifiable &= ~PcztConstants.flagShieldedModifiable;
    }
    return PcztGlobal(
        txVersion: txVersion,
        versionGroupId: versionGroupId,
        consensusBranchId: consensusBranchId,
        fallbackLockTime: fallbackLockTime,
        expiryHeight: expiryHeight,
        coinType: coinType,
        txModifiable: txModifiable,
        proprietary: proprietary);
  }

  TxVersion getTxVersion() {
    final version =
        TxVersionType.findFromVersionAndGroudId(txVersion, versionGroupId);
    if (version == null) {
      throw PcztException.failed("getTxVersion",
          reason: "Unsupported transaction version.");
    }
    return version.toVersion();
  }

  NetworkUpgrade getBranchId() {
    try {
      return NetworkUpgrade.fromId(consensusBranchId);
    } catch (_) {
      throw PcztException.failed("getTxVersion", reason: "Unknown branch id.");
    }
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "tx_version": txVersion,
      "version_group_id": versionGroupId,
      "consensus_branch_id": consensusBranchId,
      "fallback_lock_time": fallbackLockTime,
      "expiry_height": expiryHeight,
      "coin_type": coinType,
      "tx_modifiable": txModifiable,
      "proprietary": proprietary
    };
  }

  @override
  List<dynamic> get variables => [
        txVersion,
        versionGroupId,
        consensusBranchId,
        fallbackLockTime,
        expiryHeight,
        coinType,
        txModifiable,
        proprietary
      ];

  void setTxModifiable(int txModifiable) {
    _txModifiable = txModifiable;
  }

  void disableModifiable() {
    _txModifiable &= ~(PcztConstants.flagTransparentInputsModifiable |
        PcztConstants.flagTransparentOutputsModifiable |
        PcztConstants.flagShieldedModifiable);
  }

  void disableInputModifable() {
    _txModifiable &= ~PcztConstants.flagTransparentInputsModifiable;
  }

  void disableOutputModifable() {
    _txModifiable &= ~PcztConstants.flagTransparentOutputsModifiable;
  }

  void setHasSighashAll() {
    _txModifiable |= PcztConstants.flagHasSighashSingle;
  }

  void disableShieldModifiable() {
    _txModifiable &= ~PcztConstants.flagShieldedModifiable;
  }
}
