import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/shard_tree.dart';
import 'package:zcash_dart/src/merkle/store/memory.dart';

import 'types.dart';

void main() {
  test(
    "store",
    () {
      checkWitnesses();
      _checkRootHashes();
      _append();
      _witnessWithPrunedSubtrees();
      _checkShardSizes();
      _insert();
    },
  );
}

void checkWitnesses() {
  {
    final tree = newTree(100);
    _assertAppend(tree, 0, RetentionEphemeral());
    _assertAppend(tree, 1, RetentionMarked());
    _checkpoint(tree, 0);
    expect(_witness(tree, LeafPosition(0), 0), null);
  }
  {
    final tree = newTree(100);
    _assertAppend(tree, 0, RetentionMarked());
    _checkpoint(tree, 0);
    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(0), 0), [
          hashable.emptyRoot(TreeLevel.zero),
          hashable.emptyRoot(TreeLevel(1)),
          hashable.emptyRoot(TreeLevel(2)),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
    _assertAppend(tree, 1, RetentionMarked());
    _checkpoint(tree, 1);
    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(0), 0), [
          StringHashable.fromU64(1),
          hashable.emptyRoot(TreeLevel(1)),
          hashable.emptyRoot(TreeLevel(2)),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
    _assertAppend(tree, 2, RetentionMarked());
    _checkpoint(tree, 2);
    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(2), 0), [
          hashable.emptyRoot(TreeLevel.zero),
          hashable.combineAll(1, [0, 1]),
          hashable.emptyRoot(TreeLevel(2)),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
    _assertAppend(tree, 3, RetentionEphemeral());
    _checkpoint(tree, 3);
    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(2), 0), [
          StringHashable.fromU64(3),
          hashable.combineAll(1, [0, 1]),
          hashable.emptyRoot(TreeLevel(2)),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
    _assertAppend(tree, 4, RetentionEphemeral());
    _checkpoint(tree, 4);

    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(2), 0), [
          StringHashable.fromU64(3),
          hashable.combineAll(1, [0, 1]),
          hashable.combineAll(2, [4]),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
  }

  {
    final tree = newTree(100);
    _assertAppend(tree, 0, RetentionMarked());
    for (int i = 1; i < 6; i++) {
      _assertAppend(tree, i, RetentionEphemeral());
    }
    _assertAppend(tree, 6, RetentionMarked());
    _assertAppend(tree, 7, RetentionEphemeral());
    _checkpoint(tree, 0);
    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(0), 0), [
          StringHashable.fromU64(1),
          hashable.combineAll(1, [2, 3]),
          hashable.combineAll(2, [4, 5, 6, 7]),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
  }
  {
    final tree = newTree(100);
    _assertAppend(tree, 0, RetentionMarked());
    _assertAppend(tree, 1, RetentionEphemeral());
    _assertAppend(tree, 2, RetentionEphemeral());
    _assertAppend(tree, 3, RetentionMarked());
    _assertAppend(tree, 4, RetentionMarked());
    _assertAppend(tree, 5, RetentionMarked());
    _assertAppend(tree, 6, RetentionEphemeral());
    _checkpoint(tree, 0);
    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(5), 0), [
          StringHashable.fromU64(4),
          hashable.combineAll(1, [6]),
          hashable.combineAll(2, [0, 1, 2, 3]),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
  }
  {
    final tree = newTree(100);
    for (int i = 0; i < 10; i++) {
      _assertAppend(tree, i, RetentionEphemeral());
    }
    _assertAppend(tree, 10, RetentionMarked());
    _assertAppend(tree, 11, RetentionEphemeral());
    _checkpoint(tree, 0);

    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(10), 0), [
          StringHashable.fromU64(11),
          hashable.combineAll(1, [8, 9]),
          hashable.emptyRoot(TreeLevel(2)),
          hashable.combineAll(3, [0, 1, 2, 3, 4, 5, 6, 7])
        ]),
        true);
  }
  {
    final tree = newTree(100);
    _assertAppend(
        tree, 0, RetentionCheckpoint(marking: MarkingState.marked, id: 1));

    expect(_rewind(tree, 0), true);
    for (int i = 1; i < 4; i++) {
      _assertAppend(tree, i, RetentionEphemeral());
    }
    _assertAppend(tree, 4, RetentionMarked());
    for (int i = 5; i < 8; i++) {
      _assertAppend(tree, i, RetentionEphemeral());
    }
    _checkpoint(tree, 2);
    expect(
        CompareUtils.iterableIsEqual(_witness(tree, LeafPosition(0), 0), [
          StringHashable.fromU64(1),
          hashable.combineAll(1, [2, 3]),
          hashable.combineAll(2, [4, 5, 6, 7]),
          hashable.emptyRoot(TreeLevel(3)),
        ]),
        true);
  }
  {
    final tree = newTree(100);

    _assertAppend(tree, 0, RetentionEphemeral());
    _assertAppend(tree, 1, RetentionEphemeral());
    _assertAppend(tree, 2, RetentionMarked());
    _assertAppend(tree, 3, RetentionEphemeral());
    _assertAppend(tree, 4, RetentionEphemeral());
    _assertAppend(tree, 5, RetentionEphemeral());
    _assertAppend(
      tree,
      6,
      RetentionCheckpoint(
        id: 1,
        marking: MarkingState.marked,
      ),
    );
    _assertAppend(tree, 7, RetentionEphemeral());

    expect(_rewind(tree, 0), true);

    expect(
        CompareUtils.iterableIsEqual(
          _witness(tree, LeafPosition(2), 0),
          [
            StringHashable.fromU64(3),
            hashable.combineAll(1, [0, 1]),
            hashable.combineAll(2, [4, 5, 6]),
            hashable.emptyRoot(TreeLevel(3)),
          ],
        ),
        true);
  }
  {
    final tree = newTree(100);

    // Append 0..11 as Ephemeral
    for (int i = 0; i < 12; i++) {
      _assertAppend(tree, i, RetentionEphemeral());
    }

    // Append marked and ephemeral nodes
    _assertAppend(tree, 12, RetentionMarked());
    _assertAppend(tree, 13, RetentionMarked());
    _assertAppend(tree, 14, RetentionEphemeral());
    _assertAppend(tree, 15, RetentionEphemeral());

    // Create checkpoint C::from_u64(0)
    _checkpoint(tree, 0);

    // Verify witness
    expect(
        CompareUtils.iterableIsEqual(
          _witness(tree, LeafPosition(12), 0),
          [
            StringHashable.fromU64(13),
            hashable.combineAll(1, [14, 15]),
            hashable.combineAll(2, [8, 9, 10, 11]),
            hashable.combineAll(3, [0, 1, 2, 3, 4, 5, 6, 7]),
          ],
        ),
        true);
  }
}

class SMerklerPath extends MerklePath<String> {
  SMerklerPath({required super.authPath, required super.position});
}

class TestShardTree extends ShardTree<String, int,
    MemoryShardStore<String, int>, SMerklerPath> {
  TestShardTree(
      {required super.store,
      required super.maxCheckpoints,
      required super.depth,
      required super.shardHeight});

  @override
  SMerklerPath toMerklePath(LeafPosition position, List<String> path) {
    return SMerklerPath(authPath: path, position: position);
  }
}

bool _rewind(
  ShardTree<String, int, MemoryShardStore<String, int>, SMerklerPath> tree,
  int checkpointDepth,
) {
  return tree.truncateToCheckpointDepth(checkpointDepth);
}

void _checkRootHashes() {
  {
    final tree = newTree(100);
    _asserRoot(tree, [], null);
    _assertAppend(tree, 0, RetentionEphemeral());
    _asserRoot(tree, [0], null);
    _assertAppend(tree, 1, RetentionEphemeral());
    _asserRoot(tree, [0, 1], null);
    _assertAppend(tree, 2, RetentionEphemeral());
    _asserRoot(tree, [0, 1, 2], null);
  }
  {
    final tree = newTree(100);
    _assertAppend(
        tree, 0, RetentionCheckpoint(marking: MarkingState.marked, id: 1));
    for (int i = 0; i < 3; i++) {
      _assertAppend(tree, 0, RetentionEphemeral());
    }
    _asserRoot(tree, [0, 0, 0, 0], null);
  }
}

void _append() {
  final tree = newTree(100);
  expect(tree.depth, 4);
  for (int i = 0; i < 16; i++) {
    _assertAppend(tree, i, RetentionEphemeral());
    expect(tree.maxLeafPosition(), LeafPosition(i));
  }
  expect(
      () => tree.append(
          value: StringHashable.fromU64(16), retention: RetentionEphemeral()),
      throwsA(isA<MerkleTreeException>()));
}

List<String>? _witness(
    TestShardTree tree, LeafPosition position, int checkpointDepth) {
  try {
    final r = tree.witnessAtCheckpointDepth(
        checkpointDepth: checkpointDepth, position: position);
    return r?.authPath;
  } on MerkleTreeException {
    return null;
  }
}

bool _checkpoint(
    ShardTree<String, int, MemoryShardStore<String, int>, SMerklerPath> tree,
    int checkpointDepth) {
  return tree.checkpoint(checkpointDepth);
}

void _assertAppend(
    ShardTree<String, int, MemoryShardStore<String, int>, SMerklerPath> tree,
    int value,
    Retention<int> v) {
  tree.append(value: StringHashable.fromU64(value), retention: v);
}

void _asserRoot(
    ShardTree<String, int, MemoryShardStore<String, int>, SMerklerPath> tree,
    List<int> values,
    int? checkpoint) {
  final result = tree.rootAtCheckpointDepth(checkpointDepth: checkpoint);
  expect(result, StringHashable().combineAll(tree.depth, values));
}

TestShardTree newTree(int size) => TestShardTree(
    store: MemoryShardStore.empty(hashable),
    maxCheckpoints: size,
    depth: 4,
    shardHeight: 3);

void _witnessWithPrunedSubtrees() {
  final tree = TestShardTree(
      store: MemoryShardStore.empty(hashable),
      maxCheckpoints: 100,
      depth: 6,
      shardHeight: 3);
  final shardRootLevel = TreeLevel(3);
  for (int i = 0; i < 4; i++) {
    final r = i == 3 ? "abcdefgh" : i.toString();
    tree.insert(
        rootAddr: NodeAddress(level: shardRootLevel, index: i), value: r);
    // print(tree.store.getShard(NodeAddress(level: shardRootLevel, index: i)));
  }

  tree.batchInsert(
      start: LeafPosition(24),
      values: [
        "a",
        "b",
        "c",
        "d",
        "e",
        "f",
        "g",
        "h",
      ]
          .map((e) => (
                e,
                switch (e) {
                  "c" => RetentionMarked<int>(),
                  "h" => RetentionCheckpoint(marking: MarkingState.none, id: 3),
                  _ => RetentionEphemeral<int>()
                }
              ))
          .toList());
  final wintess = tree.witnessAtCheckpointDepth(
      position: LeafPosition(26), checkpointDepth: 0);
  expect(
      CompareUtils.iterableIsEqual(wintess?.authPath,
          ["d", "ab", "efgh", "2", "01", "________________________________"]),
      true);
}

void _checkShardSizes() {
  final tree = TestShardTree(
      store: MemoryShardStore.empty(hashable),
      maxCheckpoints: 100,
      depth: 4,
      shardHeight: 2);
  for (final i in [
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o"
  ]) {
    tree.append(value: i, retention: RetentionEphemeral());
  }
  expect(tree.store.getShardRoots().length, 4);
  expect(
      tree.store
          .getShard(NodeAddress(level: TreeLevel(2), index: 3))
          ?.maxPosition(),
      LeafPosition(14));
}

void _insert() {
  final tree = TestShardTree(
      store: MemoryShardStore.empty(hashable),
      maxCheckpoints: 100,
      depth: 4,
      shardHeight: 3);
  {
    final r = tree.batchInsert(start: LeafPosition(1), values: [
      ("b", RetentionCheckpoint(marking: MarkingState.none, id: 1)),
      ("c", RetentionEphemeral()),
      ("d", RetentionMarked()),
    ]);
    expect(
        r?.maxInsert == LeafPosition(3) &&
            CompareUtils.iterableIsEqual(r?.incomplete, [
              IncompleteNodeInfo(
                  address: NodeAddress(level: TreeLevel.zero, index: 0),
                  requiredForWitness: true),
              IncompleteNodeInfo(
                  address: NodeAddress(level: TreeLevel(2), index: 1),
                  requiredForWitness: true)
            ]),
        true);
  }
  // expect(tree.rootAtCheckpointDepth(checkpointDepth: 0).isErr);
  {
    final r = tree.batchInsert(
        start: LeafPosition(0), values: [("a", RetentionEphemeral())]);
    expect(r != null && r.maxInsert == LeafPosition(0) && r.incomplete.isEmpty,
        true);
  }
  {
    final r = tree.rootAtCheckpointDepth();
    expect(r, "abcd____________");
  }
  {
    final r = tree.rootAtCheckpointDepth(checkpointDepth: 0);
    expect(r, "ab______________");
  }
  {
    final r = tree.batchInsert(start: LeafPosition(10), values: [
      ("k", RetentionEphemeral()),
      ("l", RetentionCheckpoint(marking: MarkingState.none, id: 2)),
      ("m", RetentionEphemeral()),
    ]);
    expect(
        r?.maxInsert == LeafPosition(12) &&
            CompareUtils.iterableIsEqual(r?.incomplete, [
              IncompleteNodeInfo(
                  address: NodeAddress(level: TreeLevel.zero, index: 13),
                  requiredForWitness: false),
              IncompleteNodeInfo(
                  address: NodeAddress(level: TreeLevel(1), index: 7),
                  requiredForWitness: false),
              IncompleteNodeInfo(
                  address: NodeAddress(level: TreeLevel(1), index: 4),
                  requiredForWitness: false),
            ]),
        true);
  }
  // return;
  {
    expect(() => tree.rootAtCheckpointDepth(),
        throwsA(isA<MerkleTreeException>()));
  }
  {
    final r = tree.truncateToCheckpointDepth(0);
    expect(r, true);
  }
  {
    tree.batchInsert(
        start: LeafPosition(4),
        values: ["e", "f", "g", "h", "i", "j"].map((e) {
          return (e, RetentionEphemeral<int>());
        }).toList());
  }
  // return;
  expect(tree.rootAtCheckpointDepth(), "abcdefghijkl____");
  expect(tree.rootAtCheckpointDepth(checkpointDepth: 1), "ab______________");
}
