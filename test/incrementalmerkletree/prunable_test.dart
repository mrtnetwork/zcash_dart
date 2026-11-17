import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'types.dart';

import '../utils.dart';

void prunableTest() {
  test("prunable tree", () {
    _witness();
    _locatedInsertSubtree();
    _mergeCheckedFlag();
    _mergeChecked();
    _prune();
    _markedPosition();
    _rootHash();
  });
}

void incrementalmerkletreePrunableTest() {
  ZcashTestApi.runTest(prunableTest, "Prunable");
}

void main() {
  ZcashTestApi.runTest(incrementalmerkletreePrunableTest, "Prunable");
}

void _witness() {
  final t = LocatedPrunableTree<SerialzableString>(
    rootAddr: NodeAddress(level: TreeLevel(3), index: 0),
    root: parent(
      left: leaf("abcd".toSerializable(), RetentionFlags.ephemeral),
      right: parent(
        left: parent(
          left: leaf("e".toSerializable(), RetentionFlags.marked),
          right: leaf("f".toSerializable(), RetentionFlags.ephemeral),
        ),
        right: leaf("gh".toSerializable(), RetentionFlags.ephemeral),
      ),
    ),
  );
  {
    final witness = t.witness(
      position: LeafPosition(4),
      truncateAt: LeafPosition(8),
    );
    expect(witness, [
      "f".toSerializable(),
      "gh".toSerializable(),
      "abcd".toSerializable(),
    ]);
  }
  {
    final witness = t.witness(
      position: LeafPosition(4),
      truncateAt: LeafPosition(6),
    );
    expect(witness, [
      "f".toSerializable(),
      "__".toSerializable(),
      "abcd".toSerializable(),
    ]);
  }
  {
    // final witness =
    //     t.witness(position: LeafPosition(4), truncateAt: LeafPosition(7));
    // assert(witness
    //         .err()
    //         ?.message
    //         .contains(NodeAddress(level: TreeLevel(1), index: 3).toString()) ??
    //     false);
  }
}

void _locatedInsertSubtree() {
  final t = LocatedPrunableTree<SerialzableString>(
    rootAddr: NodeAddress(level: TreeLevel(3), index: 1),
    root: parent(
      left: leaf("abcd".toSerializable(), RetentionFlags.ephemeral),
      right: parent(
        left: nil(),
        right: leaf("gh".toSerializable(), RetentionFlags.ephemeral),
      ),
    ),
  );
  {
    final insert = t.insertSubtree(
      subtree: LocatedPrunableTree(
        root: parent(
          left: leaf("e".toSerializable(), RetentionFlags.marked),
          right: nil(),
        ),
        rootAddr: NodeAddress(level: TreeLevel(1), index: 6),
      ),
      containsMarked: true,
    );
    final e = LocatedPrunableTree(
      rootAddr: NodeAddress(level: TreeLevel(3), index: 1),
      root: parent(
        left: leaf("abcd".toSerializable(), RetentionFlags.ephemeral),
        right: parent(
          left: parent(
            left: leaf("e".toSerializable(), RetentionFlags.marked),
            right: nil(),
          ),
          right: leaf("gh".toSerializable(), RetentionFlags.ephemeral),
        ),
      ),
    );
    expect(insert.subtree, e);
    final t2 = LocatedPrunableTree<SerialzableString>(
      rootAddr: NodeAddress(level: TreeLevel(2), index: 1),
      root: parent(
        left: leaf("a".toSerializable(), RetentionFlags.marked),
        right: nil(),
      ),
    );
    expect(
      () => t2.insertSubtree(
        subtree: LocatedPrunableTree<SerialzableString>(
          rootAddr: NodeAddress(level: TreeLevel(1), index: 2),
          root: leaf("b".toSerializable(), RetentionFlags.ephemeral),
        ),
        containsMarked: false,
      ),
      throwsA(isA<BuError>()),
    );
    // assert(t2
    //         .insertSubtree(
    //             subtree: LocatedPrunableTree<String>(
    //                 rootAddr: NodeAddress(level: TreeLevel(1), index: 2),
    //                 root: leaf("b", RetentionFlags.ephemeral)),
    //             containsMarked: false)
    //         .err()
    //         ?.message
    //         .contains(NodeAddress(level: TreeLevel(1), index: 2).toString()) ??
    //     false);
  }
}

void _mergeCheckedFlag() {
  final t0 = leaf("a".toSerializable(), RetentionFlags.ephemeral);
  final t1 = leaf("a".toSerializable(), RetentionFlags.marked);
  final t2 = leaf("a".toSerializable(), RetentionFlags.checkpoint);
  expect(
    t0.mergeChecked(
      rootAddr: NodeAddress(level: TreeLevel(1), index: 0),
      other: t1,
    ),
    t1,
  );
  expect(
    t1.mergeChecked(
      rootAddr: NodeAddress(level: TreeLevel(1), index: 0),
      other: t2,
    ),
    leaf(
      "a".toSerializable(),
      RetentionFlags.marked | RetentionFlags.checkpoint,
    ),
  );
}

void _mergeChecked() {
  final t0 = parent(
    left: leaf("a".toSerializable(), RetentionFlags.ephemeral),
    right: nil(),
  );
  final t1 = parent(
    right: leaf("b".toSerializable(), RetentionFlags.ephemeral),
    left: nil(),
  );
  {
    final r = t0.mergeChecked(
      rootAddr: NodeAddress(level: TreeLevel(1), index: 0),
      other: t1,
    );
    expect(r, leaf("ab".toSerializable(), RetentionFlags.ephemeral));
  }
  final t2 = parent(
    left: leaf("c".toSerializable(), RetentionFlags.ephemeral),
    right: nil(),
  );
  {
    expect(
      () => t0.mergeChecked(
        rootAddr: NodeAddress(level: TreeLevel(1), index: 0),
        other: t2,
      ),
      throwsA(isA<BuError>()),
    );
  }
  final t3 = parent(left: t0, right: t2);
  final t4 = parent(left: t1, right: t1);
  expect(
    t3.mergeChecked(
      rootAddr: NodeAddress(level: TreeLevel(2), index: 0),
      other: t4,
    ),
    leaf("abcb".toSerializable(), RetentionFlags.ephemeral),
  );
}

void _prune() {
  final t = parent(
    left: leaf("a".toSerializable(), RetentionFlags.ephemeral),
    right: leaf("b".toSerializable(), RetentionFlags.ephemeral),
  );
  expect(
    t.prune(TreeLevel(1)),
    leaf("ab".toSerializable(), RetentionFlags.ephemeral),
  );
  final t0 = parent(
    left: leaf("c".toSerializable(), RetentionFlags.marked),
    right: t,
  );
  expect(
    t0.prune(TreeLevel(2)),
    parent(
      left: leaf("c".toSerializable(), RetentionFlags.marked),
      right: leaf("ab".toSerializable(), RetentionFlags.ephemeral),
    ),
  );
}

void _markedPosition() {
  final t = parent(
    left: leaf("a".toSerializable(), RetentionFlags.ephemeral),
    right: leaf("b".toSerializable(), RetentionFlags.marked),
  );
  {
    final r = t.markedPositions(NodeAddress(level: TreeLevel(1), index: 0));
    expect(CompareUtils.iterableIsEqual(r, {LeafPosition(1)}), true);
  }
  {
    final t0 = parent(left: t, right: t);
    final r = t0.markedPositions(NodeAddress(level: TreeLevel(2), index: 1));
    expect(
      CompareUtils.iterableIsEqual(r, {LeafPosition(5), LeafPosition(7)}),
      true,
    );
  }
}

void _rootHash() {
  final t = parent(
    left: leaf("a".toSerializable(), RetentionFlags.ephemeral),
    right: leaf("b".toSerializable(), RetentionFlags.ephemeral),
  );
  {
    final r = t.rootHash(
      rootAddr: NodeAddress(level: TreeLevel(1), index: 0),
      truncateAt: LeafPosition(2),
    );
    expect(r.ok(), "ab".toSerializable());
  }
  {
    final t0 = parent(left: nil(), right: t).rootHash(
      rootAddr: NodeAddress(level: TreeLevel(2), index: 0),
      truncateAt: LeafPosition(4),
    );
    expect(t0.err()?.first, NodeAddress(level: TreeLevel(1), index: 0));
    // assert(r.err()?.first == NodeAddress(level: TreeLevel(1), index: 0));
  }
  {
    final t1 = parent(left: t, right: nil());
    {
      final r = t1.rootHash(
        rootAddr: NodeAddress(level: TreeLevel(2), index: 0),
        truncateAt: LeafPosition(2),
      );
      expect(r.ok(), "ab__".toSerializable());
    }
    {
      final hash = t1.rootHash(
        rootAddr: NodeAddress(level: TreeLevel(2), index: 0),
        truncateAt: LeafPosition(3),
      );
      expect(hash.err()?.first, NodeAddress(level: TreeLevel(1), index: 1));
    }
  }
}
