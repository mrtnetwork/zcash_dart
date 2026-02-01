import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';

abstract class ShardTree<H extends Object, C extends Comparable,
    S extends ShardStore<H, C>, MERKLEPATH extends MerklePath<H>> {
  final S store;
  final int maxCheckpoints;
  int get depth => rootAddr.level.value;
  int get shardHeight => subtreeLevel.value;
  final NodeAddress rootAddr;
  final TreeLevel subtreeLevel;
  final int maxSubtreeIndex;
  late final PrunableTree<H> emptyTree =
      PrunableTree(node: NodeNil(), hashContext: store.hashContext);
  ShardTree(
      {required this.store,
      required this.maxCheckpoints,
      required int depth,
      required int shardHeight})
      : rootAddr = NodeAddress(level: TreeLevel(depth), index: 0),
        subtreeLevel = TreeLevel(shardHeight),
        maxSubtreeIndex = (0x1 << (depth - shardHeight)) - 1;
  Hashable<H> get hashContext => store.hashContext;
  MERKLEPATH toMerklePath(LeafPosition position, List<H> path);

  NodeAddress subtreeAddr(LeafPosition position) =>
      NodeAddress.abovePosition(level: subtreeLevel, position: position);
  H? getMarkedLeaf(LeafPosition position) {
    final shard = store.getShard(subtreeAddr(position));
    final v = shard?.valueAtPosition(position);
    if (v != null && v.flags.isMarket()) return v.value;
    return null;
  }

  Set<LeafPosition> markedPossitions() {
    final shards = store.getShardRoots();
    Set<LeafPosition> result = {};
    for (final s in shards) {
      final subtree = store.getShard(s);
      if (subtree == null) continue;
      result.addAll(subtree.markedPositions());
    }
    return result;
  }

  LeafPosition? maxLeafPosition({int? checkpointDepth}) {
    if (checkpointDepth == null) {
      return store.lastShard()?.maxPosition();
    }
    final r = store.getCheckpointAtDepth(checkpointDepth)?.$2.position();
    if (r == null) {
      throw MerkleTreeException.failed("maxLeafPosition",
          reason:
              "The leaf corresponding to the requested checkpoint is not present in the tree.");
    }
    return r;
  }

  bool truncateToCheckpointDepth(int checkpointDepth) {
    final checkpointId = store.getCheckpointAtDepth(checkpointDepth);
    if (checkpointId == null) return false;

    void truncateToCheckpointInternal({
      required C checkpointId,
      required Checkpoint checkpoint,
    }) {
      final state = checkpoint.treeState;
      switch (state) {
        case TreeStateEmpty():
          store.truncateShards(0);
          store.truncateCheckpointsRetaining(checkpointId);
          store.putCap(emptyTree);
          break;
        case TreeStateAtPosition(:final position):
          final subAddr = subtreeAddr(position);
          final replacement =
              store.getShard(subAddr)?.truncateToPosition(position);
          final capTree =
              LocatedPrunableTree(root: store.getCap(), rootAddr: rootAddr);
          final truncatedCap = capTree.truncateToPosition(position);
          if (truncatedCap != null) {
            store.putCap(truncatedCap.root);
          }
          if (replacement != null) {
            store.truncateShards(subAddr.index);
            store.putShard(replacement);
            store.truncateCheckpointsRetaining(checkpointId);
          }
      }
    }

    truncateToCheckpointInternal(
        checkpointId: checkpointId.$1, checkpoint: checkpointId.$2);
    return true;
  }

  bool checkpoint(C checkpointId) {
    (PrunableTree<H>, LeafPosition)? fn(
        {required NodeAddress rootAddr, required PrunableTree<H> root}) {
      return root.node.fold(
          onParent: (left, right, ann) {
            final (lAddr, rAddr) = rootAddr.children();

            final rightResult = fn(rootAddr: rAddr, root: right);

            if (rightResult == null) {
              final leftResult = fn(rootAddr: lAddr, root: left);
              if (leftResult == null) {
                return null;
              }

              final (newLeft, pos) = leftResult;
              return (
                PrunableTree.unite(
                    level: lAddr.level,
                    ann: ann,
                    left: newLeft,
                    right: emptyTree),
                pos
              );
            } else {
              final (newRight, pos) = rightResult;
              return (
                PrunableTree.unite(
                  level: lAddr.level,
                  ann: ann,
                  left: left,
                  right: newRight,
                ),
                pos,
              );
            }
          },
          onLeaf: (v) {
            return (
              PrunableTree<H>(
                  hashContext: store.hashContext,
                  node: NodeLeaf(
                      value: PrunableValue(
                          value: v.value,
                          flags: v.flags | RetentionFlags.checkpoint))),
              rootAddr.maxPosition()
            );
          },
          onNil: () => null);
    }

    final max = store.maxCheckpointId();
    if (max != null && max.compareTo(checkpointId) >= 0) {
      return false;
    }
    final subtree = store.lastShard();
    if (subtree != null) {
      final r = fn(rootAddr: subtree.rootAddr, root: subtree.root);
      if (r != null) {
        final (PrunableTree<H> replacement, LeafPosition pos) = r;
        store.putShard(
            LocatedPrunableTree(root: replacement, rootAddr: subtree.rootAddr));
        store.addCheckpoint(checkpointId, Checkpoint.atPosition(pos));
        _pruneExcessCheckpoints();
        return true;
      }
    }
    store.addCheckpoint(checkpointId, Checkpoint.treeEmpty());
    _pruneExcessCheckpoints();
    return true;
  }

  H? rootAtCheckpointDepth({int? checkpointDepth}) {
    final result = maxLeafPosition(checkpointDepth: checkpointDepth);
    if (result == null) return store.hashContext.emptyRoot(rootAddr.level);
    return root(address: rootAddr, truncateAt: result + 1);
  }

  H root({
    required NodeAddress address,
    required LeafPosition truncateAt,
  }) {
    assert(rootAddr.contains(address));
    final r = _rootInternal(
        cap: LocatedPrunableTree<H>(rootAddr: rootAddr, root: store.getCap()),
        targetAddr: address,
        truncateAt: truncateAt);
    return r.$1;
  }

  H? rootAtCheckpointId(C checkpoint) {
    final c = store.getCheckpoint(checkpoint);
    if (c == null) return null;
    final p = c.position();
    if (p == null) return store.hashContext.emptyRoot(rootAddr.level);
    return root(address: rootAddr, truncateAt: p + 1);
  }

  H rootCaching({
    required NodeAddress address,
    required LeafPosition truncateAt,
  }) {
    final value = _rootInternal(
        cap: LocatedPrunableTree<H>(root: store.getCap(), rootAddr: rootAddr),
        targetAddr: address,
        truncateAt: truncateAt);
    final nCap = value.$2;
    if (nCap != null) {
      store.putCap(nCap);
    }
    return value.$1;
  }

  void insert({required NodeAddress rootAddr, required H value}) {
    if (rootAddr.level > this.rootAddr.level) {
      throw MerkleTreeException.failed("insert",
          reason: "Tree does not contain a root at address $rootAddr",
          details: {"addr": rootAddr});
    }
    final toInsert = LocatedPrunableTree<H>(
        root: PrunableTree<H>(
            hashContext: store.hashContext,
            node: NodeLeaf(
                value: PrunableValue(
                    value: value, flags: RetentionFlags.ephemeral))),
        rootAddr: rootAddr);
    if (rootAddr.level >= subtreeLevel) {
      final cap =
          LocatedPrunableTree<H>(root: store.getCap(), rootAddr: this.rootAddr);
      final insert =
          cap.insertSubtree(subtree: toInsert, containsMarked: false);
      store.putCap(insert.subtree.root);
    }
    rootAddr.getContext(
      level: subtreeLevel,
      right: (_) {},
      left: (addr) {
        final shard = store.getShard(addr) ??
            LocatedPrunableTree<H>(
                rootAddr: addr,
                root: PrunableTree(
                    node: NodeNil(), hashContext: store.hashContext));
        final insert =
            shard.insertSubtree(subtree: toInsert, containsMarked: false);
        store.putShard(insert.subtree);
      },
    );
  }

  void append({
    required H value,
    required Retention<C> retention,
  }) {
    if (retention case RetentionCheckpoint(id: final id)) {
      final max = store.maxCheckpointId();
      if (max != null && max.compareTo(id) >= 0) {
        throw MerkleTreeException.failed("append",
            reason: "Cannot append out-of-order checkpoint identifier.");
      }
    }
    LocatedPrunableTree<H>? subtree = store.lastShard();
    (LocatedPrunableTree<H>, LeafPosition, C?) append;
    if (subtree != null) {
      if (subtree.root.isFull()) {
        final addr = subtree.rootAddr;
        if (addr.index < maxSubtreeIndex) {
          append = LocatedPrunableTree<H>(
                  root: emptyTree, rootAddr: addr.nextAtLevel())
              .append(value: value, retention: retention);
        } else {
          throw MerkleTreeException.failed("append",
              reason: "Note commitment tree is full.");
        }
      } else {
        append = subtree.append(value: value, retention: retention);
      }
    } else {
      final rootAddr = NodeAddress(level: subtreeLevel, index: 0);
      append = LocatedPrunableTree<H>(root: emptyTree, rootAddr: rootAddr)
          .append(value: value, retention: retention);
    }
    var (LocatedPrunableTree<H> result, LeafPosition position, C? checkpoint) =
        append;
    store.putShard(result);
    if (checkpoint != null) {
      store.addCheckpoint(checkpoint, Checkpoint.atPosition(position));
    }
    _pruneExcessCheckpoints();
  }

  TreeBatchResult? batchInsert(
      {required LeafPosition start, required List<(H, Retention<C>)> values}) {
    NodeAddress subtreeRootAddr = subtreeAddr(start);
    LeafPosition? maxInsert;
    final List<IncompleteNodeInfo> incomplete = [];
    bool isLast = false;
    final s = Iterable<(H, Retention<C>)>.generate(
      values.length,
      (index) {
        isLast = index == values.length - 1;
        return values[index];
      },
    );
    Iterator<(H, Retention<C>)>? itrator = s.iterator;

    while (itrator != null && !isLast) {
      // Fetch shard or empty
      LocatedPrunableTree<H> shard = store.getShard(subtreeRootAddr) ??
          LocatedPrunableTree<H>(
              rootAddr: subtreeRootAddr,
              root: PrunableTree(
                  node: NodeNil(), hashContext: store.hashContext));

      // Perform batch insert on shard
      TreeBatchInsertReport<H, C>? res =
          shard.batchInsert(start: start, values: itrator);
      if (res == null) {
        throw MerkleTreeException.failed("batchInsert",
            reason:
                "Iterator containing leaf values to insert was verified to be nonempty.");
      }

      // Store updated subtree
      store.putShard(res.subtree);

      // AstAdd checkpoints
      for (final MapEntry(key: id, value: position)
          in res.checkpoints.entries) {
        store.addCheckpoint(id, Checkpoint.atPosition(position));
      }

      // Update loop variables
      itrator = res.remainder;
      subtreeRootAddr = subtreeRootAddr.nextAtLevel();
      maxInsert = res.maxInsertPosition;
      start = res.maxInsertPosition + 1;
      incomplete.addAll(res.incomplete);
    }
    if (maxInsert == null) return null;
    _pruneExcessCheckpoints();
    return TreeBatchResult(maxInsert: maxInsert, incomplete: incomplete);
  }

  MERKLEPATH? witnessAtCheckpointIdCaching(
      {required LeafPosition position, required C checkpointId}) {
    final checkpoint = store.getCheckpoint(checkpointId);
    if (checkpoint == null) return null;
    final asOf = checkpoint.position();
    if (asOf == null || position > asOf) {
      throw MerkleTreeException.failed("witnessAtCheckpointIdCaching",
          reason: "Missing tree root.");
    }
    return _witnessInternalCaching(position: position, asOf: asOf);
  }

  MERKLEPATH? witnessAtCheckpointDepth(
      {required LeafPosition position, required int checkpointDepth}) {
    final checkpoin = store.getCheckpointAtDepth(checkpointDepth);
    if (checkpoin == null) return null;
    final asOf = checkpoin.$2.position() ?? LeafPosition(0);
    if (position > asOf) {
      throw MerkleTreeException.failed("witnessAtCheckpointDepth",
          reason: "Missing tree root.");
    }
    return _wintessInternal(position: position, asOf: asOf);
  }

  MERKLEPATH? witnessAtCheckpointId(
      {required LeafPosition position, required C checkpointId}) {
    final checkpoint = store.getCheckpoint(checkpointId);
    if (checkpoint == null) return null;
    final asOf = checkpoint.position();
    if (asOf == null || position > asOf) {
      throw MerkleTreeException.failed("witnessAtCheckpointId",
          reason: "Missing tree root.");
    }
    return _wintessInternal(position: position, asOf: asOf);
  }

  void insertFrontier(Frontier<H> frontier, Retention<C> leafRetention) {
    final f = frontier.frontier;
    if (f != null) {
      insertFrontierNodes(f, leafRetention);
    } else {
      switch (leafRetention) {
        case RetentionEphemeral<C>():
          break;
        case RetentionCheckpoint<C>(id: C id, marking: MarkingState marking)
            when marking == MarkingState.none ||
                marking == MarkingState.reference:
          store.addCheckpoint(id, Checkpoint.treeEmpty());
          break;
        default:
          throw MerkleTreeException.failed("insertFrontier",
              reason: "Invalid retention");
      }
    }
  }

  void insertFrontierNodes(
      NonEmptyFrontier<H> frontier, Retention<C> leafRetention) {
    final leafPosition = frontier.position;
    final subtreeRootAddr =
        NodeAddress.abovePosition(level: subtreeLevel, position: leafPosition);
    final currentShard = store.getShard(subtreeRootAddr) ??
        LocatedPrunableTree<H>(
            rootAddr: subtreeRootAddr,
            root:
                PrunableTree(node: NodeNil(), hashContext: store.hashContext));
    final (updatedSubtree, supertree) =
        currentShard.insertFrontierNodes(frontier, leafRetention);
    store.putShard(updatedSubtree);
    if (supertree != null) {
      final capTree =
          LocatedPrunableTree<H>(rootAddr: rootAddr, root: store.getCap());
      final newCap = capTree.insertSubtree(
          subtree: supertree, containsMarked: leafRetention.isMarked);
      store.putCap(newCap.subtree.root);
    }
    if (leafRetention case RetentionCheckpoint(id: C id)) {
      store.addCheckpoint(id, Checkpoint.atPosition(leafPosition));
    }
    _pruneExcessCheckpoints();
  }

  List<IncompleteNodeInfo> insertTree(
      LocatedPrunableTree<H> tree, Map<C, LeafPosition> checkpoints) {
    final List<IncompleteNodeInfo> allIncomplete = [];

    for (final subtree in tree.decomposeToLevel(subtreeLevel)) {
      // Skip empty subtrees to preserve shard invariants
      if (subtree.root.node.isNil()) {
        continue;
      }
      // Normalize to a valid shard address
      final rootAddr = subtreeAddr(subtree.rootAddr.positionRangeStart());
      final containsMarked = subtree.root.containsMarked();
      final currentShard = store.getShard(rootAddr) ??
          LocatedPrunableTree<H>(
              rootAddr: rootAddr, root: PrunableTree.empty(hashContext));
      final result = currentShard.insertSubtree(
          subtree: subtree, containsMarked: containsMarked);
      store.putShard(result.subtree);
      allIncomplete.addAll(result.incomplete);
    }
    // Add checkpoints associated with this tree
    for (final entry in checkpoints.entries) {
      store.addCheckpoint(entry.key, Checkpoint.atPosition(entry.value));
    }
    _pruneExcessCheckpoints();
    return allIncomplete;
  }

  (H, PrunableTree<H>?) _rootInternal(
      {required LocatedPrunableTree<H> cap,
      required NodeAddress targetAddr,
      required LeafPosition truncateAt}) {
    return cap.root.node.fold(
      onParent: (left, right, ann) {
        if (ann != null && targetAddr.contains(cap.rootAddr)) {
          return (ann, null);
        }
        final (lAddr, rAddr) = cap.rootAddr.children();
        (H, PrunableTree<H>?)? lResult;
        (H, PrunableTree<H>?)? rResult;
        if (!rAddr.contains(targetAddr)) {
          lResult = _rootInternal(
              cap: LocatedPrunableTree<H>(rootAddr: lAddr, root: left),
              targetAddr: lAddr.contains(targetAddr) ? targetAddr : lAddr,
              truncateAt: truncateAt);
        }
        if (!lAddr.contains(targetAddr)) {
          rResult = _rootInternal(
              cap: LocatedPrunableTree<H>(rootAddr: rAddr, root: right),
              targetAddr: rAddr.contains(targetAddr) ? targetAddr : rAddr,
              truncateAt: truncateAt);
        }
        (H, PrunableTree<H>?, PrunableTree<H>?) result;
        if (lResult != null && rResult != null) {
          result = (
            store.hashContext
                .combine(level: lAddr.level, a: lResult.$1, b: rResult.$1),
            lResult.$2,
            rResult.$2
          );
        } else if (lResult != null) {
          result = (lResult.$1, lResult.$2, null);
        } else if (rResult != null) {
          result = (rResult.$1, null, rResult.$2);
        } else {
          throw MerkleTreeException.failed("rootInternal");
        }
        final lV = result.$2?.nodeValue();
        final rV = result.$3?.nodeValue();

        PrunableTree<H> newParent = PrunableTree<H>(
            hashContext: store.hashContext,
            node: NodeParent(
                ann: lV != null && rV != null
                    ? store.hashContext
                        .combine(level: lAddr.level, a: lV, b: rV)
                    : null,
                left: result.$2 ?? emptyTree,
                right: result.$3 ?? emptyTree));
        return (result.$1, newParent);
      },
      onLeaf: (v) {
        if (truncateAt >= cap.rootAddr.positionRangeEnd() &&
            targetAddr.contains(cap.rootAddr)) {
          return (v.value, null);
        }
        final result = _rootInternal(
            cap: LocatedPrunableTree<H>(
                rootAddr: cap.rootAddr,
                root: PrunableTree<H>(
                    hashContext: store.hashContext,
                    node: NodeParent(
                        ann: null, left: emptyTree, right: emptyTree))),
            targetAddr: targetAddr,
            truncateAt: truncateAt);
        return (result.$1, result.$2?.reannotateRoot(v.value));
      },
      onNil: () {
        if (cap.rootAddr == targetAddr || cap.rootAddr.level == subtreeLevel) {
          final result =
              _rootFromShards(address: targetAddr, truncateAt: truncateAt);
          if (truncateAt >= cap.rootAddr.positionRangeStart()) {
            return (
              result,
              PrunableTree<H>(
                  hashContext: store.hashContext,
                  node: NodeLeaf(
                      value: PrunableValue<H>(
                          value: result, flags: RetentionFlags.ephemeral)))
            );
          }
          return (result, null);
        }
        return _rootInternal(
            cap: LocatedPrunableTree<H>(
                rootAddr: cap.rootAddr,
                root: PrunableTree<H>(
                    hashContext: store.hashContext,
                    node: NodeParent(
                        ann: null, left: emptyTree, right: emptyTree))),
            targetAddr: targetAddr,
            truncateAt: truncateAt);
      },
    );
  }

  H _rootFromShards(
      {required NodeAddress address, required LeafPosition truncateAt}) {
    return address.getContext<H>(
      level: subtreeLevel,
      right: (position) {
        List<(NodeAddress, H)> rootStack = [];
        final List<NodeAddress> incomplete = [];
        for (final i in position) {
          final subtreeAddr = NodeAddress(level: subtreeLevel, index: i);
          if (truncateAt <= subtreeAddr.positionRangeStart()) {
            break;
          }
          final subtreeRoot = store.getShard(subtreeAddr)?.rootHash(truncateAt);
          if (subtreeRoot == null) {
            incomplete.add(subtreeAddr);
          } else {
            if (subtreeAddr.index.isEven) {
              rootStack.add((subtreeAddr, subtreeRoot));
            } else {
              NodeAddress curAddr = subtreeAddr;
              H curHash = subtreeRoot;
              while (rootStack.isNotEmpty) {
                final (addr, hash) = rootStack.removeLast();
                if (addr.parent() == curAddr.parent()) {
                  curHash = store.hashContext
                      .combine(level: curAddr.level, a: hash, b: curHash);
                  curAddr = curAddr.parent();
                } else {
                  rootStack.add((addr, hash));
                  break;
                }
              }
              rootStack.add((curAddr, curHash));
            }
          }
        }
        if (incomplete.isNotEmpty) {
          throw MerkleTreeException.failed("rootFromShards",
              reason: "Unable to compute root. missing values for nodes.",
              details: {"addresses": incomplete});
        }
        if (rootStack.isNotEmpty) {
          var (curAddr, curHash) = rootStack.removeLast();

          while (rootStack.isNotEmpty) {
            final (addr, hash) = rootStack.removeLast();

            while (addr.level > curAddr.level) {
              curHash = store.hashContext.combine(
                level: curAddr.level,
                a: curHash,
                b: store.hashContext.emptyRoot(curAddr.level),
              );
              curAddr = curAddr.parent();
            }
            curHash = store.hashContext
                .combine(level: curAddr.level, a: hash, b: curHash);
            curAddr = curAddr.parent();
          }

          while (curAddr.level < address.level) {
            curHash = store.hashContext.combine(
              level: curAddr.level,
              a: curHash,
              b: store.hashContext.emptyRoot(curAddr.level),
            );
            curAddr = curAddr.parent();
          }

          return curHash;
        } else {
          return store.hashContext.emptyRoot(address.level);
        }
      },
      left: (addr) {
        if (truncateAt <= address.positionRangeStart()) {
          return store.hashContext.emptyRoot(address.level);
        }
        final hash =
            store.getShard(addr)?.subtree(address)?.rootHash(truncateAt);
        if (hash == null) {
          throw MerkleTreeException.failed("rootFromShards",
              reason: "Unable to compute root. missing values for nodes.",
              details: {"address": addr});
        }
        return hash;
      },
    );
  }

  void _pruneExcessCheckpoints() {
    int checkpointCount = store.checkpointCount();
    if (checkpointCount > maxCheckpoints) {
      final removeCount = checkpointCount - maxCheckpoints;
      final List<dynamic> checkpointsToDelete = [];
      final Map<NodeAddress, Map<LeafPosition, RetentionFlags>> clearPositions =
          {};

      // Iterate through checkpoints
      store.withCheckpoints(checkpointCount, (cid, checkpoint) {
        final removing = checkpointsToDelete.length < removeCount;

        if (removing) {
          checkpointsToDelete.add(cid);
        }

        void clearAt(LeafPosition pos, RetentionFlags flagsToClear) {
          final subtreeAddr = this.subtreeAddr(pos);

          if (removing) {
            clearPositions.putIfAbsent(subtreeAddr, () => {}).update(pos,
                (flags) {
              return flags | flagsToClear;
            }, ifAbsent: () => flagsToClear);
          } else {
            final toClear = clearPositions[subtreeAddr];
            if (toClear != null && toClear.containsKey(pos)) {
              toClear[pos] = toClear[pos]! & ~flagsToClear;
            }
          }
        }

        // Clear or preserve the checkpoint leaf
        final treeState = checkpoint.treeState;
        if (treeState case TreeStateAtPosition state) {
          clearAt(state.position, RetentionFlags.checkpoint);
        }
        // Clear or preserve leaves marked for removal
        for (var pos in checkpoint.marksRemoved()) {
          clearAt(pos, RetentionFlags.marked);
        }
      });

      // Remove fully cleared positions
      clearPositions.removeWhere((_, positions) {
        positions.removeWhere((_, flags) => flags.isEmpty);
        return positions.isEmpty;
      });

      // Prune each affected subtree
      clearPositions.forEach((subtreeAddr, positions) {
        LocatedPrunableTree<H>? shard = store.getShard(subtreeAddr);

        if (shard != null) {
          final cleared = shard.clearFlags(positions);
          store.putShard(cleared);
        }
      });

      // Remove the checkpoints
      for (var c in checkpointsToDelete) {
        store.removeCheckpoint(c);
      }
    }
  }

  /// witness
  MERKLEPATH _witnessInternalCaching({
    required LeafPosition position,
    required LeafPosition asOf,
  }) {
    final subtree = subtreeAddr(position);
    final witness = store
        .getShard(subtree)
        ?.witness(position: position, truncateAt: asOf + 1);
    if (witness == null) {
      throw MerkleTreeException.failed("witnessInternalCaching",
          reason: "Unable to compute root. missing values for nodes.",
          details: {"address": subtree});
    }
    final rootAddr = this.rootAddr;
    NodeAddress curAddr = subtree;
    while (curAddr != rootAddr) {
      final root =
          rootCaching(address: curAddr.sibling(), truncateAt: asOf + 1);
      witness.add(root);
      curAddr = curAddr.parent();
    }
    assert(witness.length == depth);
    return toMerklePath(position, witness);
  }

  MERKLEPATH _wintessInternal({
    required LeafPosition position,
    required LeafPosition asOf,
  }) {
    final subtree = subtreeAddr(position);
    final witness = store
        .getShard(subtree)
        ?.witness(position: position, truncateAt: asOf + 1);
    if (witness == null) {
      throw MerkleTreeException.failed("wintessInternal",
          reason: "Unable to compute root. missing values for nodes.",
          details: {"address": subtree});
    }
    // final w = witness.unwrap();
    final rootAddr = this.rootAddr;
    NodeAddress curAddr = subtree;
    while (curAddr != rootAddr) {
      final path = root(address: curAddr.sibling(), truncateAt: asOf + 1);
      witness.add(path);
      curAddr = curAddr.parent();
    }
    assert(witness.length == depth);
    return toMerklePath(position, witness);
  }
}
