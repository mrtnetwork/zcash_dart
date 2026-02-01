import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/merkle/tree/shard_tree.dart';
import 'package:zcash_dart/src/merkle/store/memory.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/src/note_encryption.dart';
import 'package:zcash_dart/src/orchard/transaction/commitment.dart';

class OrchardAnchor with LayoutSerializable, Equality {
  final PallasNativeFp inner;
  const OrchardAnchor(this.inner);
  factory OrchardAnchor.fromBytes(List<int> bytes) {
    return OrchardAnchor(PallasNativeFp.fromBytes(bytes));
  }
  factory OrchardAnchor.emptyTree() {
    return OrchardAnchor(PallasNativeFp.nP(BigInt.parse(
        "21641924050683187072471021765392292010168693068998734505527562100199019325870")));
  }
  factory OrchardAnchor.deserializeJson(Map<String, dynamic> json) {
    return OrchardAnchor.fromBytes(json.valueAsBytes("inner"));
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

  @override
  List<dynamic> get variables => [inner];
}

class OrchardMerkleHash with Equality, LayoutSerializable {
  final PallasNativeFp inner;
  const OrchardMerkleHash(this.inner);

  factory OrchardMerkleHash.deserializeJson(Map<String, dynamic> json) =>
      OrchardMerkleHash.fromBytes(json.valueAsBytes("inner"));

  factory OrchardMerkleHash.fromBytes(List<int> bytes) {
    return OrchardMerkleHash(PallasNativeFp.fromBytes(bytes));
  }
  factory OrchardMerkleHash.dummy() =>
      OrchardMerkleHash(PallasNativeFp.random());

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
    return {"inner": toBytes()};
  }

  List<int> toBytes() => inner.toBytes();

  OrchardAnchor toAnchor() => OrchardAnchor(inner);

  @override
  List<dynamic> get variables => [inner];
}

class OrchardMerkleHashable extends Hashable<OrchardMerkleHash> {
  OrchardMerkleHashable({HashDomainNative? domain})
      : domain =
            domain ?? HashDomainNative.fromDomain("z.cash:Orchard-MerkleCRH");
  final PallasNativeFp _uncommited = PallasNativeFp.two();
  final HashDomainNative domain;
  List<OrchardMerkleHash> _buildEmptyRoots() {
    final List<OrchardMerkleHash> emptyRoots = [];
    var state = emptyLeaf();
    emptyRoots.add(state);
    for (int level = 0;
        level < NoteEncryptionConst.noteCommitmentTreeDepth;
        level++) {
      state = combine(level: TreeLevel(level), a: state, b: state);
      emptyRoots.add(state);
    }
    return emptyRoots.immutable;
  }

  late final List<OrchardMerkleHash> emptyRoots = _buildEmptyRoots();

  @override
  OrchardMerkleHash combine(
      {required TreeLevel level,
      required OrchardMerkleHash a,
      required OrchardMerkleHash b}) {
    final lhsBits = a.inner.toBits();
    final rhsBits = b.inner.toBits();
    final base = domain.hash([
      ...BigintUtils.toBinaryBool(BigInt.from(level.value),
          bitLength: HashDomainConst.K),
      ...lhsBits.sublist(0, HashDomainConst.lOrchardMerkle),
      ...rhsBits.sublist(0, HashDomainConst.lOrchardMerkle)
    ]);
    return OrchardMerkleHash(base ?? PallasNativeFp.zero());
  }

  @override
  OrchardMerkleHash emptyLeaf() {
    return OrchardMerkleHash(_uncommited);
  }

  @override
  OrchardMerkleHash emptyRoot(TreeLevel level) {
    return emptyRoots[level.value];
  }
}

class OrchardMerklePath extends MerklePath<OrchardMerkleHash>
    with LayoutSerializable, Equality {
  OrchardMerklePath._(
      {required super.position,
      required List<OrchardMerkleHash> authPath,
      required int depth})
      : super(
            authPath: authPath
                .exc(
                    length: depth,
                    operation: "OrchardMerklePath",
                    reason: "Invalid auth path length.")
                .immutable);
  OrchardMerklePath(
      {required super.position, required List<OrchardMerkleHash> authPath})
      : super(
            authPath: authPath
                .exc(
                    length: NoteEncryptionConst.noteCommitmentTreeDepth,
                    operation: "OrchardMerklePath",
                    reason: "Invalid auth path length.")
                .immutable);
  factory OrchardMerklePath.dummy() {
    return OrchardMerklePath(
        position: LeafPosition(QuickCrypto.nextU32()),
        authPath: List.generate(NoteEncryptionConst.noteCommitmentTreeDepth,
            (_) => OrchardMerkleHash.dummy()));
  }

  factory OrchardMerklePath.deserializeJson(Map<String, dynamic> json) {
    return OrchardMerklePath(
        position: LeafPosition(json.valueAsInt("position")),
        authPath: json
            .valueEnsureAsList<Map<String, dynamic>>("auth_path")
            .map((e) => OrchardMerkleHash.deserializeJson(e))
            .toList());
  }

  OrchardAnchor root(
      {required OrchardExtractedNoteCommitment cmx,
      required OrchardMerkleHashable hashContext}) {
    final r = authPath.indexed.fold(OrchardMerkleHash(cmx.inner), (node, r) {
      final int l = r.$1;
      final sibling = r.$2;
      if ((position.position & (1 << l)) == 0) {
        return hashContext.combine(level: TreeLevel(l), a: node, b: sibling);
      } else {
        return hashContext.combine(level: TreeLevel(l), a: sibling, b: node);
      }
    });
    return OrchardAnchor(r.inner);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "position"),
      LayoutConst.array(OrchardMerkleHash.layout(),
          NoteEncryptionConst.noteCommitmentTreeDepth,
          property: "auth_path")
    ], property: property);
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

class OrchardShardStore extends MemoryShardStore<OrchardMerkleHash, int> {
  OrchardShardStore(super.hashable) : super.empty();
}

class OrchardShardTree extends ShardTree<
    OrchardMerkleHash,
    int,
    ShardStore<OrchardMerkleHash, int>,
    OrchardMerklePath> with LayoutSerializable {
  OrchardShardTree(ShardStore<OrchardMerkleHash, int> store,
      {super.shardHeight = NoteEncryptionConst.shardHeight,
      super.maxCheckpoints = 100,
      super.depth = NoteEncryptionConst.noteCommitmentTreeDepth})
      : super(store: store);

  factory OrchardShardTree.deserialize(
      {required List<int> bytes,
      required ShardStore<OrchardMerkleHash, int> store,
      int shardHeight = NoteEncryptionConst.shardHeight,
      int maxCheckpoints = 100,
      int depth = NoteEncryptionConst.noteCommitmentTreeDepth}) {
    final decode = OrchardSerializableShardTree.deserialize(
        bytes: bytes, hashable: store.hashContext);
    store.putCap(decode.cap);
    final level = TreeLevel(shardHeight);
    for (final i in decode.shards) {
      store.putShard(LocatedPrunableTree(
          root: i.tree, rootAddr: NodeAddress(level: level, index: i.index)));
    }
    for (final i in decode.checkpionts) {
      store.addCheckpoint(i.id, Checkpoint.fromState(i.state));
    }
    return OrchardShardTree(store,
        depth: depth, maxCheckpoints: maxCheckpoints, shardHeight: shardHeight);
  }

  @override
  OrchardMerklePath toMerklePath(
      LeafPosition position, List<OrchardMerkleHash> path) {
    return OrchardMerklePath._(
        position: position, authPath: path, depth: depth);
  }

  OrchardSerializableShardTree toSeriableShardTree() {
    final cap = store.getCap();
    final shardRoots = store.getShards();
    final checkpoints = store.getCheckpoints();
    return OrchardSerializableShardTree(
        cap: cap,
        shards: shardRoots
            .map((e) => OrchardSerializableTreeShard(
                index: e.rootAddr.index, tree: e.root))
            .toList(),
        checkpionts: checkpoints
            .map((e) =>
                SerializableTreeCheckpoint(id: e.key, state: e.value.treeState))
            .toList());
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return OrchardSerializableShardTree.layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return toSeriableShardTree().toSerializeJson();
  }
}

class OrchardCommitmentTree extends CommitmentTree<OrchardMerkleHash> {
  OrchardCommitmentTree(
      {required super.left, required super.right, super.parents});
  factory OrchardCommitmentTree.deserialize(List<int> bytes) {
    return OrchardCommitmentTree.deserializeJson(
        LayoutSerializable.deserialize(bytes: bytes, layout: layout()));
  }
  factory OrchardCommitmentTree.deserializeJson(Map<String, dynamic> json) {
    return OrchardCommitmentTree(
        left: json.valueTo<OrchardMerkleHash?, Map<String, dynamic>>(
          key: "left",
          parse: (v) {
            return OrchardMerkleHash.deserializeJson(v);
          },
        ),
        right: json.valueTo<OrchardMerkleHash?, Map<String, dynamic>>(
          key: "right",
          parse: (v) {
            return OrchardMerkleHash.deserializeJson(v);
          },
        ),
        parents: json
            .valueEnsureAsList<Map<String, dynamic>?>("parents")
            .map((e) => e == null ? null : OrchardMerkleHash.deserializeJson(e))
            .toList());
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.optional(OrchardMerkleHash.layout(), property: "left"),
      LayoutConst.optional(OrchardMerkleHash.layout(), property: "right"),
      LayoutConst.bcsVector(LayoutConst.optional(OrchardMerkleHash.layout()),
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

class OrchardSerializableTreeShard with LayoutSerializable {
  final int index;
  final PrunableTree<OrchardMerkleHash> tree;
  const OrchardSerializableTreeShard({required this.index, required this.tree});
  factory OrchardSerializableTreeShard.deserializeJson(
      {required Map<String, dynamic> json,
      required Hashable<OrchardMerkleHash> hashable}) {
    return OrchardSerializableTreeShard(
        index: json.valueAs("index"),
        tree: PrunableTree.deserializeJson(
            json: json.valueAs("tree"),
            hashContext: hashable,
            onParseNode: (json) => OrchardMerkleHash.deserializeJson(json)));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "index"),
      PrunableTree.layout(OrchardMerkleHash.layout(), property: "tree"),
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

class OrchardSerializableShardTree with LayoutSerializable {
  final PrunableTree<OrchardMerkleHash> cap;
  final List<OrchardSerializableTreeShard> shards;
  final List<SerializableTreeCheckpoint> checkpionts;
  const OrchardSerializableShardTree(
      {required this.cap, required this.shards, required this.checkpionts});
  factory OrchardSerializableShardTree.deserialize(
      {required List<int> bytes,
      required Hashable<OrchardMerkleHash> hashable}) {
    final json = LayoutSerializable.deserialize(bytes: bytes, layout: layout());
    return OrchardSerializableShardTree.deserializeJson(
        json: json, hashable: hashable);
  }
  factory OrchardSerializableShardTree.deserializeJson(
      {required Map<String, dynamic> json,
      required Hashable<OrchardMerkleHash> hashable}) {
    return OrchardSerializableShardTree(
        cap: PrunableTree.deserializeJson(
          json: json.valueAs("cap"),
          hashContext: hashable,
          onParseNode: (json) => OrchardMerkleHash.deserializeJson(json),
        ),
        shards: json
            .valueEnsureAsList<Map<String, dynamic>>("shards")
            .map((e) => OrchardSerializableTreeShard.deserializeJson(
                json: e, hashable: hashable))
            .toList(),
        checkpionts: json
            .valueEnsureAsList<Map<String, dynamic>>("checkpionts")
            .map((e) => SerializableTreeCheckpoint.deserializeJson(e))
            .toList());
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      PrunableTree.layout(OrchardMerkleHash.layout(), property: "cap"),
      LayoutConst.bcsVector(OrchardSerializableTreeShard.layout(),
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
