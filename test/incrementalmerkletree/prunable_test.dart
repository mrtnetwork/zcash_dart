import 'package:blockchain_utils/utils/compare/compare.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'types.dart';

void main() {
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

void _witness() {
  final t = LocatedPrunableTree<String>(
      rootAddr: NodeAddress(level: TreeLevel(3), index: 0),
      root: parent(
        left: leaf("abcd", RetentionFlags.ephemeral),
        right: parent(
          left: parent(
            left: leaf("e", RetentionFlags.marked),
            right: leaf("f", RetentionFlags.ephemeral),
          ),
          right: leaf("gh", RetentionFlags.ephemeral),
        ),
      ));
  {
    final witness =
        t.witness(position: LeafPosition(4), truncateAt: LeafPosition(8));
    expect(witness, ["f", "gh", "abcd"]);
  }
  {
    final witness =
        t.witness(position: LeafPosition(4), truncateAt: LeafPosition(6));
    expect(witness, ["f", "__", "abcd"]);
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
  final t = LocatedPrunableTree<String>(
      rootAddr: NodeAddress(level: TreeLevel(3), index: 1),
      root: parent(
          left: leaf("abcd", RetentionFlags.ephemeral),
          right: parent(
              left: nil(), right: leaf("gh", RetentionFlags.ephemeral))));
  {
    final insert = t.insertSubtree(
        subtree: LocatedPrunableTree(
            root: parent(left: leaf("e", RetentionFlags.marked), right: nil()),
            rootAddr: NodeAddress(level: TreeLevel(1), index: 6)),
        containsMarked: true);
    final e = LocatedPrunableTree(
        rootAddr: NodeAddress(level: TreeLevel(3), index: 1),
        root: parent(
            left: leaf("abcd", RetentionFlags.ephemeral),
            right: parent(
                left: parent(
                    left: leaf("e", RetentionFlags.marked), right: nil()),
                right: leaf("gh", RetentionFlags.ephemeral))));
    expect(insert.subtree, e);
    final t2 = LocatedPrunableTree<String>(
        rootAddr: NodeAddress(level: TreeLevel(2), index: 1),
        root: parent(left: leaf("a", RetentionFlags.marked), right: nil()));
    expect(
        () => t2.insertSubtree(
            subtree: LocatedPrunableTree<String>(
                rootAddr: NodeAddress(level: TreeLevel(1), index: 2),
                root: leaf("b", RetentionFlags.ephemeral)),
            containsMarked: false),
        throwsA(isA<MerkleTreeException>()));
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
  final t0 = leaf("a", RetentionFlags.ephemeral);
  final t1 = leaf("a", RetentionFlags.marked);
  final t2 = leaf("a", RetentionFlags.checkpoint);
  expect(
      t0.mergeChecked(
          rootAddr: NodeAddress(level: TreeLevel(1), index: 0), other: t1),
      t1);
  expect(
      t1.mergeChecked(
          rootAddr: NodeAddress(level: TreeLevel(1), index: 0), other: t2),
      leaf("a", RetentionFlags.marked | RetentionFlags.checkpoint));
}

void _mergeChecked() {
  final t0 = parent(left: leaf("a", RetentionFlags.ephemeral), right: nil());
  final t1 = parent(right: leaf("b", RetentionFlags.ephemeral), left: nil());
  {
    final r = t0.mergeChecked(
        rootAddr: NodeAddress(level: TreeLevel(1), index: 0), other: t1);
    expect(r, leaf("ab", RetentionFlags.ephemeral));
  }
  final t2 = parent(left: leaf("c", RetentionFlags.ephemeral), right: nil());
  {
    expect(
        () => t0.mergeChecked(
            rootAddr: NodeAddress(level: TreeLevel(1), index: 0), other: t2),
        throwsA(isA<MerkleTreeException>()));
  }
  final t3 = parent(left: t0, right: t2);
  final t4 = parent(left: t1, right: t1);
  expect(
      t3.mergeChecked(
          rootAddr: NodeAddress(level: TreeLevel(2), index: 0), other: t4),
      leaf("abcb", RetentionFlags.ephemeral));
}

void _prune() {
  final t = parent(
      left: leaf("a", RetentionFlags.ephemeral),
      right: leaf("b", RetentionFlags.ephemeral));
  expect(t.prune(TreeLevel(1)), leaf("ab", RetentionFlags.ephemeral));
  final t0 = parent(left: leaf("c", RetentionFlags.marked), right: t);
  expect(
      t0.prune(TreeLevel(2)),
      parent(
          left: leaf("c", RetentionFlags.marked),
          right: leaf("ab", RetentionFlags.ephemeral)));
}

void _markedPosition() {
  final t = parent(
      left: leaf("a", RetentionFlags.ephemeral),
      right: leaf("b", RetentionFlags.marked));
  {
    final r = t.markedPositions(NodeAddress(level: TreeLevel(1), index: 0));
    expect(CompareUtils.iterableIsEqual(r, {LeafPosition(1)}), true);
  }
  {
    final t0 = parent(left: t, right: t);
    final r = t0.markedPositions(NodeAddress(level: TreeLevel(2), index: 1));
    expect(CompareUtils.iterableIsEqual(r, {LeafPosition(5), LeafPosition(7)}),
        true);
  }
}

void _rootHash() {
  final t = parent(
      left: leaf("a", RetentionFlags.ephemeral),
      right: leaf("b", RetentionFlags.ephemeral));
  {
    final r = t.rootHash(
        rootAddr: NodeAddress(level: TreeLevel(1), index: 0),
        truncateAt: LeafPosition(2));
    expect(r, "ab");
  }
  {
    final t0 = parent(left: nil(), right: t);
    expect(
        () => t0.rootHash(
            rootAddr: NodeAddress(level: TreeLevel(2), index: 0),
            truncateAt: LeafPosition(4)),
        throwsA(isA<MerkleTreeException>()));
    // assert(r.err()?.first == NodeAddress(level: TreeLevel(1), index: 0));
  }
  {
    final t1 = parent(left: t, right: nil());
    {
      final r = t1.rootHash(
          rootAddr: NodeAddress(level: TreeLevel(2), index: 0),
          truncateAt: LeafPosition(2));
      expect(r, "ab__");
    }
    {
      expect(
          () => t1.rootHash(
              rootAddr: NodeAddress(level: TreeLevel(2), index: 0),
              truncateAt: LeafPosition(3)),
          throwsA(isA<MerkleTreeException>()));
      // assert(r.err()?.first == NodeAddress(level: TreeLevel(1), index: 1));
    }
  }
}
