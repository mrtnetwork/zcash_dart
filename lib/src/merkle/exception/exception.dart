import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/merkle/merkle.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class MerkleTreeException extends BaseDartZcashPluginException {
  const MerkleTreeException(super.message, {super.details});
  factory MerkleTreeException.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.merkleError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return MerkleTreeException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.merkleError;
  static MerkleTreeException failed(
    String name, {
    String? reason,
    Map<String, String?>? details,
  }) {
    return MerkleTreeException(
      "Merkle operation failed during $name",
      details: {"reason": reason, ...details ?? {}}.notNullValue,
    );
  }
}

class MerkleMergeError extends MerkleTreeException {
  final NodeAddress address;
  const MerkleMergeError._({
    required String message,
    Map<String, String?>? details,
    required this.address,
  }) : super(message, details: details);
  static MerkleMergeError conflict({
    required String name,
    required NodeAddress address,
  }) {
    return MerkleMergeError._(
      message: "Merkle merge operation failed during $name",
      address: address,
      details: {"reason": "Merge conflict at address $address"}.notNullValue,
    );
  }

  factory MerkleMergeError.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.merkleMergeError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return MerkleMergeError._(
      message: values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
      address: NodeAddress.deserialize(object: values.objectAt(2)),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.merkleMergeError;

  @override
  List<CborObject?> get serializationItems => [
    ...super.serializationItems,
    address.toCbor(),
  ];

  @override
  List<dynamic> get variables => [...super.variables, address];
}

class MerkleFrontierError extends MerkleTreeException {
  final List<NodeAddress> addresses;
  const MerkleFrontierError._({
    required String message,
    required this.addresses,
    Map<String, String?>? details,
  }) : super(message, details: details);
  static MerkleFrontierError incompleteTree({
    required String name,
    List<NodeAddress> addresses = const [],
  }) {
    return MerkleFrontierError._(
      message: "Frontier operation failed during $name",
      addresses: addresses,
      details: {"reason": "Tree incomplete."}.notNullValue,
    );
  }

  static MerkleFrontierError failed({
    required String name,
    required String reason,
    List<NodeAddress> addresses = const [],
  }) {
    return MerkleFrontierError._(
      message: "Frontier operation failed during $name",
      addresses: addresses,
      details: {"reason": reason}.notNullValue,
    );
  }

  factory MerkleFrontierError.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.merkleFrontierError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return MerkleFrontierError._(
      message: values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
      addresses:
          values
              .listAt<CborTagValue>(2)
              .map((e) => NodeAddress.deserialize(object: e))
              .toList(),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.merkleFrontierError;

  @override
  List<CborObject?> get serializationItems => [
    ...super.serializationItems,
    CborTagSerializable.listFromDynamic(
      addresses.map((e) => e.toCbor()).toList(),
    ),
  ];
  @override
  List<dynamic> get variables => [...super.variables, addresses];
}

class MerkleWitnessError extends MerkleTreeException {
  final List<NodeAddress> addresses;
  const MerkleWitnessError._({
    required String message,
    required this.addresses,
    Map<String, String?>? details,
  }) : super(message, details: details);
  static MerkleFrontierError incompleteTree({
    required String name,
    List<NodeAddress> addresses = const [],
  }) {
    return MerkleFrontierError._(
      message: "Witness operation failed during $name",
      addresses: addresses,
      details: {"reason": "Tree incomplete."}.notNullValue,
    );
  }

  static MerkleWitnessError failed({
    required String name,
    required String reason,
    List<NodeAddress> addresses = const [],
  }) {
    return MerkleWitnessError._(
      message: "Witness operation failed during $name",
      addresses: addresses,
      details: {"reason": reason}.notNullValue,
    );
  }

  static MerkleWitnessError addressNotFound({
    required String name,
    required NodeAddress address,
  }) {
    return MerkleWitnessError._(
      message: "Witness operation failed during $name",
      addresses: [address],
      details: {"reason": "Address not found in tree."}.notNullValue,
    );
  }

  factory MerkleWitnessError.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.merkleWitnessError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return MerkleWitnessError._(
      message: values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
      addresses:
          values
              .listAt<CborTagValue>(2)
              .map((e) => NodeAddress.deserialize(object: e))
              .toList(),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.merkleWitnessError;

  @override
  List<CborObject?> get serializationItems => [
    ...super.serializationItems,
    CborTagSerializable.listFromDynamic(
      addresses.map((e) => e.toCbor()).toList(),
    ),
  ];
  @override
  List<dynamic> get variables => [...super.variables, addresses];
}

class MerkleInsertionError extends MerkleTreeException {
  final NodeAddress? address;
  const MerkleInsertionError._({
    required String message,
    required this.address,
    Map<String, String?>? details,
  }) : super(message, details: details);
  static MerkleInsertionError subtreeInsertionFailed({
    required String name,
    required String? reason,
    NodeAddress? address,
  }) {
    return MerkleInsertionError._(
      message: "Subtree insertion operation failed during $name",
      address: address,
      details: {"reason": reason}.notNullValue,
    );
  }

  static MerkleInsertionError insertionFailed({
    required String name,
    String? reason,
    NodeAddress? address,
  }) {
    return MerkleInsertionError._(
      message: "Tree insertion operation failed during $name",
      address: address,
      details: {"reason": reason}.notNullValue,
    );
  }

  static MerkleInsertionError frontierInsertionFailed({
    required String name,
    required String reason,
    NodeAddress? address,
  }) {
    return MerkleInsertionError._(
      message: "Frontier insertion operation failed during $name",
      address: address,
      details: {"reason": reason}.notNullValue,
    );
  }

  factory MerkleInsertionError.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.merkleInsertionError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return MerkleInsertionError._(
      message: values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
      address: values.maybeObjectAt<NodeAddress, CborTagValue>(
        2,
        (e) => NodeAddress.deserialize(object: e),
      ),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.merkleInsertionError;

  @override
  List<CborObject?> get serializationItems => [
    ...super.serializationItems,
    address?.toCbor(),
  ];
  @override
  List<dynamic> get variables => [...super.variables, address];
}

class MerkleBuilderException extends MerkleTreeException {
  const MerkleBuilderException(super.message, {super.details});
  factory MerkleBuilderException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.merkleBuilderError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return MerkleBuilderException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.merkleBuilderError;
  static MerkleBuilderException failed(
    String name, {
    String? reason,
    Map<String, String?>? details,
  }) {
    return MerkleBuilderException(
      "Merkle builder operation failed during $name",
      details: {"reason": reason, ...details ?? {}}.notNullValue,
    );
  }
}
