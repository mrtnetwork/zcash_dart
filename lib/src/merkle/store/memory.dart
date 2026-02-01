import 'dart:collection';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';

class MemoryShardStore<H extends Object, C extends Comparable>
    implements ShardStore<H, C> {
  final List<LocatedPrunableTree<H>> _shards;
  final SplayTreeMap<C, Checkpoint> _checkpoints;
  PrunableTree<H> _cap;

  MemoryShardStore.empty(Hashable<H> hashContext)
      : _cap = PrunableTree.empty(hashContext),
        _shards = [],
        _checkpoints = SplayTreeMap<C, Checkpoint>();

  @override
  ShardStore<H, C> clone() {
    return MemoryShardStore.empty(hashContext)
      .._cap = _cap
      .._checkpoints.addAll(_checkpoints)
      .._shards.addAll(_shards);
  }

  @override
  LocatedPrunableTree<H>? getShard(NodeAddress shardRoot) {
    final idx = shardRoot.index;
    if (idx < 0 || idx >= _shards.length) {
      return null;
    }
    return _shards[idx];
  }

  @override
  LocatedPrunableTree<H>? lastShard() {
    if (_shards.isEmpty) return null;
    return _shards.last;
  }

  @override
  void putShard(LocatedPrunableTree<H> subtree) {
    final addr = subtree.rootAddr;
    final targetIndex = addr.index;

    final start = _shards.isEmpty ? 0 : _shards.last.rootAddr.index + 1;

    for (var i = start; i <= targetIndex; i += 1) {
      _shards.add(
        LocatedPrunableTree(
          rootAddr: NodeAddress(level: addr.level, index: i),
          root: PrunableTree<H>.empty(hashContext),
        ),
      );
    }

    _shards[targetIndex.toInt()] = subtree;
  }

  @override
  List<NodeAddress> getShardRoots() {
    return _shards.map((s) => s.rootAddr).toList();
  }

  @override
  void truncateShards(int shardIndex) {
    if (shardIndex < _shards.length) {
      _shards.removeRange(shardIndex, _shards.length);
    }
  }

  @override
  PrunableTree<H> getCap() {
    return _cap;
  }

  @override
  void putCap(PrunableTree<H> cap) {
    _cap = cap;
  }

  @override
  void addCheckpoint(
    C checkpointId,
    Checkpoint checkpoint,
  ) {
    _checkpoints[checkpointId] = checkpoint;
  }

  @override
  int checkpointCount() {
    return _checkpoints.length;
  }

  @override
  Checkpoint? getCheckpoint(C checkpointId) {
    return _checkpoints[checkpointId];
  }

  @override
  (C, Checkpoint)? getCheckpointAtDepth(int depth) {
    if (depth < 0 || depth >= _checkpoints.length) {
      return null;
    }

    final entry = _checkpoints.entries.toList().reversed.elementAt(depth);

    return (entry.key, entry.value);
  }

  @override
  C? minCheckpointId() {
    return _checkpoints.isEmpty ? null : _checkpoints.firstKey();
  }

  @override
  C? maxCheckpointId() {
    return _checkpoints.isEmpty ? null : _checkpoints.lastKey();
  }

  @override
  void withCheckpoints(
    int limit,
    void Function(C id, Checkpoint checkpoint) callback,
  ) {
    var count = 0;
    for (final entry in _checkpoints.entries) {
      if (count++ >= limit) break;
      callback(entry.key, entry.value);
    }
  }

  @override
  void removeCheckpoint(C checkpointId) {
    _checkpoints.remove(checkpointId);
  }

  @override
  void truncateCheckpointsRetaining(C checkpointId) {
    final keysToRemove =
        _checkpoints.keys.where((k) => k.compareTo(checkpointId) > 0).toList();

    for (final k in keysToRemove) {
      _checkpoints.remove(k);
    }

    final retained = _checkpoints[checkpointId];
    if (retained != null) {
      retained.marksRemoved().clear();
    }
  }

  @override
  Hashable<H> get hashContext => _cap.hashContext;

  @override
  List<LocatedPrunableTree<H>> getShards() {
    return _shards.clone();
  }

  @override
  List<MapEntry<C, Checkpoint>> getCheckpoints() {
    return _checkpoints.entries.toList();
  }
}
