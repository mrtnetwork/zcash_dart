import 'dart:collection';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

/// Represents a leaf position in a tree, supporting equality and ordering.
class LeafPosition with Equality implements Comparable<LeafPosition> {
  final int position;
  LeafPosition(int position) : position = position.asPositive;

  bool isRightChild() => (position & 1) == 1;

  /// Addition operator: Adds a given BigInt to this position
  LeafPosition operator +(int other) {
    return LeafPosition(position + other);
  }

  /// Subtraction operator: Subtracts a given BigInt from this position
  LeafPosition operator -(int other) {
    return LeafPosition(position - other);
  }

  /// Comparison operators
  bool operator <(LeafPosition other) => position < other.position;
  bool operator <=(LeafPosition other) => position <= other.position;
  bool operator >(LeafPosition other) => position > other.position;
  bool operator >=(LeafPosition other) => position >= other.position;

  bool isCompleteSubtree(TreeLevel rootLevel) {
    for (int l = 0; l < rootLevel.value; l++) {
      if ((position & (1 << l)) == 0) {
        return false;
      }
    }
    return true;
  }

  /// Returns the minimum possible level of the root of a binary tree containing at least
  /// `self + 1` leaves.
  TreeLevel rootLevel() {
    // Dart int is arbitrary precision, but we assume 64-bit for this calculation
    final int bits = 64;

    // leading zeros = number of bits from MSB to first 1
    int leadingZeros = bits - position.bitLength;

    int rootLevel = bits - leadingZeros;

    return TreeLevel(rootLevel);
  }

  int pastOmmerCount() {
    int count = 0;
    final rootLevel = this.rootLevel().value;

    for (int i = 0; i < rootLevel; i++) {
      if (((position >> i) & 0x1) == 1) {
        count++;
      }
    }

    return count;
  }

  @override
  int compareTo(LeafPosition other) {
    return position.compareTo(other.position);
  }

  @override
  String toString() {
    return "LeafPosition($position)";
  }

  @override
  List<dynamic> get variables => [position];
}

/// Represents a tree level with comparable ordering and value equality.
class TreeLevel with Equality implements Comparable<TreeLevel> {
  final int value;

  // TreeLevel 0 corresponds to a leaf of the tree
  static const TreeLevel zero = TreeLevel._(0);

  const TreeLevel._(this.value);

  /// Comparison operators
  bool operator <(TreeLevel other) => value < other.value;
  bool operator <=(TreeLevel other) => value <= other.value;
  bool operator >(TreeLevel other) => value > other.value;
  bool operator >=(TreeLevel other) => value >= other.value;
  factory TreeLevel(int value) {
    return TreeLevel._(value.asU8);
  }

  /// Returns an iterable from this level up to [other], excluding [other]
  Iterable<TreeLevel> toList(TreeLevel other) sync* {
    for (var i = value; i < other.value; i++) {
      yield TreeLevel(i);
    }
  }

  // Addition operator
  TreeLevel operator +(int other) {
    var result = value + other;
    if (result > BinaryOps.mask8) {
      throw MerkleTreeException.failed(
        "TreeLevel.Addition",
        reason: 'Addition level failed. overflow.',
      );
    }
    return TreeLevel(result);
  }

  // Subtraction operator
  TreeLevel operator -(int other) {
    if (value < other) {
      throw MerkleTreeException.failed(
        "TreeLevel.Subtraction",
        reason: 'Subtraction level failed. overflow.',
      );
    }
    return TreeLevel(value - other);
  }

  bool isZero() => value == 0;
  @override
  int compareTo(TreeLevel other) => value.compareTo(other.value);

  @override
  String toString() => 'TreeLevel($value)';

  @override
  List<dynamic> get variables => [value];
}

/// Represents the address of a node with value-based equality.
class NodeAddress with Equality, LayoutSerializable, CborTagSerializable {
  final TreeLevel level;
  final int index;
  NodeAddress({required this.level, required int index})
    : index = index.asPositive;
  factory NodeAddress.fromPosition(LeafPosition p) {
    return NodeAddress(level: TreeLevel.zero, index: p.position);
  }

  factory NodeAddress.deserialize({List<int>? bytes, CborObject? object}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.nodeAddress,
      cborBytes: bytes,
      cborObject: object,
    );
    return NodeAddress(
      level: TreeLevel(values.rawValueAt(0)),
      index: values.rawValueAt(1),
    );
  }

  /// Returns the minimum value among the range of leaf positions
  LeafPosition positionRangeStart() {
    return LeafPosition(
      index << level.value,
    ); // level.0 in Rust → level.value in Dart
  }

  /// Returns the (exclusive) end of the range of leaf positions
  LeafPosition positionRangeEnd() {
    return LeafPosition((index + 1) << level.value);
  }

  /// Returns the maximum value among the range of leaf positions
  LeafPosition maxPosition() {
    return positionRangeEnd() - 1;
  }

  (NodeAddress, NodeAddress) children({MerkleTreeException? error}) {
    if (this.level == TreeLevel.zero) {
      throw error ??
          MerkleTreeException.failed(
            "NodeAddress.children",
            reason: 'Zero level does not have any children.',
          );
    }
    final level = TreeLevel(this.level.value - 1);
    final index = this.index << 1;
    final left = NodeAddress(level: level, index: index);
    final right = NodeAddress(level: level, index: index + 1);
    return (left, right);
  }

  LeafPositionRange positionRange() {
    return LeafPositionRange(
      start: positionRangeStart(),
      end: positionRangeEnd(),
    );
  }

  NodeAddress sibling() {
    return NodeAddress(level: level, index: index ^ 1);
  }

  NodeAddress nextAtLevel() {
    return NodeAddress(level: level, index: index + 1);
  }

  NodeAddress parent() {
    return NodeAddress(level: TreeLevel(level.value + 1), index: index >> 1);
  }

  factory NodeAddress.abovePosition({
    required TreeLevel level,
    required LeafPosition position,
  }) {
    return NodeAddress(level: level, index: position.position >> level.value);
  }

  factory NodeAddress.deserializeJson(Map<String, dynamic> json) {
    return NodeAddress(
      level: TreeLevel(json.valueAsInt("level")),
      index: json.valueAsInt("index"),
    );
  }
  bool isRightChild() {
    return (index & 1) == 1;
  }

  bool isLeftChild() {
    return (index & 1) == 0;
  }

  bool iSaplingAnchorOf(NodeAddress addr) {
    return level > addr.level &&
        (addr.index >> (level.value - addr.level.value)) == index;
  }

  bool contains(NodeAddress addr) {
    return this == addr || iSaplingAnchorOf(addr);
  }

  NodeAddress commonAncestor(NodeAddress other) {
    // Order nodes by level
    final higher = level.value >= other.level.value ? this : other;
    final lower = level.value >= other.level.value ? other : this;

    // Lift the lower node to the same level
    final levelDiff = higher.level.value - lower.level.value;
    final lowerAncestorIndex = lower.index >> levelDiff;

    // XOR distance
    final indexDelta = higher.index ^ lowerAncestorIndex;

    // Equivalent to: u64::BITS - leading_zeros
    // In Dart: bitLength gives position of highest set bit + 1
    final levelDelta = indexDelta == 0 ? 0 : indexDelta.bitLength;

    return NodeAddress(
      level: higher.level + levelDelta,
      index:
          (higher.index > lowerAncestorIndex
              ? higher.index
              : lowerAncestorIndex) >>
          levelDelta,
    );
  }

  T getContext<T extends Object?>({
    required TreeLevel level,
    required T Function(NodeAddress addr) left,
    required T Function(LeafPositionRange position) right,
  }) {
    if (level >= this.level) {
      return left(
        NodeAddress(
          level: level,
          index: index >> (level - this.level.value).value,
        ),
      );
    }
    final int shift = this.level.value - level.value;
    return right(
      LeafPositionRange(
        start: LeafPosition(index << shift),
        end: LeafPosition((index + 1) << shift),
      ),
    );
  }

  @override
  String toString() {
    return "NodeAddress { level: $level, index: $index }";
  }

  @override
  List<dynamic> get variables => [level, index];

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "level"),
      LayoutConst.lebU64(property: "index"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"level": level.value, "index": BigInt.from(index)};
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.nodeAddress;

  @override
  List<CborObject?> get serializationItems => [
    level.value.toCbor(),
    index.toCbor(),
  ];
}

/// Abstract base for a Merkle path, supporting value-based equality.
abstract class MerklePath<H extends MerkleNodeValue> with Equality {
  final List<H> authPath;
  final LeafPosition position;
  const MerklePath({required this.authPath, required this.position});

  @override
  List<dynamic> get variables => [authPath, position];
}

enum MarkingState {
  marked(0),
  reference(1),
  none(2);

  final int value;
  const MarkingState(this.value);
  static MarkingState fromValue(int? value) => values.firstWhere(
    (e) => e.value == value,
    orElse: () => throw ItemNotFoundException(value: value),
  );
}

enum RetentionType {
  ephemeral(0),
  checkpoint(1),
  marked(2),
  reference(3);

  final int value;
  const RetentionType(this.value);
  static RetentionType fromValue(int? value) => values.firstWhere(
    (e) => e.value == value,
    orElse: () => throw ItemNotFoundException(value: value),
  );
}

sealed class Retention<C extends Object> with Equality {
  const Retention(this.type);
  bool get isCheckpoint => false;
  bool get isMarked => false;
  final RetentionType type;

  @override
  List<dynamic> get variables => [type];
}

class RetentionEphemeral<C extends Object> extends Retention<C> {
  RetentionEphemeral() : super(RetentionType.ephemeral);

  @override
  String toString() {
    return "RetentionEphemeral<$C>()";
  }
}

class RetentionCheckpoint<C extends Object> extends Retention<C> {
  final C id;
  final MarkingState marking;
  const RetentionCheckpoint({required this.marking, required this.id})
    : super(RetentionType.checkpoint);
  @override
  bool get isCheckpoint => true;
  @override
  bool get isMarked => marking == MarkingState.marked;

  @override
  List<dynamic> get variables => [type, id, marking];
  @override
  String toString() {
    return "RetentionCheckpoint<$C>($id, marking:${marking.name})";
  }
}

class RetentionMarked<C extends Object> extends Retention<C> {
  RetentionMarked() : super(RetentionType.marked);
  @override
  bool get isMarked => true;
  @override
  String toString() {
    return "RetentionMarked<$C>()";
  }
}

class RetentionReference<C extends Object> extends Retention<C> {
  RetentionReference() : super(RetentionType.reference);
  @override
  String toString() {
    return "RetentionReference<$C>()";
  }
}

abstract class MerkleNodeValue with LayoutSerializable, Equality {
  const MerkleNodeValue();
  List<int> toBytes();
}

abstract mixin class Hashable<HASH extends MerkleNodeValue> {
  HASH emptyLeaf();

  /// Combines two child nodes at the given level, producing a new node at level + 1.
  HASH combine({required TreeLevel level, required HASH a, required HASH b});

  /// Produces an empty root at the specified level by combining empty leaves.
  HASH emptyRoot(TreeLevel level) {
    HASH v = emptyLeaf();
    for (final lvl in TreeLevel.zero.toList(level)) {
      v = combine(level: lvl, a: v, b: v);
    }
    return v;
  }
}

class LeafPositionRange with Iterable<int>, Equality {
  final LeafPosition start;
  final LeafPosition end;
  LeafPositionRange({required this.start, required this.end});
  @override
  bool contains(Object? element) {
    return switch (element) {
      final int p => p >= start.position && p <= end.position,
      final LeafPosition l => containsPosition(l),
      _ => false,
    };
  }

  bool containsPosition(LeafPosition element) {
    return element >= start && element <= end;
  }

  @override
  Iterator<int> get iterator =>
      Iterable<int>.generate(
        end.position - start.position,
        (i) => start.position + i,
      ).iterator;

  @override
  List<dynamic> get variables => [start, end];

  @override
  String toString() {
    return "LeafPositionRange($start, $end)";
  }
}

class RetentionFlags with Equality {
  final int flag;
  const RetentionFlags._(this.flag);
  RetentionFlags(int flag) : flag = flag.asU8;
  static const RetentionFlags ephemeral = RetentionFlags._(0x00);
  static const RetentionFlags checkpoint = RetentionFlags._(0x01);
  static const RetentionFlags marked = RetentionFlags._(0x02);
  static const RetentionFlags reference = RetentionFlags._(0x04);
  bool hasFlag(RetentionFlags flag) => (this & flag) == flag;
  bool isCheckpoint() => hasFlag(checkpoint);
  bool isMarket() => hasFlag(marked);
  factory RetentionFlags.fromRetention(Retention retention) {
    return switch (retention) {
      final RetentionEphemeral _ => RetentionFlags.ephemeral,
      final RetentionCheckpoint c => switch (c.marking) {
        MarkingState.marked =>
          RetentionFlags.checkpoint | RetentionFlags.marked,
        MarkingState.reference =>
          RetentionFlags.checkpoint | RetentionFlags.reference,
        _ => checkpoint,
      },
      final RetentionMarked _ => marked,
      final RetentionReference _ => reference,
    };
  }
  bool get isEmpty => flag == 0;

  /// Bitwise OR
  RetentionFlags operator |(RetentionFlags other) =>
      RetentionFlags(flag | other.flag);

  /// Bitwise AND
  RetentionFlags operator &(RetentionFlags other) =>
      RetentionFlags(flag & other.flag);

  /// Bitwise XOR
  RetentionFlags operator ^(RetentionFlags other) =>
      RetentionFlags(flag ^ other.flag);

  /// Bitwise subtraction (Rust-style flag removal)
  RetentionFlags operator -(RetentionFlags other) =>
      RetentionFlags(flag & ~other.flag & BinaryOps.mask8);

  /// Bitwise NOT
  RetentionFlags operator ~() => RetentionFlags(~flag & BinaryOps.mask8);

  @override
  String toString() {
    return "RetentionFlags(${switch (flag) {
      0x00 => "ephemeral",
      0x01 => "checkpoint",
      0x02 => "marked",
      0x04 => "reference",
      _ => flag.toHexaDecimal,
    }})";
  }

  @override
  List<dynamic> get variables => [flag];
}

enum NodeType {
  parent(0),
  leaf(1),
  nil(2);

  final int value;
  const NodeType(this.value);
  static NodeType fromValue(int? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ItemNotFoundException(value: value, name: "NodeType"),
    );
  }

  static NodeType fromName(String? name) {
    return values.firstWhere(
      (e) => e.name == name,
      orElse: () => throw ItemNotFoundException(value: name, name: "NodeType"),
    );
  }
}

/// Abstract Node class with generic types A (annotation) and V (value)
sealed class Node<
  A extends Object?,
  V extends Object?,
  TREE extends Tree<A, V, TREE>
>
    with Equality {
  const Node();
  bool isNil() => tryAsNil() != null;
  bool isParent() => tryAsPrent() != null;
  bool isLeaf() => tryAsleef() != null;

  V? leafValue() => tryAsleef()?.value;
  A? annotation() => tryAsPrent()?.ann;

  NodeParent<A, V, TREE>? tryAsPrent() => null;
  NodeLeaf<A, V, TREE>? tryAsleef() => null;
  NodeNil<A, V, TREE>? tryAsNil() => null;
  Node<A, V, TREE> reannotate(A ann) => this;
  NodeType get type;

  T fold<T extends Object?>({
    required T Function(TREE left, TREE right, A ann) onParent,
    required T Function(V value) onLeaf,
    required T Function() onNil,
  }) {
    return switch (this) {
      final NodeParent<A, V, TREE> r => onParent(r.left, r.right, r.ann),
      final NodeLeaf<A, V, TREE> r => onLeaf(r.value),
      final NodeNil<A, V, TREE> _ => onNil(),
    };
  }
}

/// A parent node in the tree, with annotation `ann` and left/right children
class NodeParent<
  A extends Object?,
  V extends Object?,
  TREE extends Tree<A, V, TREE>
>
    extends Node<A, V, TREE> {
  final A ann;
  final TREE left;
  final TREE right;

  const NodeParent({
    required this.ann,
    required this.left,
    required this.right,
  });

  @override
  NodeParent<A, V, TREE> tryAsPrent() {
    return this;
  }

  @override
  Node<A, V, TREE> reannotate(A ann) {
    return NodeParent(ann: ann, left: left, right: right);
  }

  @override
  List<dynamic> get variables => [ann, left, right];

  @override
  String toString() {
    return "Parent($ann, left: $left, right: $right)";
  }

  @override
  NodeType get type => NodeType.parent;
}

/// A leaf node, containing a value
class NodeLeaf<
  A extends Object?,
  V extends Object?,
  TREE extends Tree<A, V, TREE>
>
    extends Node<A, V, TREE> {
  final V value;

  const NodeLeaf({required this.value});

  @override
  NodeLeaf<A, V, TREE>? tryAsleef() {
    return this;
  }

  @override
  String toString() {
    return "Leaf($value)";
  }

  @override
  List<dynamic> get variables => [value];

  @override
  NodeType get type => NodeType.leaf;
}

/// An empty node
class NodeNil<
  A extends Object?,
  V extends Object?,
  TREE extends Tree<A, V, TREE>
>
    extends Node<A, V, TREE> {
  const NodeNil();

  @override
  NodeNil<A, V, TREE>? tryAsNil() {
    return this;
  }

  @override
  List<dynamic> get variables => [];
  @override
  String toString() {
    return "Nil()";
  }

  @override
  NodeType get type => NodeType.nil;
}

/// An immutable binary tree wrapping a Node
abstract class Tree<
  A extends Object?,
  V extends Object?,
  TREE extends Tree<A, V, TREE>
>
    with Equality {
  final Node<A, V, TREE> node;

  const Tree(this.node);
  @override
  String toString() {
    return "Tree($node)";
  }
}

class LocatedTree<
  A extends Object?,
  V extends Object?,
  TREE extends Tree<A, V, TREE>
>
    with Equality {
  final NodeAddress rootAddr;
  final TREE root;
  const LocatedTree({required this.root, required this.rootAddr});

  @override
  List<dynamic> get variables => [rootAddr, root];
  @override
  String toString() {
    return "Tree($rootAddr,$root)";
  }
}

class IncompleteNodeInfo with Equality {
  final NodeAddress address;
  final bool requiredForWitness;
  const IncompleteNodeInfo({
    required this.address,
    required this.requiredForWitness,
  });

  @override
  String toString() {
    return "IncompleteNodeInfo{ address: $address, requiredForWitness: $requiredForWitness}";
  }

  @override
  List<dynamic> get variables => [address, requiredForWitness];
}

class TreeInsertReport<H extends MerkleNodeValue> {
  final LocatedPrunableTree<H> subtree;
  final List<IncompleteNodeInfo> incomplete;
  const TreeInsertReport({required this.subtree, required this.incomplete});
}

class TreeBatchInsertReport<
  H extends MerkleNodeValue,
  CHECKPOINT extends Object
> {
  final LocatedPrunableTree<H> subtree;
  final bool containsMarked;
  final List<IncompleteNodeInfo> incomplete;
  final LeafPosition maxInsertPosition;
  final SplayTreeMap<CHECKPOINT, LeafPosition> checkpoints;
  final Iterator<(H, Retention<CHECKPOINT>)>? remainder;
  const TreeBatchInsertReport({
    required this.subtree,
    required this.containsMarked,
    required this.incomplete,
    required this.maxInsertPosition,
    required this.checkpoints,
    required this.remainder,
  });
}

class TreeBatchResult {
  final LeafPosition maxInsert;
  final List<IncompleteNodeInfo> incomplete;
  const TreeBatchResult({required this.maxInsert, required this.incomplete});
}

class PrunableValue<H extends MerkleNodeValue> with Equality {
  final H value;
  final RetentionFlags flags;
  const PrunableValue({required this.value, required this.flags});
  @override
  String toString() {
    return "Value($value, $flags)";
  }

  @override
  List<dynamic> get variables => [value, flags];
}

class NonEmptyFrontier<H extends MerkleNodeValue>
    with LayoutSerializable, CborTagSerializable {
  final LeafPosition position;
  final H leaf;
  final List<H> ommers;
  NonEmptyFrontier({
    required this.position,
    required this.leaf,
    List<H> ommers = const [],
  }) : ommers = ommers.immutable;
  factory NonEmptyFrontier.deserialize({
    required H Function(List<int>) fromBytes,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.nonEmptyFrontier,
      cborBytes: bytes,
      cborObject: object,
    );
    return NonEmptyFrontier(
      position: LeafPosition(values.rawValueAt(0)),
      leaf: fromBytes(values.rawValueAt(1)),
      ommers:
          values
              .listAt<CborBytesValue>(2)
              .map((e) => fromBytes(e.value))
              .toList(),
    );
  }

  /// Constructs a new frontier from its constituent parts.
  factory NonEmptyFrontier.fromParts(
    LeafPosition position,
    H leaf,
    List<H> ommers,
  ) {
    final expectedOmmers = position.pastOmmerCount();
    if (ommers.length == expectedOmmers) {
      return NonEmptyFrontier(position: position, leaf: leaf, ommers: ommers);
    } else {
      throw MerkleFrontierError.failed(
        name: "NonEmptyFrontier.fromParts",
        reason: "Position mismatch.",
      );
    }
  }

  factory NonEmptyFrontier.deserializeJson({
    required Map<String, dynamic> json,
    required H Function(List<int>) fromBytes,
  }) {
    return NonEmptyFrontier(
      position: LeafPosition(json.valueAsInt("position")),
      leaf: fromBytes(json.valueAsBytes("leaf")),
      ommers:
          json.valueEnsureAsList<List<int>>("ommers").map(fromBytes).toList(),
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU64(property: "position"),
      LayoutConst.bcsBytes(property: "leaf"),
      LayoutConst.bcsVector(LayoutConst.bcsBytes(), property: "ommers"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "position": BigInt.from(position.position),
      "leaf": leaf.toBytes(),
      "ommers": ommers.map((e) => e.toBytes()).toList(),
    };
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.nonEmptyFrontier;

  @override
  List<CborObject?> get serializationItems => [
    position.position.toCbor(),
    CborBytesValue(leaf.toBytes()),
    CborTagSerializable.listFromDynamic(
      ommers.map((e) => CborBytesValue(e.toBytes())).toList(),
    ),
  ];
}

class Frontier<H extends MerkleNodeValue> {
  final NonEmptyFrontier<H>? frontier;
  const Frontier({this.frontier});
}

abstract class CommitmentTree<H extends MerkleNodeValue>
    with LayoutSerializable {
  final H? left;
  final H? right;
  final List<H?> parents;
  CommitmentTree({
    required this.left,
    required this.right,
    List<H?> parents = const [],
  }) : parents = parents.immutable;
  int get depth;

  /// Returns the number of leaf nodes in the tree.
  int size() {
    int acc;
    if (left == null && right == null) {
      acc = 0;
    } else if (left != null && right == null) {
      acc = 1;
    } else if (left != null && right != null) {
      acc = 2;
    } else {
      throw MerkleFrontierError.failed(
        name: "CommitmentTree.size",
        reason: 'Unreachable state.',
      );
    }

    for (var i = 0; i < parents.length; i++) {
      final p = parents[i];
      if (p != null) {
        acc += 1 << (i + 1);
      }
    }

    return acc;
  }

  Frontier<H> toFrontier() {
    if (size() == 0) {
      return Frontier();
    } else {
      final ommers = <H>[];
      for (final v in parents) {
        if (v != null) {
          ommers.add(v);
        }
      }

      late final H leaf;
      late final List<H> finalOmmers;

      if (left != null && right == null) {
        leaf = left as H;
        finalOmmers = ommers;
      } else if (left != null && right != null) {
        leaf = right as H;
        finalOmmers = [left as H, ...ommers];
      } else {
        throw MerkleFrontierError.failed(
          name: "toFrontier",
          reason: 'Unreachable state.',
        );
      }

      final frontier = NonEmptyFrontier.fromParts(
        LeafPosition(size() - 1),
        leaf,
        finalOmmers,
      );
      if (frontier.position.rootLevel() > TreeLevel(depth)) {
        throw MerkleFrontierError.failed(
          name: "toFrontier",
          reason: "max depth exceeded",
        );
      }
      // If a frontier cannot be successfully constructed from the
      // parts of a commitment tree, it is a programming error.
      return Frontier<H>(frontier: frontier);
    }
  }
}

class SerializableTreeShard<H extends MerkleNodeValue>
    with CborTagSerializable {
  final int index;
  final PrunableTree<H> tree;
  const SerializableTreeShard({required this.index, required this.tree});
  factory SerializableTreeShard.deserialize({
    required H Function(List<int> bytes) fromBytes,
    required Hashable<H> hashable,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.serialzableTreeShard,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableTreeShard(
      index: values.rawValueAt(0),
      tree: PrunableTree<H>.deserialize(
        hashContext: hashable,
        fromBytes: fromBytes,
        object: values.objectAt(1),
      ),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serialzableTreeShard;

  @override
  List<CborObject?> get serializationItems => [index.toCbor(), tree.toCbor()];
}

class SerializableShardTree<H extends MerkleNodeValue>
    with CborTagSerializable {
  final PrunableTree<H> cap;
  final List<SerializableTreeShard<H>> shards;
  final List<SerializableTreeCheckpoint> checkpionts;
  const SerializableShardTree({
    required this.cap,
    required this.shards,
    required this.checkpionts,
  });
  factory SerializableShardTree.deserialize({
    required Hashable<H> hashContext,
    required H Function(List<int> bytes) fromBytes,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.serialzableTree,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableShardTree(
      cap: PrunableTree.deserialize(
        hashContext: hashContext,
        fromBytes: fromBytes,
        object: values.objectAt(0),
      ),
      shards:
          values
              .listAt<CborTagValue>(1)
              .map(
                (e) => SerializableTreeShard.deserialize(
                  hashable: hashContext,
                  object: e,
                  fromBytes: fromBytes,
                ),
              )
              .toList(),
      checkpionts:
          values
              .listAt<CborTagValue>(2)
              .map((e) => SerializableTreeCheckpoint.deserialize(object: e))
              .toList(),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serialzableTree;

  @override
  List<CborObject?> get serializationItems => [
    cap.toCbor(),
    CborTagSerializable.listFromDynamic(shards.map((e) => e.toCbor()).toList()),
    CborTagSerializable.listFromDynamic(
      checkpionts.map((e) => e.toCbor()).toList(),
    ),
  ];
}

extension ExtRetentionEncoding on Retention<int> {
  static Retention<int> deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.retention,
      cborBytes: bytes,
      cborObject: obj,
    );
    final type = RetentionType.fromValue(values.rawValueAt(0));
    return switch (type) {
      RetentionType.ephemeral => RetentionEphemeral(),
      RetentionType.checkpoint => () {
        final checkpoint = values.objectAt<CborListValue>(1);
        return RetentionCheckpoint(
          id: checkpoint.rawValueAt<int>(0),
          marking: MarkingState.fromValue(checkpoint.rawValueAt<int>(1)),
        );
      }(),
      RetentionType.marked => RetentionMarked(),
      RetentionType.reference => RetentionReference(),
    };
  }

  CborTagValue toCbor() {
    return CborTagValue(
      CborListValue.definite(<CborObject>[
        CborIntValue(type.value),
        switch (this) {
          RetentionCheckpoint<int>(:final id, :final marking) =>
            CborListValue.definite([
              CborIntValue(id),
              CborIntValue(marking.value),
            ]),
          _ => CborListValue.definite(<CborObject>[]),
        },
      ]),
      [ZcashSerializationIdentifier.retention.id],
    );
  }
}
