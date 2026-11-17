import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';

/// Zcash-specific error types. Phase 2: taxonomy only, no serialization.
enum ZcashErrorType implements BuErrorType {
  plugin(12000),
  invalidUnifiedReceivers(12001),
  mismatchNetwork(12002),
  scannerFailed(12003),
  scannerInvalidCompact(12004),
  cryptoContext(12005),
  merkleFailed(12006),
  merkleMergeConflict(12007),
  merkleFrontierIncomplete(12008),
  merkleFrontierFailed(12009),
  merkleWitnessFailed(12010),
  merkleWitnessAddressNotFound(12011),
  merkleInsertionSubtreeFailed(12012),
  merkleInsertionFailed(12013),
  merkleInsertionFrontierFailed(12014),
  merkleBuilderFailed(12015),
  noteFailed(12016),
  orchardFailed(12017),
  orchardBuilderFailed(12018),
  orchardPcztFailed(12019),
  saplingFailed(12020),
  saplingBuilderFailed(12021),
  saplingPcztFailed(12022),
  transparentFailed(12023),
  transparentMultisigFailed(12024),
  transparentBuilderFailed(12025),
  transparentPcztFailed(12026),
  pcztFailed(12027),
  txBuilderFailed(12028),
  txSerializationFailed(12029),
  txSerializationUnexpected(12030),
  walletdFailed(12031);

  @override
  String get domain => 'zcash';

  @override
  String get errName => name;

  @override
  final int id;
  const ZcashErrorType(this.id);

  @override
  bool isValid(int? tag) {
    if (tag == null) return false;
    return values.any((e) => e.id == tag);
  }
}

/// Same-signature helpers replacing the removed per-class factories.
/// Message text and `details` shapes are preserved verbatim (including the
/// `Opearion` typo and the `MerkleWitnessError.incompleteTree` quirk, which
/// historically produced a frontier-tagged error).
abstract final class ZcashErrors {
  static const invalidUnifiedReceivers = BuError(
    ZcashErrorType.invalidUnifiedReceivers,
    "Invalid unified address receivers.",
  );

  static BuError mismatchNetwork({
    required ZcashNetwork network,
    required ZcashNetwork expected,
  }) => BuError(
    ZcashErrorType.mismatchNetwork,
    "Network mismatch: address belongs to a different network.",
    details: {"network": network.name, "expected": expected.name},
  );

  static BuError scannerFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.scannerFailed,
    "Block scan failed during $operation",
    details: {"reason": reason, ...details ?? {}}.notNullValue,
  );

  static BuError scannerInvalidCompact(
    String elem, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.scannerInvalidCompact,
    "Invalid compact $elem object.",
    details: {"reason": reason, ...details ?? {}}.notNullValue,
  );

  static BuError pcztFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.pcztFailed,
    "Pczt operation failed during $operation.",
    details: {"reason": reason, ...details ?? {}}.notNullValue,
  );

  static BuError merkleFailed(
    String name, {
    String? reason,
    Map<String, String?>? details,
  }) => BuError(
    ZcashErrorType.merkleFailed,
    "Merkle operation failed during $name",
    details: {"reason": reason, ...details ?? {}}.notNullValue,
  );

  static String _addr(NodeAddress a) =>
      'level=${a.level.value} index=${a.index}';
  static String _addrs(List<NodeAddress> a) => a.map(_addr).join(',');

  static BuError merkleMergeConflict({
    required String name,
    required NodeAddress address,
  }) => BuError(
    ZcashErrorType.merkleMergeConflict,
    "Merkle merge operation failed during $name",
    details:
        {"reason": "Merge conflict at address ${_addr(address)}"}.notNullValue,
  );

  static BuError merkleFrontierIncomplete({
    required String name,
    List<NodeAddress> addresses = const [],
  }) => BuError(
    ZcashErrorType.merkleFrontierIncomplete,
    "Frontier operation failed during $name",
    details:
        {
          "reason": "Tree incomplete.",
          if (addresses.isNotEmpty) "addresses": _addrs(addresses),
        }.notNullValue,
  );

  static BuError merkleFrontierFailed({
    required String name,
    required String reason,
    List<NodeAddress> addresses = const [],
  }) => BuError(
    ZcashErrorType.merkleFrontierFailed,
    "Frontier operation failed during $name",
    details:
        {
          "reason": reason,
          if (addresses.isNotEmpty) "addresses": _addrs(addresses),
        }.notNullValue,
  );

  static BuError merkleWitnessFailed({
    required String name,
    required String reason,
    List<NodeAddress> addresses = const [],
  }) => BuError(
    ZcashErrorType.merkleWitnessFailed,
    "Witness operation failed during $name",
    details:
        {
          "reason": reason,
          if (addresses.isNotEmpty) "addresses": _addrs(addresses),
        }.notNullValue,
  );

  static BuError merkleWitnessAddressNotFound({
    required String name,
    required NodeAddress address,
  }) => BuError(
    ZcashErrorType.merkleWitnessAddressNotFound,
    "Witness operation failed during $name",
    details:
        {
          "reason": "Address not found in tree.",
          "address": _addr(address),
        }.notNullValue,
  );

  /// Mirrors the historical quirk where
  /// `MerkleWitnessError.incompleteTree` produced a frontier-tagged error.
  static BuError merkleWitnessIncompleteTree({
    required String name,
    List<NodeAddress> addresses = const [],
  }) => BuError(
    ZcashErrorType.merkleFrontierIncomplete,
    "Witness operation failed during $name",
    details:
        {
          "reason": "Tree incomplete.",
          if (addresses.isNotEmpty) "addresses": _addrs(addresses),
        }.notNullValue,
  );

  static BuError merkleInsertionSubtreeFailed({
    required String name,
    required String? reason,
    NodeAddress? address,
  }) => BuError(
    ZcashErrorType.merkleInsertionSubtreeFailed,
    "Subtree insertion operation failed during $name",
    details:
        {
          "reason": reason,
          if (address != null) "address": _addr(address),
        }.notNullValue,
  );

  static BuError merkleInsertionFailed({
    required String name,
    String? reason,
    NodeAddress? address,
  }) => BuError(
    ZcashErrorType.merkleInsertionFailed,
    "Tree insertion operation failed during $name",
    details:
        {
          "reason": reason,
          if (address != null) "addresses": _addr(address),
        }.notNullValue,
  );

  static BuError merkleInsertionFrontierFailed({
    required String name,
    required String reason,
    NodeAddress? address,
  }) => BuError(
    ZcashErrorType.merkleInsertionFrontierFailed,
    "Frontier insertion operation failed during $name",
    details:
        {
          "reason": reason,
          if (address != null) "addresses": _addr(address),
        }.notNullValue,
  );

  static BuError merkleBuilderFailed(
    String name, {
    String? reason,
    Map<String, String?>? details,
  }) => BuError(
    ZcashErrorType.merkleBuilderFailed,
    "Merkle builder operation failed during $name",
    details: {"reason": reason, ...details ?? {}}.notNullValue,
  );

  static BuError noteFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.noteFailed,
    "Note operation failed during $operation.",
    details: {...details ?? {}, "reason": reason},
  );

  static BuError orchardFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.orchardFailed,
    "Orchard operation failed during $operation",
    details: {...details ?? {}, "reason": reason},
  );

  static BuError orchardBuilderFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.orchardBuilderFailed,
    "Orchard builder operation failed during $operation",
    details: {...details ?? {}, "reason": reason},
  );

  static BuError orchardPcztFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.orchardPcztFailed,
    "Orchard Pczt operation failed during $operation",
    details: {...details ?? {}, "reason": reason},
  );

  static BuError saplingFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.saplingFailed,
    "Sapling operation failure during $operation",
    details: details,
  );

  static BuError saplingBuilderFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.saplingBuilderFailed,
    "Sapling builder operation failed during $operation",
    details: {...details ?? {}, "reason": reason},
  );

  static BuError saplingPcztFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.saplingPcztFailed,
    "Sapling Pczt failure during $operation",
    details: {"reason": reason, ...details ?? {}},
  );

  static BuError transparentFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.transparentFailed,
    "Transparent operation failure during $operation",
    details: details,
  );

  static BuError transparentMultisigFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.transparentMultisigFailed,
    "Transparent multisig address generation failed.",
    details: details,
  );

  static BuError transparentBuilderFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.transparentBuilderFailed,
    "Transparent builder operation failed during $operation",
    details: {...details ?? {}, "reason": reason},
  );

  static BuError transparentPcztFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.transparentPcztFailed,
    "Transparent Pczt failure during $operation",
    details: {...details ?? {}, "reason": reason},
  );

  static BuError txBuilderFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.txBuilderFailed,
    "Transaction builder operation failed during $operation",
    details: {...details ?? {}, "reason": reason}.notNullValue,
  );

  static BuError txSerializationFailed(String operation) => BuError(
    ZcashErrorType.txSerializationFailed,
    "Serialization failed: missing or unknown parameters for '$operation'.",
  );

  static const txSerializationUnexpected = BuError(
    ZcashErrorType.txSerializationUnexpected,
    "Unexpected error while serialization transaction",
  );

  static BuError walletdFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
  }) => BuError(
    ZcashErrorType.walletdFailed,
    "Opearion failed during $operation",
    details: details,
  );
}
