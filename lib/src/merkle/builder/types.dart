import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/merkle/store/store.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class ScannedOutputWithMerkle<
  OUTPUT extends ScannedOutput,
  MERKLE extends MerklePath
> {
  final OUTPUT output;
  final MERKLE merklePath;
  const ScannedOutputWithMerkle({
    required this.output,
    required this.merklePath,
  });
}

class BuildMerleOutput {
  factory BuildMerleOutput.empty() {
    return BuildMerleOutput(
      orchardNotes: [],
      saplingNotes: [],
      orchardAnchor: OrchardAnchor.emptyTree(),
      saplingAnchor: SaplingAnchor.emptyTree(),
    );
  }
  final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
  orchardNotes;
  final List<ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
  saplingNotes;
  final OrchardAnchor orchardAnchor;
  final SaplingAnchor saplingAnchor;
  BuildMerleOutput({
    required List<
      ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>
    >
    orchardNotes,
    required List<
      ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>
    >
    saplingNotes,
    required this.orchardAnchor,
    required this.saplingAnchor,
  }) : orchardNotes = orchardNotes.immutable,
       saplingNotes = saplingNotes.immutable;
  ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>
  getSaplingOutput(SaplingScannedOutput output) {
    return saplingNotes.firstWhere(
      (e) => e.output == output,
      orElse:
          () => throw ItemNotFoundException(name: "ScannedOutputWithMerkle"),
    );
  }

  ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>
  getOrchardOutput(OrchardScannedOutput output) {
    return orchardNotes.firstWhere(
      (e) => e.output == output,
      orElse:
          () => throw ItemNotFoundException(name: "ScannedOutputWithMerkle"),
    );
  }

  int get totalNotes => orchardNotes.length + saplingNotes.length;
}

class SerializableTreeInsertReport<H extends MerkleNodeValue>
    with CborTagSerializable {
  final LocatedPrunableTree<H> subtree;
  final List<SerializableTreeCheckpointPosition> checkpoints;
  const SerializableTreeInsertReport({
    required this.subtree,
    required this.checkpoints,
  });
  factory SerializableTreeInsertReport.deserialize({
    required Hashable<H> hashContext,
    required H Function(List<int> bytes) fromBytes,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.serializableTreeInsertReport,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableTreeInsertReport(
      subtree: LocatedPrunableTree<H>.deserialize(
        fromBytes: fromBytes,
        object: values.objectAt(0),
        hashContext: hashContext,
      ),
      checkpoints:
          values
              .listAt<CborTagValue>(1)
              .map(
                (e) =>
                    SerializableTreeCheckpointPosition.deserialize(object: e),
              )
              .toList(),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serializableTreeInsertReport;

  @override
  List<CborObject?> get serializationItems => [
    subtree.toCbor(),
    CborTagSerializable.listFromDynamic(
      checkpoints.map((e) => e.toCbor()).toList(),
    ),
  ];

  SerializableTreeInsertReport<H> copyWith({
    LocatedPrunableTree<H>? subtree,
    List<SerializableTreeCheckpointPosition>? checkpoints,
  }) {
    return SerializableTreeInsertReport<H>(
      subtree: subtree ?? this.subtree,
      checkpoints: checkpoints ?? this.checkpoints,
    );
  }

  @override
  String toString() {
    return "{checkpoints: $checkpoints}";
  }
}

class SerializableMerkleInsertReport with CborTagSerializable {
  final SerializableTreeInsertReport<SaplingNode>? sapling;
  final SerializableTreeInsertReport<OrchardMerkleHash>? orchard;
  final int height;
  final ChainState chainState;
  final int finalOrchardTree;
  final int finalSaplingTree;

  const SerializableMerkleInsertReport({
    this.sapling,
    this.orchard,
    required this.height,
    required this.finalOrchardTree,
    required this.finalSaplingTree,
    required this.chainState,
  });
  factory SerializableMerkleInsertReport.deserialize({
    required Hashable<OrchardMerkleHash> orchardHashable,
    required Hashable<SaplingNode> saplingHashable,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.serializableMerkleInsertReport,
      cborBytes: bytes,
      cborObject: object,
    );
    return SerializableMerkleInsertReport(
      orchard: values.maybeObjectAt<
        SerializableTreeInsertReport<OrchardMerkleHash>,
        CborTagValue
      >(
        0,
        (i) => SerializableTreeInsertReport.deserialize(
          hashContext: orchardHashable,
          fromBytes: OrchardMerkleHash.fromBytes,
          object: i,
        ),
      ),
      sapling: values.maybeObjectAt<
        SerializableTreeInsertReport<SaplingNode>,
        CborTagValue
      >(
        1,
        (i) => SerializableTreeInsertReport.deserialize(
          hashContext: saplingHashable,
          fromBytes: SaplingNode.fromBytes,
          object: i,
        ),
      ),
      height: values.rawValueAt(2),
      finalOrchardTree: values.rawValueAt(3),
      finalSaplingTree: values.rawValueAt(4),
      chainState: ChainState.deserialize(object: values.objectAt(5)),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.serializableMerkleInsertReport;

  @override
  List<CborObject?> get serializationItems => [
    orchard?.toCbor(),
    sapling?.toCbor(),
    height.toCbor(),
    finalOrchardTree.toCbor(),
    finalSaplingTree.toCbor(),
    chainState.toCbor(),
  ];

  SerializableMerkleInsertReport copyWith({
    SerializableTreeInsertReport<SaplingNode>? sapling,
    SerializableTreeInsertReport<OrchardMerkleHash>? orchard,
    int? height,
    ChainState? chainState,
    int? finalOrchardTree,
    int? finalSaplingTree,
  }) {
    return SerializableMerkleInsertReport(
      sapling: sapling ?? this.sapling,
      orchard: orchard ?? this.orchard,
      height: height ?? this.height,
      chainState: chainState ?? this.chainState,
      finalOrchardTree: finalOrchardTree ?? this.finalOrchardTree,
      finalSaplingTree: finalSaplingTree ?? this.finalSaplingTree,
    );
  }
}

class ChainMerkleState with CborTagSerializable {
  final SaplingShardTree sapling;
  final OrchardShardTree orchard;
  final int saplingSubtreeIndex;
  final int orchardSabtreeIndex;
  const ChainMerkleState({
    required this.sapling,
    required this.orchard,
    required this.saplingSubtreeIndex,
    required this.orchardSabtreeIndex,
  });
  factory ChainMerkleState.deserialize({
    required Hashable<OrchardMerkleHash> orchardHashable,
    required Hashable<SaplingNode> saplingHashable,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.chainMerkleState,
      cborBytes: bytes,
      cborObject: object,
    );
    return ChainMerkleState(
      sapling: SaplingShardTree.deserialize(
        store: SaplingShardStore(saplingHashable),
        object: values.objectAt(0),
      ),
      orchard: OrchardShardTree.deserialize(
        store: OrchardShardStore(orchardHashable),
        object: values.objectAt(1),
      ),
      saplingSubtreeIndex: values.rawValueAt(2),
      orchardSabtreeIndex: values.rawValueAt(3),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.chainMerkleState;

  @override
  List<CborObject?> get serializationItems => [
    sapling.toSerializableShardTree().toCbor(),
    orchard.toSerializableShardTree().toCbor(),
    saplingSubtreeIndex.toCbor(),
    orchardSabtreeIndex.toCbor(),
  ];

  ChainMerkleState copyWith({
    SaplingShardTree? sapling,
    OrchardShardTree? orchard,
    int? saplingSubtreeIndex,
    int? orchardSabtreeIndex,
  }) {
    return ChainMerkleState(
      sapling: sapling ?? this.sapling,
      orchard: orchard ?? this.orchard,
      saplingSubtreeIndex: saplingSubtreeIndex ?? this.saplingSubtreeIndex,
      orchardSabtreeIndex: orchardSabtreeIndex ?? this.orchardSabtreeIndex,
    );
  }
}

class SubtreeRoots with CborTagSerializable {
  final int start;
  final List<List<int>> hashes;

  SubtreeRoots({required this.start, required List<List<int>> hashes})
    : hashes =
          hashes
              .map((e) => e.exc(length: 32, operation: "SubtreeRoots"))
              .toImutableList;
  factory SubtreeRoots.deserialize({
    required Hashable<OrchardMerkleHash> orchardHashable,
    required Hashable<SaplingNode> saplingHashable,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.subtreeHashes,
      cborBytes: bytes,
      cborObject: object,
    );
    return SubtreeRoots(
      start: values.rawValueAt(0),
      hashes: values.listAt<CborBytesValue>(1).map((e) => e.value).toList(),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.subtreeHashes;

  @override
  List<CborObject?> get serializationItems => [
    start.toCbor(),
    CborTagSerializable.listFromDynamic(
      hashes.map((e) => CborBytesValue(e)).toList(),
    ),
  ];
}
