import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/merkle/tree/shard_tree.dart';
import 'package:zcash_dart/src/merkle/store/memory.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/src/note_encryption.dart';
import 'package:zcash_dart/src/pedersen_hash/src/hash.dart';
import 'package:zcash_dart/src/sapling/transaction/commitment.dart';

class SaplingNode with LayoutSerializable, Equality {
  final JubJubNativeFq inner;
  const SaplingNode(this.inner);
  factory SaplingNode.deserializeJson(Map<String, dynamic> json) =>
      SaplingNode.fromBytes(json.valueAsBytes("inner"));
  factory SaplingNode.fromBytes(List<int> bytes) {
    return SaplingNode(JubJubNativeFq.fromBytes(bytes));
  }
  factory SaplingNode.random() {
    return SaplingNode(JubJubNativeFq.random());
  }
  factory SaplingNode.fromCmu(SaplingExtractedNoteCommitment cmu) {
    return SaplingNode(cmu.inner);
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([LayoutConst.fixedBlob32(property: "inner")],
        property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner.toBytes()};
  }

  List<int> toBytes() => inner.toBytes();

  List<bool> toBits() => inner.toBits();

  SaplingAnchor toAnchor() => SaplingAnchor(inner);

  @override
  List<dynamic> get variables => [inner];
}

class SaplingAnchor with LayoutSerializable, Equality {
  final JubJubNativeFq inner;
  const SaplingAnchor(this.inner);
  factory SaplingAnchor.fromBytes(List<int> bytes) {
    return SaplingAnchor(JubJubNativeFq.fromBytes(bytes));
  }

  factory SaplingAnchor.emptyTree() {
    return SaplingAnchor(JubJubNativeFq.nP(BigInt.parse(
        "28173632385923246415274731176992492615790500778795336173196884897344578175739")));
  }

  factory SaplingAnchor.deserializeJson(Map<String, dynamic> json) =>
      SaplingAnchor.fromBytes(json.valueAsBytes("inner"));

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner.toBytes()};
  }

  List<int> toBytes() => inner.toBytes();
  @override
  List<dynamic> get variables => [inner];
}

class SaplingMerklePath extends MerklePath<SaplingNode>
    with LayoutSerializable, Equality {
  SaplingMerklePath(
      {required super.position, required List<SaplingNode> authPath})
      : super(
            authPath: authPath.exc(
                length: NoteEncryptionConst.noteCommitmentTreeDepth,
                operation: "SaplingMerklePath",
                reason: "Invalid auth path length."));
  factory SaplingMerklePath.deserializeJson(Map<String, dynamic> json) {
    return SaplingMerklePath(
        position: LeafPosition(json.valueAsInt("position")),
        authPath: json
            .valueEnsureAsList<Map<String, dynamic>>("auth_path")
            .map((e) => SaplingNode.deserializeJson(e))
            .toList());
  }
  factory SaplingMerklePath.random({int position = 0}) => SaplingMerklePath(
      position: LeafPosition(position),
      authPath: List.generate(NoteEncryptionConst.noteCommitmentTreeDepth,
          (_) => SaplingNode.random()));

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "position"),
      LayoutConst.array(
          SaplingNode.layout(), NoteEncryptionConst.noteCommitmentTreeDepth,
          property: "auth_path")
    ], property: property);
  }

  SaplingAnchor root(SaplingNode leaf, SaplingMerkleHashable hashable) {
    final root = authPath.indexed.fold(
      leaf,
      (currentRoot, entry) {
        final int level = entry.$1;
        final sibling = entry.$2;

        if (((position.position >> level) & 0x01) == 0) {
          return hashable.combine(
              level: TreeLevel(level), a: currentRoot, b: sibling);
        } else {
          return hashable.combine(
              level: TreeLevel(level), a: sibling, b: currentRoot);
        }
      },
    );

    return SaplingAnchor(root.inner);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "position": position.position,
      "auth_path": authPath.map((e) => e.toSerializeJson()).toList()
    };
  }

  @override
  List<dynamic> get variables => [position, authPath];
}

class SaplingMerkleHashable extends Hashable<SaplingNode> {
  SaplingMerkleHashable(this.hash);
  final PedersenHashNative hash;
  late final List<SaplingNode> emptyRoots = _buildEmptyRoots();

  List<SaplingNode> _buildEmptyRoots() {
    final List<SaplingNode> v = [emptyLeaf()];
    for (int d = 0; d < NoteEncryptionConst.noteCommitmentTreeDepth; d++) {
      final next = combine(level: TreeLevel(d), a: v[d], b: v[d]);
      v.add(next);
    }
    return v.immutable;
  }

  @override
  SaplingNode combine(
      {required TreeLevel level,
      required SaplingNode a,
      required SaplingNode b}) {
    final n = hash.hash(
        personalization: PersonalizationMerkleTree(level.value),
        inputBits: [
          ...a.toBits().sublist(0, JubJubFqConst.bits),
          ...b.toBits().sublist(0, JubJubFqConst.bits),
        ]);
    return SaplingNode(n.toAffine().u);
  }

  @override
  SaplingNode emptyLeaf() {
    return SaplingNode(JubJubNativeFq.one());
  }

  @override
  SaplingNode emptyRoot(TreeLevel level) {
    return emptyRoots[level.value];
  }
}

class SaplingShardStore extends MemoryShardStore<SaplingNode, int> {
  SaplingShardStore(SaplingMerkleHashable super.hashable) : super.empty();
}

class SaplingShardTree extends ShardTree<SaplingNode, int,
    ShardStore<SaplingNode, int>, SaplingMerklePath> with LayoutSerializable {
  SaplingShardTree(ShardStore<SaplingNode, int> store)
      : super(
            depth: NoteEncryptionConst.noteCommitmentTreeDepth,
            shardHeight: NoteEncryptionConst.shardHeight,
            maxCheckpoints: 100,
            store: store);

  factory SaplingShardTree.deserialize(
      {required List<int> bytes, required ShardStore<SaplingNode, int> store}) {
    final decode = SaplingSerializableShardTree.deserialize(
        bytes: bytes, hashable: store.hashContext);
    store.putCap(decode.cap);
    final level = TreeLevel(NoteEncryptionConst.shardHeight);
    for (final i in decode.shards) {
      store.putShard(LocatedPrunableTree(
          root: i.tree, rootAddr: NodeAddress(level: level, index: i.index)));
    }
    for (final i in decode.checkpionts) {
      store.addCheckpoint(i.id, Checkpoint.fromState(i.state));
    }
    return SaplingShardTree(store);
  }

  @override
  SaplingMerklePath toMerklePath(
      LeafPosition position, List<SaplingNode> path) {
    return SaplingMerklePath(position: position, authPath: path);
  }

  SaplingSerializableShardTree toSeriableShardTree() {
    final cap = store.getCap();
    final shardRoots = store.getShards();
    final checkpoints = store.getCheckpoints();
    return SaplingSerializableShardTree(
        cap: cap,
        shards: shardRoots
            .map((e) => SaplingSerializableTreeShard(
                index: e.rootAddr.index, tree: e.root))
            .toList(),
        checkpionts: checkpoints
            .map((e) =>
                SerializableTreeCheckpoint(id: e.key, state: e.value.treeState))
            .toList());
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return SaplingSerializableShardTree.layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return toSeriableShardTree().toSerializeJson();
  }
}

class SaplingCommitmentTree extends CommitmentTree<SaplingNode> {
  SaplingCommitmentTree(
      {required super.left, required super.right, super.parents});
  factory SaplingCommitmentTree.deserialize(List<int> bytes) {
    return SaplingCommitmentTree.deserializeJson(
        LayoutSerializable.deserialize(bytes: bytes, layout: layout()));
  }
  factory SaplingCommitmentTree.deserializeJson(Map<String, dynamic> json) {
    return SaplingCommitmentTree(
        left: json.valueTo<SaplingNode?, Map<String, dynamic>>(
          key: "left",
          parse: (v) {
            return SaplingNode.deserializeJson(v);
          },
        ),
        right: json.valueTo<SaplingNode?, Map<String, dynamic>>(
          key: "right",
          parse: (v) {
            return SaplingNode.deserializeJson(v);
          },
        ),
        parents: json
            .valueEnsureAsList<Map<String, dynamic>?>("parents")
            .map((e) => e == null ? null : SaplingNode.deserializeJson(e))
            .toList());
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.optional(SaplingNode.layout(), property: "left"),
      LayoutConst.optional(SaplingNode.layout(), property: "right"),
      LayoutConst.bcsVector(LayoutConst.optional(SaplingNode.layout()),
          property: "parents")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  int get depth => NoteEncryptionConst.noteCommitmentTreeDepth;

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "left": left?.toSerializeJson(),
      "right": right?.toSerializeJson(),
      "parents": parents.map((e) => e?.toSerializeJson()).toList()
    };
  }
}

class SaplingSerializableTreeShard with LayoutSerializable {
  final int index;
  final PrunableTree<SaplingNode> tree;
  const SaplingSerializableTreeShard({required this.index, required this.tree});
  factory SaplingSerializableTreeShard.deserializeJson(
      {required Map<String, dynamic> json,
      required Hashable<SaplingNode> hashable}) {
    return SaplingSerializableTreeShard(
        index: json.valueAs("index"),
        tree: PrunableTree.deserializeJson(
            json: json.valueAs("tree"),
            hashContext: hashable,
            onParseNode: (json) => SaplingNode.deserializeJson(json)));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "index"),
      PrunableTree.layout(SaplingNode.layout(), property: "tree"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"index": index, "tree": tree.toSerializeJson()};
  }
}

class SaplingSerializableShardTree with LayoutSerializable {
  final PrunableTree<SaplingNode> cap;
  final List<SaplingSerializableTreeShard> shards;
  final List<SerializableTreeCheckpoint> checkpionts;
  const SaplingSerializableShardTree(
      {required this.cap, required this.shards, required this.checkpionts});
  factory SaplingSerializableShardTree.deserialize(
      {required List<int> bytes, required Hashable<SaplingNode> hashable}) {
    final json = LayoutSerializable.deserialize(bytes: bytes, layout: layout());
    return SaplingSerializableShardTree.deserializeJson(
        json: json, hashable: hashable);
  }
  factory SaplingSerializableShardTree.deserializeJson(
      {required Map<String, dynamic> json,
      required Hashable<SaplingNode> hashable}) {
    return SaplingSerializableShardTree(
        cap: PrunableTree.deserializeJson(
          json: json.valueAs("cap"),
          hashContext: hashable,
          onParseNode: (json) => SaplingNode.deserializeJson(json),
        ),
        shards: json
            .valueEnsureAsList<Map<String, dynamic>>("shards")
            .map((e) => SaplingSerializableTreeShard.deserializeJson(
                json: e, hashable: hashable))
            .toList(),
        checkpionts: json
            .valueEnsureAsList<Map<String, dynamic>>("checkpionts")
            .map((e) => SerializableTreeCheckpoint.deserializeJson(e))
            .toList());
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      PrunableTree.layout(SaplingNode.layout(), property: "cap"),
      LayoutConst.bcsVector(SaplingSerializableTreeShard.layout(),
          property: "shards"),
      LayoutConst.bcsVector(SerializableTreeCheckpoint.layout(),
          property: "checkpionts")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "cap": cap.toSerializeJson(),
      "shards": shards.map((e) => e.toSerializeJson()).toList(),
      "checkpionts": checkpionts.map((e) => e.toSerializeJson()).toList()
    };
  }
}
