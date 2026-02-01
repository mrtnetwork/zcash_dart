import 'package:test/test.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';

void main() {
  test(
    "Node Addres",
    () {
      addressISaplingAnchor();
      addressPositionRange();
      addressAbovePosition();
      addressChildren();
      context();
      testCommonAncestor();
      testPositionIsCompleteSubtree();
    },
  );
}

void context() {
  {
    final r = NodeAddress(level: TreeLevel(3), index: 1).getContext(
      level: TreeLevel.zero,
      right: (position) => position,
      left: (addr) {},
    );
    expect(r, LeafPositionRange(start: LeafPosition(8), end: LeafPosition(16)));
  }
  {
    final r = NodeAddress(level: TreeLevel(3), index: 4).getContext(
      level: TreeLevel(5),
      left: (addr) => addr,
      right: (position) => position,
    );
    expect(r, NodeAddress(level: TreeLevel(5), index: 1));
  }
}

void addressChildren() {
  expect(() => NodeAddress(level: TreeLevel.zero, index: 1).children(),
      throwsA(isA<MerkleTreeException>()));
  expect(NodeAddress(level: TreeLevel(3), index: 1).children(), (
    NodeAddress(level: TreeLevel(2), index: 2),
    NodeAddress(level: TreeLevel(2), index: 3)
  ));
}

void addressAbovePosition() {
  expect(
      NodeAddress.abovePosition(level: TreeLevel(3), position: LeafPosition(9)),
      NodeAddress(level: TreeLevel(3), index: 1));
}

void addressPositionRange() {
  expect(NodeAddress(level: TreeLevel.zero, index: 0).positionRange(),
      LeafPositionRange(start: LeafPosition(0), end: LeafPosition(1)));

  expect(NodeAddress(level: TreeLevel(1), index: 0).positionRange(),
      LeafPositionRange(start: LeafPosition(0), end: LeafPosition(2)));

  expect(NodeAddress(level: TreeLevel(2), index: 1).positionRange(),
      LeafPositionRange(start: LeafPosition(4), end: LeafPosition(8)));
}

void addressISaplingAnchor() {
  final l0 = TreeLevel.zero;
  final l1 = TreeLevel(1);
  expect(
      NodeAddress(level: l1, index: 0)
          .iSaplingAnchorOf(NodeAddress(level: l0, index: 0)),
      true);
  expect(
      NodeAddress(level: l1, index: 0)
          .iSaplingAnchorOf(NodeAddress(level: l0, index: 1)),
      true);
  expect(
      !NodeAddress(level: l1, index: 0)
          .iSaplingAnchorOf(NodeAddress(level: l0, index: 2)),
      true);
}

void testCommonAncestor() {
  // Test cases
  expect(
    NodeAddress(level: TreeLevel(2), index: 1)
        .commonAncestor(NodeAddress(level: TreeLevel(3), index: 2)),
    NodeAddress(level: TreeLevel(5), index: 0),
  );

  expect(
    NodeAddress(level: TreeLevel(2), index: 2)
        .commonAncestor(NodeAddress(level: TreeLevel(1), index: 7)),
    NodeAddress(level: TreeLevel(3), index: 1),
  );

  expect(
    NodeAddress(level: TreeLevel(2), index: 2)
        .commonAncestor(NodeAddress(level: TreeLevel(1), index: 6)),
    NodeAddress(level: TreeLevel(3), index: 1),
  );

  expect(
    NodeAddress(level: TreeLevel(2), index: 2)
        .commonAncestor(NodeAddress(level: TreeLevel(2), index: 2)),
    NodeAddress(level: TreeLevel(2), index: 2),
  );

  expect(
    NodeAddress(level: TreeLevel(2), index: 2)
        .commonAncestor(NodeAddress(level: TreeLevel.zero, index: 9)),
    NodeAddress(level: TreeLevel(2), index: 2),
  );

  expect(
    NodeAddress(level: TreeLevel.zero, index: 9)
        .commonAncestor(NodeAddress(level: TreeLevel(2), index: 2)),
    NodeAddress(level: TreeLevel(2), index: 2),
  );

  expect(
    NodeAddress(level: TreeLevel.zero, index: 12)
        .commonAncestor(NodeAddress(level: TreeLevel.zero, index: 15)),
    NodeAddress(level: TreeLevel(2), index: 3),
  );

  expect(
    NodeAddress(level: TreeLevel.zero, index: 13)
        .commonAncestor(NodeAddress(level: TreeLevel.zero, index: 15)),
    NodeAddress(level: TreeLevel(2), index: 3),
  );

  expect(
    NodeAddress(level: TreeLevel.zero, index: 13)
        .commonAncestor(NodeAddress(level: TreeLevel.zero, index: 14)),
    NodeAddress(level: TreeLevel(2), index: 3),
  );

  expect(
    NodeAddress(level: TreeLevel.zero, index: 14)
        .commonAncestor(NodeAddress(level: TreeLevel.zero, index: 15)),
    NodeAddress(level: TreeLevel(1), index: 7),
  );

  expect(
    NodeAddress(level: TreeLevel.zero, index: 15)
        .commonAncestor(NodeAddress(level: TreeLevel.zero, index: 16)),
    NodeAddress(level: TreeLevel(5), index: 0),
  );
}

void testPositionIsCompleteSubtree() {
  expect(LeafPosition(0).isCompleteSubtree(TreeLevel.zero), true);
  expect(LeafPosition(1).isCompleteSubtree(TreeLevel(1)), true);
  expect(LeafPosition(2).isCompleteSubtree(TreeLevel(1)), false);
  expect(LeafPosition(2).isCompleteSubtree(TreeLevel(2)), false);
  expect(LeafPosition(3).isCompleteSubtree(TreeLevel(2)), true);
  expect(LeafPosition(4).isCompleteSubtree(TreeLevel(2)), false);
  expect(LeafPosition(7).isCompleteSubtree(TreeLevel(3)), true);
  expect(LeafPosition(0xFFFFFFFF).isCompleteSubtree(TreeLevel(32)), true);
}
