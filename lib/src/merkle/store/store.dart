import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

abstract class ShardStore<H extends MerkleNodeValue, ID extends Comparable> {
  Hashable<H> get hashContext;
  int get totalShards;

  /// Returns the subtree at the given root address, if any.
  LocatedPrunableTree<H>? getShard(NodeAddress shardRoot);

  /// Returns the subtree at the node index if any.
  LocatedPrunableTree<H>? getShardAtIndex(int index);

  List<LocatedPrunableTree<H>> getShards();

  /// Returns the subtree containing the maximum inserted leaf position.
  LocatedPrunableTree<H>? lastShard();

  /// Inserts or replaces a shard.
  void putShard(LocatedPrunableTree<H> subtree);

  /// Returns all shard root addresses.
  List<NodeAddress> getShardRoots();

  /// Removes shards with index >= shardIndex.
  void truncateShards(int shardIndex);

  /// Returns the cached cap tree.
  PrunableTree<H> getCap();

  /// Persists the cap tree.
  void putCap(PrunableTree<H> cap);

  /// Returns the checkpoint with the lowest position.
  ID? minCheckpointId();

  /// Returns the checkpoint with the highest position.
  ID? maxCheckpointId();

  /// Adds a checkpoint.
  void addCheckpoint(ID checkpointId, Checkpoint checkpoint);

  /// Returns number of checkpoints.
  int checkpointCount();

  /// Returns checkpoint at depth.
  (ID, Checkpoint)? getCheckpointAtDepth(int checkpointDepth);

  /// Returns checkpoint by id.
  Checkpoint? getCheckpoint(ID checkpointId);

  List<MapEntry<ID, Checkpoint>> getCheckpoints();

  /// Mutable iteration over checkpoints.
  void withCheckpoints(
    int limit,
    void Function(ID id, Checkpoint checkpoint) callback,
  );

  /// Remove checkpoint.
  void removeCheckpoint(ID checkpointId);

  /// Truncate checkpoints retaining the specified one.
  void truncateCheckpointsRetaining(ID checkpointId);

  ShardStore<H, ID> clone({Hashable<H>? hashContext});
}

// enum TreeStateType {
//   empty(0),
//   atPosition(1);

//   final int value;
//   const TreeStateType(this.value);
//   static TreeStateType fromValue(int? value) {
//     return values.firstWhere(
//       (e) => e.value == value,
//       orElse: () => throw BuError(DefaultErrorType.notFound, "No matching TreeStateType found for the given value. $value", details: {"name": "TreeStateType", "value": value?.toString()}),
//     );
//   }

//   static TreeStateType fromName(String? name) {
//     return values.firstWhere(
//       (e) => e.name == name,
//       orElse: () => throw BuError(DefaultErrorType.notFound, "No matching TreeStateType found for the given value. $name", details: {"name": "TreeStateType", "value": name?.toString()}),
//     );
//   }
// }

sealed class TreeState with Equality {
  const TreeState();

  bool get isEmpty;
}

class TreeStateEmpty extends TreeState {
  const TreeStateEmpty();

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.noArgs();
  }

  @override
  bool get isEmpty => true;

  @override
  String toString() {
    return "TreeStateEmpty()";
  }

  @override
  List<dynamic> get variables => [];
}

class TreeStateAtPosition extends TreeState {
  final LeafPosition position;
  const TreeStateAtPosition(this.position);
  @override
  bool get isEmpty => false;
  @override
  String toString() {
    return "TreeStateAtPosition($position)";
  }

  @override
  List<dynamic> get variables => [position];
}

class SerializableTreeCheckpoint with CborTagSerializable {
  final TreeState state;
  final int id;

  SerializableTreeCheckpoint({required int id, required this.state})
    : id = id.asU32;
  factory SerializableTreeCheckpoint.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.serializableTreeCheckpoint,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableTreeCheckpoint(
      state:
          values.maybeRawValueAt<TreeState, int>(
            0,
            (v) => TreeStateAtPosition(LeafPosition(v)),
          ) ??
          TreeStateEmpty(),
      id: values.rawValueAt(1),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serializableTreeCheckpoint;

  @override
  List<CborObject?> get serializationItems => [
    switch (state) {
      TreeStateEmpty() => null,
      TreeStateAtPosition(:final position) => position.position.toCbor(),
    },
    id.toCbor(),
  ];
}

class Checkpoint {
  final TreeState treeState;
  final Set<LeafPosition> _marksRemoved;
  @override
  String toString() {
    return "Checkpoint(state: $treeState, marksRemoved: $_marksRemoved)";
  }

  factory Checkpoint.fromState(TreeState state) =>
      Checkpoint._(state, <LeafPosition>{});

  Checkpoint._(this.treeState, this._marksRemoved);

  factory Checkpoint.treeEmpty() {
    return Checkpoint._(const TreeStateEmpty(), <LeafPosition>{});
  }

  factory Checkpoint.atPosition(LeafPosition position) {
    return Checkpoint._(TreeStateAtPosition(position), <LeafPosition>{});
  }

  // TreeState treeState() => treeState;

  Set<LeafPosition> marksRemoved() => _marksRemoved;

  bool get isTreeEmpty => treeState.isEmpty;

  LeafPosition? position() {
    return switch (treeState) {
      TreeStateAtPosition(:final position) => position,
      TreeStateEmpty() => null,
    };
  }

  void markRemoved(LeafPosition position) {
    _marksRemoved.add(position);
  }
}

class SerializableTreeCheckpointPosition
    with LayoutSerializable, CborTagSerializable {
  final int checkpoint;
  final LeafPosition position;
  const SerializableTreeCheckpointPosition({
    required this.checkpoint,
    required this.position,
  });
  factory SerializableTreeCheckpointPosition.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier:
          ZcashSerializationIdentifier.serializableTreeCheckpointPosition,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableTreeCheckpointPosition(
      checkpoint: values.rawValueAt(0),
      position: LeafPosition(values.rawValueAt(1)),
    );
  }
  factory SerializableTreeCheckpointPosition.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return SerializableTreeCheckpointPosition(
      checkpoint: json.valueAsInt("checkpoint"),
      position: LeafPosition(json.valueAsInt("position")),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "checkpoint"),
      LayoutConst.lebU64(property: "position"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "checkpoint": checkpoint,
      "position": BigInt.from(position.position),
    };
  }

  @override
  String toString() {
    return "{checkpint: $checkpoint, possition: ${position.position}}";
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serializableTreeCheckpointPosition;

  @override
  List<CborObject?> get serializationItems => [
    checkpoint.toCbor(),
    position.position.toCbor(),
  ];
}
