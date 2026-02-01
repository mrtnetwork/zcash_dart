import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';

abstract class ShardStore<H extends Object, ID extends Comparable> {
  Hashable<H> get hashContext;

  /// Returns the subtree at the given root address, if any.
  LocatedPrunableTree<H>? getShard(NodeAddress shardRoot);

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
  void addCheckpoint(
    ID checkpointId,
    Checkpoint checkpoint,
  );

  /// Returns number of checkpoints.
  int checkpointCount();

  /// Returns checkpoint at depth.
  (ID, Checkpoint)? getCheckpointAtDepth(int checkpointDepth);

  /// Returns checkpoint by id.
  Checkpoint? getCheckpoint(ID checkpointId);

  List<MapEntry<ID, Checkpoint>> getCheckpoints();

  /// Mutable iteration over checkpoints.
  void withCheckpoints(
      int limit, void Function(ID id, Checkpoint checkpoint) callback);

  /// Remove checkpoint.
  void removeCheckpoint(ID checkpointId);

  /// Truncate checkpoints retaining the specified one.
  void truncateCheckpointsRetaining(
    ID checkpointId,
  );

  ShardStore<H, ID> clone();
}

enum TreeStateType {
  empty(0),
  atPosition(1);

  final int value;
  const TreeStateType(this.value);
  static TreeStateType fromValue(int? value) {
    return values.firstWhere((e) => e.value == value,
        orElse: () =>
            throw ItemNotFoundException(name: "TreeStateType", value: value));
  }

  static TreeStateType fromName(String? name) {
    return values.firstWhere((e) => e.name == name,
        orElse: () =>
            throw ItemNotFoundException(name: "TreeStateType", value: name));
  }
}

sealed class TreeState with VariantLayoutSerializable, Equality {
  const TreeState();
  factory TreeState.deserializeJson(Map<String, dynamic> json) {
    final decode = VariantLayoutSerializable.toVariantDecodeResult(json);
    final type = TreeStateType.fromName(decode.variantName);
    return switch (type) {
      TreeStateType.empty => TreeStateEmpty(),
      TreeStateType.atPosition =>
        TreeStateAtPosition.deserializeJson(decode.value)
    };
  }
  bool get isEmpty;
  TreeStateType get type;
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyEnum([
      LazyVariantModel(
          layout: ({property}) => TreeStateEmpty.layout(property: property),
          property: TreeStateType.empty.name,
          index: TreeStateType.empty.value),
      LazyVariantModel(
          layout: ({property}) =>
              TreeStateAtPosition.layout(property: property),
          property: TreeStateType.atPosition.name,
          index: TreeStateType.atPosition.value),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toVariantLayout({String? property}) {
    return layout(property: property);
  }

  @override
  String get variantName => type.name;
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
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {};
  }

  @override
  TreeStateType get type => TreeStateType.empty;

  @override
  List<dynamic> get variables => [];
}

class TreeStateAtPosition extends TreeState {
  final LeafPosition position;
  const TreeStateAtPosition(this.position);
  factory TreeStateAtPosition.deserializeJson(Map<String, dynamic> json) {
    return TreeStateAtPosition(LeafPosition(json.valueAs("position")));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([LayoutConst.lebU32(property: "position")],
        property: property);
  }

  @override
  bool get isEmpty => false;
  @override
  String toString() {
    return "TreeStateAtPosition($position)";
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"position": position.position};
  }

  @override
  TreeStateType get type => TreeStateType.atPosition;

  @override
  List<dynamic> get variables => [position];
}

class SerializableTreeCheckpoint with LayoutSerializable {
  final int id;
  final TreeState state;
  const SerializableTreeCheckpoint({required this.id, required this.state});
  factory SerializableTreeCheckpoint.deserializeJson(
      Map<String, dynamic> json) {
    return SerializableTreeCheckpoint(
        id: json.valueAs("id"),
        state: TreeState.deserializeJson(json.valueAs("state")));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "id"),
      TreeState.layout(property: "state")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"id": id, "state": state.toSerializeVariantJson()};
  }
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
    return Checkpoint._(
      TreeStateAtPosition(position),
      <LeafPosition>{},
    );
  }

  // TreeState treeState() => treeState;

  Set<LeafPosition> marksRemoved() => _marksRemoved;

  bool get isTreeEmpty => treeState.isEmpty;

  LeafPosition? position() {
    return switch (treeState) {
      TreeStateAtPosition(:final position) => position,
      TreeStateEmpty() => null
    };
  }

  void markRemoved(LeafPosition position) {
    _marksRemoved.add(position);
  }
}
