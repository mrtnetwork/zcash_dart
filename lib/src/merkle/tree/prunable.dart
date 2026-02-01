import 'dart:collection';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';

class PrunableTree<H extends Object>
    extends Tree<H?, PrunableValue<H>, PrunableTree<H>> with Equality {
  const PrunableTree({
    required Node<H?, PrunableValue<H>, PrunableTree<H>> node,
    required this.hashContext,
  }) : super(node);

  factory PrunableTree.deserializeJson(
      {required Map<String, dynamic> json,
      required Hashable<H> hashContext,
      required H Function(Map<String, dynamic> json) onParseNode}) {
    final decode = VariantLayoutSerializable.toVariantDecodeResult(json);
    final type = NodeType.fromName(decode.variantName);
    final value = decode.value;
    return PrunableTree<H>(
        hashContext: hashContext,
        node: switch (type) {
          NodeType.nil => NodeNil<H?, PrunableValue<H>, PrunableTree<H>>(),
          NodeType.leaf => NodeLeaf<H?, PrunableValue<H>, PrunableTree<H>>(
              value: PrunableValue(
                  value: onParseNode(value.valueAs("value")),
                  flags: RetentionFlags(value.valueAs("flags")))),
          NodeType.parent => NodeParent<H?, PrunableValue<H>, PrunableTree<H>>(
              ann: value.valueTo<H?, Map<String, dynamic>>(
                  key: "ann", parse: onParseNode),
              left: PrunableTree.deserializeJson(
                  json: value.valueAs("left"),
                  onParseNode: onParseNode,
                  hashContext: hashContext),
              right: PrunableTree.deserializeJson(
                  json: value.valueAs("right"),
                  onParseNode: onParseNode,
                  hashContext: hashContext))
        });
  }

  final Hashable<H> hashContext;

  static Layout<Map<String, dynamic>> layout(Layout node, {String? property}) {
    return LayoutConst.lazyEnum([
      LazyVariantModel(
          layout: ({property}) {
            return LayoutConst.struct([
              LayoutConst.optional(node, property: "ann"),
              layout(node, property: "left"),
              layout(node, property: "right")
            ], property: property);
          },
          property: NodeType.parent.name,
          index: NodeType.parent.value),
      LazyVariantModel(
          layout: ({property}) {
            return LayoutConst.struct([
              LayoutConst.wrap(node, property: "value"),
              LayoutConst.u8(property: "flags")
            ], property: property);
          },
          property: NodeType.leaf.name,
          index: NodeType.leaf.value),
      LazyVariantModel(
          layout: ({property}) {
            return LayoutConst.noArgs(property: property);
          },
          property: NodeType.nil.name,
          index: NodeType.nil.value)
    ], property: property);
  }

  factory PrunableTree.parent({
    required PrunableTree<H> left,
    required PrunableTree<H> right,
    H? ann,
  }) {
    return PrunableTree(
        node: NodeParent(ann: ann, left: left, right: right),
        hashContext: left.hashContext);
  }
  factory PrunableTree.empty(Hashable<H> hashContext) {
    return PrunableTree(node: NodeNil(), hashContext: hashContext);
  }

  factory PrunableTree.unite({
    required TreeLevel level,
    required PrunableTree<H> left,
    required PrunableTree<H> right,
    required H? ann,
  }) {
    if (left.node.isNil() && right.node.isNil()) {
      if (ann == null) {
        return PrunableTree(node: NodeNil(), hashContext: left.hashContext);
      }
    }
    final hashContext = left.hashContext;
    final lV = left.node.leafValue();
    final rV = right.node.leafValue();
    if (lV != null && rV != null) {
      final rFlag = rV.flags;
      if (lV.flags == RetentionFlags.ephemeral &&
          (rFlag & (RetentionFlags.marked | RetentionFlags.reference)) ==
              RetentionFlags.ephemeral) {
        return PrunableTree(
            node: NodeLeaf(
                value: PrunableValue(
                    value: hashContext.combine(
                        level: level, a: lV.value, b: rV.value),
                    flags: rFlag)),
            hashContext: hashContext);
      }
    }
    return PrunableTree(
        node: NodeParent(ann: ann, left: left, right: right),
        hashContext: hashContext);
  }

  factory PrunableTree.leaf(
      {required PrunableValue<H> value, required Hashable<H> hashContext}) {
    return PrunableTree(node: NodeLeaf(value: value), hashContext: hashContext);
  }

  H? leafValue() {
    return node.leafValue()?.value;
  }

  H? nodeValue() {
    return node.annotation() ?? leafValue();
  }

  bool isMarkedLeaf() {
    return node.leafValue()?.flags.isMarket() ?? false;
  }

  bool hasComputableRoot() {
    return node.fold(
        onParent: (left, right, ann) =>
            ann != null ||
            (left.hasComputableRoot() && right.hasComputableRoot()),
        onLeaf: (v) => true,
        onNil: () => false);
  }

  bool isFull() {
    return node.fold(
        onParent: (_, right, ann) => ann != null || right.isFull(),
        onLeaf: (v) => true,
        onNil: () => false);
  }

  bool containsMarked() {
    return node.fold(
      onParent: (left, right, _) =>
          left.containsMarked() || right.containsMarked(),
      onLeaf: (v) => v.flags.isMarket(),
      onNil: () => false,
    );
  }

  H rootHash(
      {required NodeAddress rootAddr, required LeafPosition truncateAt}) {
    if (truncateAt <= rootAddr.positionRangeStart()) {
      return hashContext.emptyRoot(rootAddr.level);
    }
    return node.fold(
        onParent: (left, right, ann) {
          if (ann != null && truncateAt >= rootAddr.positionRangeEnd()) {
            return ann;
          }
          // Compute the roots of the left and right children and hash them together
          final (lAddr, rAddr) = rootAddr.children();

          final leftRoot =
              left.rootHash(rootAddr: lAddr, truncateAt: truncateAt);
          final rightRoot =
              right.rootHash(rootAddr: rAddr, truncateAt: truncateAt);
          return hashContext.combine(
              level: lAddr.level, a: leftRoot, b: rightRoot);
        },
        onLeaf: (v) {
          if (truncateAt >= rootAddr.positionRangeEnd()) {
            return v.value;
          }
          throw MerkleTreeException("rootHash", details: {"address": rootAddr});
        },
        onNil: () => throw MerkleTreeException("rootHash",
            details: {"address": rootAddr}));
  }

  SplayTreeSet<LeafPosition> markedPositions(NodeAddress rootAddr) {
    final SplayTreeSet<LeafPosition> result = SplayTreeSet();
    node.fold(
      onParent: (left, right, an) {
        assert(!(left.node.isNil() && !right.node.isNil()));
        final (lAddr, rAddr) = rootAddr.children();
        result.addAll(
            {...left.markedPositions(lAddr), ...right.markedPositions(rAddr)});
      },
      onLeaf: (v) {
        if (rootAddr.level == TreeLevel.zero && v.flags.isMarket()) {
          result.add(LeafPosition(rootAddr.index));
        }
      },
      onNil: () {},
    );
    return result;
  }

  PrunableTree<H> reannotateRoot(H? ann) {
    return PrunableTree(node: node.reannotate(ann), hashContext: hashContext);
  }

  PrunableTree<H> prune(TreeLevel level) {
    return node.fold(
        onParent: (left, right, ann) {
          return PrunableTree.unite(
              level: level,
              left: left.prune(level - 1),
              right: right.prune(level - 1),
              ann: ann);
        },
        onLeaf: (v) => this,
        onNil: () => this);
  }

  PrunableTree<H> mergeChecked(
      {required NodeAddress rootAddr, required PrunableTree<H> other}) {
    PrunableTree<H> fn(
        {required NodeAddress addr,
        required PrunableTree<H> t0,
        required PrunableTree<H> t1}) {
      final noDefaultFill = addr.positionRangeEnd();
      if (t0.node.isNil()) {
        return t1;
      }
      if (t1.node.isNil()) {
        return t0;
      }
      final t0Leaf = t0.node.tryAsleef();
      final t1Leaf = t1.node.tryAsleef();
      if (t0Leaf != null && t1Leaf != null) {
        if (t0Leaf.value.value == t1Leaf.value.value) {
          return PrunableTree<H>(
              hashContext: hashContext,
              node: NodeLeaf(
                  value: PrunableValue<H>(
                      value: t0Leaf.value.value,
                      flags: RetentionFlags(
                          t0Leaf.value.flags.flag | t1Leaf.value.flags.flag))));
        }
        throw MerkleTreeException.failed("mergeChecked",
            reason:
                "Inserted root conflicts with existing root at address $addr",
            details: {"rootAddr": addr});
      }
      final leaf = t0.node.tryAsleef() ?? t1.node.tryAsleef();
      final parent = t0.node.isParent()
          ? t0
          : t1.node.isParent()
              ? t1
              : null;
      if (leaf != null && parent != null) {
        final parentHash =
            parent.rootHash(rootAddr: addr, truncateAt: noDefaultFill);
        if (parentHash == leaf.value.value) {
          return parent.reannotateRoot(leaf.value.value);
        }
        throw MerkleTreeException.failed("mergeChecked",
            reason:
                "Inserted root conflicts with existing root at address $addr",
            details: {"rootAddr": addr});
      }
      H? lRoot;
      H? rRoot;
      try {
        lRoot = t0.rootHash(rootAddr: addr, truncateAt: noDefaultFill);
      } on MerkleTreeException catch (_) {}
      try {
        rRoot = t1.rootHash(rootAddr: addr, truncateAt: noDefaultFill);
      } on MerkleTreeException catch (_) {}
      if (lRoot == rRoot) {
        final lParent = t0.node.tryAsPrent();
        final rParent = t1.node.tryAsPrent();
        if (lParent != null && rParent != null) {
          final (lAddr, rAddr) = addr.children();
          final left = fn(addr: lAddr, t0: lParent.left, t1: rParent.left);
          final right = fn(addr: rAddr, t0: lParent.right, t1: rParent.right);
          return PrunableTree.unite(
              level: addr.level - 1,
              left: left,
              right: right,
              ann: lParent.ann ?? rParent.ann);
        }
      }
      throw MerkleTreeException.failed("mergeChecked",
          reason: "Merge input malformed at address $addr",
          details: {"rootAddr": addr});
    }

    return fn(addr: rootAddr, t0: this, t1: other);
  }

  @override
  List<dynamic> get variables => [node];
}

class LocatedPrunableTree<H extends Object>
    extends LocatedTree<H?, PrunableValue<H>, PrunableTree<H>> {
  const LocatedPrunableTree({required super.root, required super.rootAddr});
  Hashable<H> get hashContext => root.hashContext;

  factory LocatedPrunableTree.unit(
      {required LocatedPrunableTree<H> lroot,
      required LocatedPrunableTree<H> rroot,
      required TreeLevel pruneLevel}) {
    assert(lroot.rootAddr.parent() == rroot.rootAddr.parent());
    return LocatedPrunableTree<H>(
        rootAddr: lroot.rootAddr.parent(),
        root: lroot.rootAddr.level < pruneLevel
            ? PrunableTree.unite(
                level: lroot.rootAddr.level,
                left: lroot.root,
                right: rroot.root,
                ann: null)
            : PrunableTree.parent(left: lroot.root, right: rroot.root));
  }
  LeafPosition? maxPosition() {
    LeafPosition? fn(NodeAddress addr, PrunableTree<H> root) {
      return root.node.fold(
          onParent: (left, right, ann) {
            if (ann != null) return addr.maxPosition();
            final (lAddr, rAddr) = addr.children();
            return fn(rAddr, right) ?? fn(lAddr, left);
          },
          onLeaf: (v) => addr.positionRangeEnd() - 1,
          onNil: () => null);
    }

    return fn(rootAddr, root);
  }

  H rootHash(LeafPosition truncateAt) {
    return root.rootHash(rootAddr: rootAddr, truncateAt: truncateAt);
  }

  H rightFilledRoot() {
    final position = maxPosition() ?? rootAddr.positionRangeStart();
    return rootHash(position + 1);
  }

  Set<LeafPosition> markedPositions() {
    void fn(
        {required NodeAddress rootAddr,
        required PrunableTree<H> root,
        required Set<LeafPosition> acc}) {
      root.node.fold(
          onParent: (left, right, _) {
            final (lAddr, rAddr) = rootAddr.children();

            fn(rootAddr: lAddr, root: left, acc: acc);
            fn(rootAddr: rAddr, root: right, acc: acc);
          },
          onLeaf: (v) {
            if (v.flags.isMarket() && rootAddr.level.isZero()) {
              acc.add(LeafPosition(rootAddr.index));
            }
          },
          onNil: () => {});
    }

    final acc = <LeafPosition>{};
    fn(rootAddr: rootAddr, root: root, acc: acc);
    return acc;
  }

  List<H> witness(
      {required LeafPosition position, required LeafPosition truncateAt}) {
    List<H> fn(
        {required PrunableTree<H> root,
        required NodeAddress rootAddr,
        required LeafPosition position,
        required LeafPosition truncateAt}) {
      return root.node.fold(
        onParent: (left, right, ann) {
          final (lAddr, rAddr) = rootAddr.children();
          if (rootAddr.level.value > 1) {
            final rStart = rAddr.positionRangeStart();
            if (position < rStart) {
              return [
                ...fn(
                    rootAddr: lAddr,
                    truncateAt: truncateAt,
                    root: left,
                    position: position),
                right.rootHash(rootAddr: rAddr, truncateAt: truncateAt)
              ];
            } else {
              return [
                ...fn(
                    rootAddr: rAddr,
                    truncateAt: truncateAt,
                    root: right,
                    position: position),
                left.rootHash(rootAddr: lAddr, truncateAt: rStart)
              ];
            }
          } else {
            if (position.isRightChild()) {
              if (right.isMarkedLeaf()) {
                final n = left.leafValue();
                if (n != null) return [n];
              }

              throw MerkleTreeException.failed("witness",
                  details: {"address": lAddr});
            } else if (left.isMarkedLeaf()) {
              if (truncateAt <= (position + 1)) {
                return [root.hashContext.emptyLeaf()];
              }
              final n = right.leafValue();
              if (n != null) return [n];
            }
            throw MerkleTreeException.failed("witness",
                details: {"address": rAddr});
          }
        },
        onLeaf: (v) => throw MerkleTreeException.failed("witness",
            details: {"address": rootAddr}),
        onNil: () => throw MerkleTreeException.failed("witness",
            details: {"address": rootAddr}),
      );
    }

    if (rootAddr.positionRange().containsPosition(position)) {
      try {
        return fn(
            root: root,
            rootAddr: rootAddr,
            position: position,
            truncateAt: truncateAt);
      } on MerkleTreeException catch (e) {
        throw MerkleTreeException.failed("witness",
            reason: "Unable to compute root. missing values for nodes.",
            details: e.details);
      }
    }
    throw MerkleTreeException.failed("witness",
        reason: "Tree does not contain a root at address");
  }

  LocatedPrunableTree<H>? truncateToPosition(LeafPosition position) {
    PrunableTree<H>? fn(
        {required LeafPosition position,
        required NodeAddress rootAddr,
        required PrunableTree<H> root}) {
      return root.node.fold(
        onParent: (left, right, ann) {
          final (lAddr, rAddr) = rootAddr.children();
          if (position < rAddr.positionRangeStart()) {
            final n = fn(position: position, rootAddr: lAddr, root: left);
            if (n == null) return null;
            return PrunableTree.unite(
                level: lAddr.level,
                left: n,
                right: PrunableTree.empty(hashContext),
                ann: ann);
          }
          final n = fn(position: position, rootAddr: rAddr, root: right);
          if (n == null) return null;
          return PrunableTree.unite(
              level: rAddr.level, left: left, right: n, ann: ann);
        },
        onLeaf: (v) {
          if (rootAddr.maxPosition() <= position) {
            return root;
          }
          return null;
        },
        onNil: () => null,
      );
    }

    if (rootAddr.positionRange().containsPosition(position)) {
      final r = fn(position: position, rootAddr: rootAddr, root: root);
      if (r == null) return null;
      return LocatedPrunableTree(root: r, rootAddr: rootAddr);
    }
    return null;
  }

  TreeInsertReport<H> insertSubtree(
      {required LocatedPrunableTree<H> subtree, required bool containsMarked}) {
    (PrunableTree<H>, List<IncompleteNodeInfo>) fn(
        {required NodeAddress rootAddr,
        required PrunableTree<H> into,
        required LocatedPrunableTree<H> subtree,
        required bool containsMarked}) {
      if (subtree.root.node.isNil()) {
        return (into, []);
      }
      (PrunableTree<H>, List<IncompleteNodeInfo>) replacement(
        H? ann,
        LocatedPrunableTree<H> node,
      ) {
        final incomplete = <IncompleteNodeInfo>[];
        var current = node;
        final empty = PrunableTree.empty(hashContext);

        while (current.rootAddr.level < rootAddr.level) {
          incomplete.add(
            IncompleteNodeInfo(
                address: current.rootAddr.sibling(),
                requiredForWitness: containsMarked),
          );
          final full = current.root;
          current = LocatedPrunableTree(
            rootAddr: current.rootAddr.parent(),
            root: current.rootAddr.isRightChild()
                ? PrunableTree.parent(left: empty, right: full)
                : PrunableTree.parent(left: full, right: empty),
          );
        }
        return (current.root.reannotateRoot(ann), incomplete);
      }

      return into.node.fold(
        onParent: (left, right, ann) {
          if (rootAddr == subtree.rootAddr) {
            return (
              into.mergeChecked(rootAddr: rootAddr, other: subtree.root),
              []
            );
          }
          final (lAddr, rAddr) = rootAddr.children();

          if (lAddr.contains(subtree.rootAddr)) {
            final r = fn(
                rootAddr: lAddr,
                into: left,
                subtree: subtree,
                containsMarked: containsMarked);
            return (
              PrunableTree.unite(
                  level: rootAddr.level - 1,
                  left: r.$1,
                  ann: ann,
                  right: right),
              r.$2
            );
          }
          final r = fn(
              rootAddr: rAddr,
              into: right,
              subtree: subtree,
              containsMarked: containsMarked);
          return (
            PrunableTree.unite(
                ann: ann, level: rootAddr.level - 1, right: r.$1, left: left),
            r.$2
          );
        },
        onLeaf: (leaf) {
          final value = leaf.value;
          final retention = leaf.flags;

          if (rootAddr == subtree.rootAddr) {
            // Replacing the root
            if (subtree.root.hasComputableRoot()) {
              final leaf = subtree.root.node.tryAsleef();
              if (leaf != null) {
                final v0 = leaf.value.value;
                final ret0 = leaf.value.flags;
                if (v0 != value) {
                  throw MerkleTreeException.failed("insertSubtree",
                      reason:
                          "Inserted root conflicts with existing root at address $rootAddr.",
                      details: {"addr": rootAddr});
                }
                final mergedRetention =
                    ((retention | ret0) - RetentionFlags.reference) |
                        (RetentionFlags.reference & retention & ret0);
                return (
                  PrunableTree<H>(
                      hashContext: root.hashContext,
                      node: NodeLeaf(
                          value: PrunableValue(
                              value: value, flags: mergedRetention))),
                  []
                );
              }
              return (subtree.root, <IncompleteNodeInfo>[]);
            } else if (subtree.root.nodeValue() == value) {
              return (subtree.root.reannotateRoot(value), []);
            } else {
              throw MerkleTreeException.failed("insertSubtree",
                  reason:
                      "Inserted root conflicts with existing root at address $rootAddr.",
                  details: {"addr": rootAddr});
            }
          }

          return replacement(value, subtree);
        },
        onNil: () => replacement(null, subtree),
      );
    }

    final maxPosition = this.maxPosition() ?? LeafPosition(0);
    if (rootAddr.contains(subtree.rootAddr)) {
      final r = fn(
          rootAddr: rootAddr,
          into: root,
          subtree: subtree,
          containsMarked: containsMarked);
      final newTree = LocatedPrunableTree(root: r.$1, rootAddr: rootAddr);
      final nPosition = newTree.maxPosition() ?? LeafPosition(0);

      assert(nPosition >= maxPosition);
      return TreeInsertReport(subtree: newTree, incomplete: r.$2);
    }
    throw MerkleTreeException.failed("insertSubtree",
        reason: "Tree does not contain a root at address ${subtree.rootAddr}",
        details: {"addr": rootAddr});
  }

  LocatedPrunableTree<H> clearFlags(
      Map<LeafPosition, RetentionFlags> toClearMap) {
    final toClear = toClearMap.entries.toList();
    PrunableTree<H> go(
        {required List<MapEntry<LeafPosition, RetentionFlags>> flagsToClear,
        required NodeAddress addr,
        required PrunableTree<H> tree}) {
      if (flagsToClear.isEmpty) {
        return tree;
      }

      final node = tree.node;
      return node.fold(
        onParent: (left, right, ann) {
          final (lAddr, rAddr) = addr.children();
          int partition = flagsToClear.indexWhere(
              (e) => e.key.compareTo(lAddr.positionRangeEnd()) >= 0);
          if (partition == -1) partition = flagsToClear.length;
          final leftSubtree = go(
              flagsToClear: flagsToClear.sublist(0, partition),
              addr: lAddr,
              tree: left);
          final rightSubtree = go(
              flagsToClear: flagsToClear.sublist(partition),
              addr: rAddr,
              tree: right);
          return PrunableTree.unite(
              level: lAddr.level,
              left: leftSubtree,
              right: rightSubtree,
              ann: ann);
        },
        onLeaf: (v) {
          if (flagsToClear.length == 1) {
            final newFlags =
                RetentionFlags(v.flags.flag & ~flagsToClear[0].value.flag);
            return PrunableTree<H>(
                hashContext: tree.hashContext,
                node: NodeLeaf(
                    value: PrunableValue(value: v.value, flags: newFlags)));
          } else {
            throw StateError('Tree state inconsistent with checkpoints.');
          }
        },
        onNil: () {
          return PrunableTree.empty(hashContext);
        },
      );
    }

    return LocatedPrunableTree<H>(
        root: go(flagsToClear: toClear, addr: rootAddr, tree: root),
        rootAddr: rootAddr);
  }

  PrunableValue<H>? valueAtPosition(LeafPosition position) {
    PrunableValue<H>? fn({
      required LeafPosition pos,
      required NodeAddress addr,
      required PrunableTree<H> root,
    }) {
      return root.node.fold(
        onParent: (left, right, ann) {
          final (lAddr, rAddr) = addr.children();

          if (lAddr.positionRange().containsPosition(pos)) {
            return fn(pos: pos, addr: lAddr, root: left);
          }
          return fn(pos: pos, addr: rAddr, root: right);
        },
        onLeaf: (v) {
          if (addr.level.isZero()) {
            return v;
          }
          return null;
        },
        onNil: () => null,
      );
    }

    if (rootAddr.positionRange().contains(position.position)) {
      return fn(pos: position, addr: rootAddr, root: root);
    }
    return null;
  }

  LocatedPrunableTree<H>? subtree(NodeAddress addr) {
    LocatedPrunableTree<H>? fn(
        {required NodeAddress rootAddr,
        required PrunableTree<H> root,
        required NodeAddress addr}) {
      if (rootAddr == addr) {
        return LocatedPrunableTree(root: root, rootAddr: rootAddr);
      }
      return root.node.fold(
        onParent: (left, right, _) {
          final (lAddr, rAddr) = rootAddr.children();

          if (lAddr.contains(addr)) {
            return fn(rootAddr: lAddr, root: left, addr: addr);
          }
          return fn(rootAddr: rAddr, root: right, addr: addr);
        },
        onLeaf: (v) => null,
        onNil: () => null,
      );
    }

    if (rootAddr.contains(addr)) {
      return fn(rootAddr: rootAddr, root: root, addr: addr);
    }
    return null;
  }

  static TreeBatchInsertReport<H, C>?
      fromIter<C extends Object, H extends Object>(
          {required LeafPositionRange positionRange,
          required TreeLevel pruneLevel,
          required Iterator<(H, Retention<C>)> values,
          required Hashable<H> hashContext}) {
    List<(LocatedPrunableTree<H>, bool)> framgments = [];
    LeafPosition position = positionRange.start;
    final SplayTreeMap<C, LeafPosition> checkpoints = SplayTreeMap();
    Iterator<(H, Retention<C>)>? iter = values;
    while (position < positionRange.end) {
      if (iter != null && iter.moveNext()) {
        final (value, id) = iter.current;
        if (id case RetentionCheckpoint<C> f) {
          checkpoints[f.id] = position;
        }
        final rFlags = RetentionFlags.fromRetention(id);
        LocatedPrunableTree<H> subtree = LocatedPrunableTree<H>(
            root: PrunableTree(
                node:
                    NodeLeaf(value: PrunableValue(value: value, flags: rFlags)),
                hashContext: hashContext),
            rootAddr: NodeAddress.fromPosition(position));
        if (position.isRightChild()) {
          while (framgments.isNotEmpty) {
            final (sibling, marked) = framgments.removeLast();
            if (sibling.rootAddr.parent() == subtree.rootAddr.parent()) {
              subtree = LocatedPrunableTree.unit(
                  lroot: sibling, rroot: subtree, pruneLevel: pruneLevel);
            } else {
              framgments.add((sibling, marked));
              break;
            }
          }
        }
        framgments.add((subtree, rFlags.isMarket()));
        position += 1;
      } else {
        iter = null;
        break;
      }
    }
    if (position > positionRange.start) {
      final lastPosition = position - 1;
      final minimalRootAddr = NodeAddress.fromPosition(positionRange.start)
          .commonAncestor(NodeAddress.fromPosition(lastPosition));
      final (result) =
          _buildMinimalTree(framgments, minimalRootAddr, pruneLevel);

      if (result != null) {
        return TreeBatchInsertReport(
            subtree: result.toInsert,
            containsMarked: result.marked,
            incomplete: result.incomplete,
            maxInsertPosition: lastPosition,
            checkpoints: checkpoints,
            remainder: iter);
      }
    }
    return null;
  }

  (LocatedPrunableTree<H>, LeafPosition, C?) append<C extends Comparable>({
    required H value,
    required Retention<C> retention,
  }) {
    C? checkpointId;
    if (retention case RetentionCheckpoint<C>(id: final id)) {
      checkpointId = id;
    }
    final result = _batchAppend([(value, retention)].iterator);
    if (result == null) throw MerkleTreeException.failed("append");
    final remainder = result.remainder;
    if (remainder != null && remainder.moveNext()) {
      throw MerkleTreeException.failed("append",
          reason: "Note commitment tree is full.");
    }
    return (result.subtree, result.maxInsertPosition, checkpointId);
    // final checkpointId = retention case
  }

  TreeBatchInsertReport<H, CHECKPOINT>? _batchAppend<CHECKPOINT extends Object>(
      Iterator<(H, Retention<CHECKPOINT>)> values) {
    LeafPosition? appendPosition = maxPosition();
    if (appendPosition != null) {
      appendPosition += 1;
    }
    appendPosition ??= rootAddr.positionRangeStart();
    return batchInsert(start: appendPosition, values: values);
  }

  TreeBatchInsertReport<H, CHECKPOINT>? batchInsert<CHECKPOINT extends Object>(
      {required LeafPosition start,
      required Iterator<(H, Retention<CHECKPOINT>)> values}) {
    final subtreeRange = rootAddr.positionRange();
    final bool containsStart = subtreeRange.containsPosition(start);
    if (containsStart) {
      final positionRange =
          LeafPositionRange(start: start, end: subtreeRange.end);

      final n = fromIter(
          positionRange: positionRange,
          pruneLevel: rootAddr.level,
          values: values,
          hashContext: hashContext);
      if (n != null) {
        final result =
            insertSubtree(subtree: n.subtree, containsMarked: n.containsMarked);
        return TreeBatchInsertReport(
            subtree: result.subtree,
            containsMarked: n.containsMarked,
            incomplete: [...n.incomplete, ...result.incomplete],
            maxInsertPosition: n.maxInsertPosition,
            checkpoints: n.checkpoints,
            remainder: n.remainder);
      }
    }
    return null;
  }

  static ({
    LocatedPrunableTree<H> toInsert,
    bool marked,
    List<IncompleteNodeInfo> incomplete
  })? _buildMinimalTree<H extends Object>(
    List<(LocatedPrunableTree<H>, bool)> xs,
    NodeAddress rootAddr,
    TreeLevel pruneBelow,
  ) {
    if (xs.isEmpty) return null;
    List<IncompleteNodeInfo> incomplete = [];
    var (cur, containsMarked) = xs.removeLast();
    while (xs.isNotEmpty) {
      final (top, topMarked) = xs.removeLast();
      while (cur.rootAddr.level < top.rootAddr.level) {
        cur = _combineWithEmpty(cur, true, incomplete, topMarked, pruneBelow);
      }
      if (cur.rootAddr.level == top.rootAddr.level) {
        containsMarked = containsMarked || topMarked;
        if (cur.rootAddr.isRightChild()) {
          cur = LocatedPrunableTree.unit(
              lroot: top, rroot: cur, pruneLevel: pruneBelow);
        } else {
          xs.add((top, topMarked));
          cur = _combineWithEmpty(cur, true, incomplete, topMarked, pruneBelow);
          break;
        }
      } else {
        xs.add((top, topMarked));
        break;
      }
    }
    while (cur.rootAddr.level + 1 < rootAddr.level) {
      cur =
          _combineWithEmpty(cur, true, incomplete, containsMarked, pruneBelow);
    }
    xs.add((cur, containsMarked));
    final res = xs.fold<LocatedPrunableTree<H>?>(null, (acc, c) {
      final nextTree = c.$1;
      final nextMarked = c.$2;
      if (acc == null) {
        return nextTree;
      }
      LocatedPrunableTree<H> p = acc;
      while (p.rootAddr.level < nextTree.rootAddr.level) {
        containsMarked = containsMarked || nextMarked;
        p = _combineWithEmpty(p, false, incomplete, nextMarked, pruneBelow);
      }
      return LocatedPrunableTree.unit(
          lroot: p, rroot: nextTree, pruneLevel: pruneBelow);
    });
    if (res == null) return null;
    return (toInsert: res, marked: containsMarked, incomplete: incomplete);
  }

  SplayTreeMap<LeafPosition, RetentionFlags> flagPositions() {
    void fn(
        {required PrunableTree<H> root,
        required NodeAddress rootAddr,
        required SplayTreeMap<LeafPosition, RetentionFlags> acc}) {
      root.node.fold(
          onParent: (left, right, _) {
            final (lAddr, rAddr) = rootAddr.children();
            fn(root: left, rootAddr: lAddr, acc: acc);
            fn(root: right, rootAddr: rAddr, acc: acc);
          },
          onLeaf: (value) {
            if (value.flags != RetentionFlags.ephemeral) {
              acc[rootAddr.maxPosition()] = value.flags;
            }
          },
          onNil: () {});
    }

    final SplayTreeMap<LeafPosition, RetentionFlags> reuslt = SplayTreeMap();
    fn(root: root, rootAddr: rootAddr, acc: reuslt);
    return reuslt;
  }

  static LocatedPrunableTree<H> _combineWithEmpty<H extends Object>(
    LocatedPrunableTree<H> root,
    bool expectLeftChild,
    List<IncompleteNodeInfo> incomplete,
    bool containsMarked,
    TreeLevel pruneBelow,
  ) {
    final siblingAddr = root.rootAddr.sibling();
    incomplete.add(IncompleteNodeInfo(
        address: siblingAddr, requiredForWitness: containsMarked));
    final sibling = LocatedPrunableTree<H>(
      rootAddr: siblingAddr,
      root: PrunableTree.empty(root.hashContext),
    );
    if (root.rootAddr.isLeftChild()) {
      return LocatedPrunableTree.unit(
          lroot: root, rroot: sibling, pruneLevel: pruneBelow);
    }
    return LocatedPrunableTree.unit(
        lroot: sibling, rroot: root, pruneLevel: pruneBelow);
  }

  (LocatedPrunableTree<H>, LocatedPrunableTree<H>?)
      insertFrontierNodes<C extends Object>(
          NonEmptyFrontier<H> frontier, Retention<C> leafRetention) {
    final subtreeRange = rootAddr.positionRange();

    if (subtreeRange.containsPosition(frontier.position)) {
      final leafIsMarked = leafRetention.isMarked;

      final (subtree, supertree) = fromFrontier(
          frontier: frontier,
          leafRetention: leafRetention,
          splitAt: rootAddr.level);
      final inserted =
          insertSubtree(subtree: subtree, containsMarked: leafIsMarked);
      final updatedSubtree = inserted.subtree;
      return ((updatedSubtree, supertree));
    } else {
      throw MerkleTreeException.failed("insertFrontierNodes",
          reason: "point out of range.");
    }
  }

  (LocatedPrunableTree<H>, LocatedPrunableTree<H>?)
      fromFrontier<C extends Object>({
    required NonEmptyFrontier<H> frontier,
    required Retention<C> leafRetention,
    required TreeLevel splitAt,
  }) {
    final position = frontier.position;
    final leaf = frontier.leaf;
    final ommers = frontier.ommers.iterator;
    NodeAddress addr = NodeAddress.fromPosition(position);
    PrunableTree<H> subtree = PrunableTree.leaf(
        value: PrunableValue(
            value: leaf, flags: RetentionFlags.fromRetention(leafRetention)),
        hashContext: hashContext);

    // Build subtree bottom-up until we reach splitAt
    while (addr.level < splitAt) {
      if (addr.isLeftChild()) {
        // Left child: right side is empty
        subtree = PrunableTree.parent(
          ann: null,
          left: subtree,
          right: PrunableTree.empty(hashContext),
        );
      } else if (ommers.moveNext()) {
        // Right child: take left sibling from ommers
        final left = ommers.current;
        subtree = PrunableTree.parent(
          left: PrunableTree.leaf(
              value:
                  PrunableValue(value: left, flags: RetentionFlags.ephemeral),
              hashContext: hashContext),
          right: subtree,
        );
      } else {
        break;
      }

      addr = addr.parent();
    }
    final locatedSubtree = LocatedPrunableTree(rootAddr: addr, root: subtree);
    LocatedPrunableTree<H>? locatedSupertree;
    if (locatedSubtree.rootAddr.level == splitAt) {
      var superAddr = locatedSubtree.rootAddr;
      PrunableTree<H>? supertree;
      final empty = PrunableTree.empty(hashContext);
      while (ommers.moveNext()) {
        final left = ommers.current;

        // Climb while we are a left child
        while (superAddr.isLeftChild()) {
          supertree = supertree == null
              ? PrunableTree.parent(left: empty, right: empty)
              : PrunableTree.parent(left: supertree, right: empty);

          superAddr = superAddr.parent();
        }

        // Now attach the left sibling
        supertree = PrunableTree.parent(
            left: PrunableTree.leaf(
                value:
                    PrunableValue(value: left, flags: RetentionFlags.ephemeral),
                hashContext: hashContext),
            right: supertree ?? empty);

        superAddr = superAddr.parent();
      }

      if (supertree != null) {
        locatedSupertree =
            LocatedPrunableTree(rootAddr: superAddr, root: supertree);
      }
    } else {
      // Not enough ommers → no cap contribution
      locatedSupertree = null;
    }

    return (locatedSubtree, locatedSupertree);
  }

  List<LocatedPrunableTree<H>> decomposeToLevel(TreeLevel level) {
    List<LocatedPrunableTree<H>> go(
      TreeLevel level,
      NodeAddress rootAddr,
      PrunableTree<H> root,
    ) {
      if (rootAddr.level == level) {
        return [LocatedPrunableTree<H>(rootAddr: rootAddr, root: root)];
      } else {
        return root.node.fold(
            onParent: (left, right, ann) {
              final (lAddr, rAddr) = rootAddr.children();
              final lDecomposed = go(level, lAddr, left);
              final rDecomposed = go(level, rAddr, right);
              lDecomposed.addAll(rDecomposed);
              return lDecomposed;
            },
            onLeaf: (value) => [],
            onNil: () => []);
      }
    }

    if (level >= rootAddr.level) {
      return [this];
    } else {
      return go(level, rootAddr, root);
    }
  }
}

extension PrunableSerializable<H extends LayoutSerializable>
    on PrunableTree<H> {
  Map<String, dynamic> toSerializeJson() {
    return {
      node.type.name: node.fold(
          onParent: (left, right, ann) {
            return {
              "ann": ann?.toSerializeJson(),
              "left": left.toSerializeJson(),
              "right": right.toSerializeJson()
            };
          },
          onLeaf: (value) => {
                "value": value.value.toSerializeJson(),
                "flags": value.flags.flag
              },
          onNil: () => <String, dynamic>{})
    };
  }
}
