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
      ironwoodNotes: [],
      orchardAnchor: OrchardAnchor.emptyTree(),
      saplingAnchor: SaplingAnchor.emptyTree(),
      ironwoodAnchor: OrchardAnchor.emptyTree(),
    );
  }
  final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
  orchardNotes;
  final List<ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
  saplingNotes;

  /// Ironwood-pool notes (NU6.3 second slot). Ironwood notes are
  /// Orchard-shaped, so they share the Orchard output and path types and
  /// anchor on an Orchard-typed root.
  final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
  ironwoodNotes;
  final OrchardAnchor orchardAnchor;
  final SaplingAnchor saplingAnchor;

  /// Anchor of the Ironwood pool at the witness height.
  final OrchardAnchor ironwoodAnchor;
  BuildMerleOutput({
    required List<
      ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>
    >
    orchardNotes,
    required List<
      ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>
    >
    saplingNotes,
    required List<
      ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>
    >
    ironwoodNotes,
    required this.orchardAnchor,
    required this.saplingAnchor,
    required this.ironwoodAnchor,
  }) : orchardNotes = orchardNotes.immutable,
       saplingNotes = saplingNotes.immutable,
       ironwoodNotes = ironwoodNotes.immutable;
  ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>
  getSaplingOutput(SaplingScannedOutput output) {
    return saplingNotes.firstWhere(
      (e) => e.output == output,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching ScannedOutputWithMerkle found for the given value. null",
              ),
    );
  }

  ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>
  getOrchardOutput(OrchardScannedOutput output) {
    return orchardNotes.firstWhere(
      (e) => e.output == output,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching ScannedOutputWithMerkle found for the given value. null",
              ),
    );
  }

  ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>
  getIronwoodOutput(OrchardScannedOutput output) {
    return ironwoodNotes.firstWhere(
      (e) => e.output == output,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching ScannedOutputWithMerkle found for the given value. null",
              ),
    );
  }

  int get totalNotes =>
      orchardNotes.length + saplingNotes.length + ironwoodNotes.length;
}

/// Lightweight summary of one [NativeMerkleController.updateState] batch.
///
/// Pure-Rust controllers track no Dart shard trees, so there is no tree
/// report to merge: the controller itself is the state and [NativeMerkleState]
/// bytes (see [NativeMerkleController.serialize]) are the persistence unit.
/// The report only carries the covered heights and per-pool tip sizes.
class NativeMerkleInsertReport {
  /// First scanned block of the batch.
  final int height;

  /// Last scanned block of the batch.
  final int lastHeight;

  /// Per-pool note-commitment tree sizes at [lastHeight].
  final int finalSaplingTree;
  final int finalOrchardTree;
  final int finalIronwoodTree;

  const NativeMerkleInsertReport({
    required this.height,
    required this.lastHeight,
    required this.finalSaplingTree,
    required this.finalOrchardTree,
    required this.finalIronwoodTree,
  });

  @override
  String toString() {
    return "NativeMerkleInsertReport {height: $height, lastHeight: $lastHeight, "
        "sapling: $finalSaplingTree, orchard: $finalOrchardTree, "
        "ironwood: $finalIronwoodTree}";
  }
}

/// Pure-Rust merkle persistence: the exact tip-leaf journal plus the
/// absorbed-subtree indices, CBOR-encoded for the wallet database.
///
/// Restoring from these bytes rebuilds an identical Rust mirror: completed
/// subtree roots are re-fetched from lightwalletd and journal tip leaves
/// are re-appended, then checkpoints are replayed. No Dart shard trees are
/// involved (see [NativeMerkleController]).
class NativeMerkleState with CborTagSerializable {
  /// Tip-leaf journal for the native mirror (sapling/orchard/ironwood).
  final MirrorTipJournal journal;

  /// Last absorbed subtree index per pool (exclusive fetch cursor: the next
  /// fetch starts at `index + 1`).
  final int saplingSubtreeIndex;
  final int orchardSubtreeIndex;
  final int ironwoodSubtreeIndex;

  const NativeMerkleState({
    this.journal = const MirrorTipJournal(),
    this.saplingSubtreeIndex = 0,
    this.orchardSubtreeIndex = 0,
    this.ironwoodSubtreeIndex = 0,
  });

  factory NativeMerkleState.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.nativeMerkleState,
      cborBytes: bytes,
      cborObject: object,
    );
    MirrorTipJournal journal = const MirrorTipJournal();
    try {
      final journalObj = values.objectAt<CborObject?>(3);
      final decoded = MirrorTipJournal.tryDecode(journalObj);
      if (decoded != null) journal = decoded;
    } catch (_) {
      // Missing or malformed journal item: treat as empty.
    }
    return NativeMerkleState(
      saplingSubtreeIndex: values.rawValueAt(0),
      orchardSubtreeIndex: values.rawValueAt(1),
      ironwoodSubtreeIndex: values.rawValueAt(2),
      journal: journal,
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.nativeMerkleState;

  @override
  List<CborObject?> get serializationItems => [
    saplingSubtreeIndex.toCbor(),
    orchardSubtreeIndex.toCbor(),
    ironwoodSubtreeIndex.toCbor(),
    journal.toCbor(),
  ];

  NativeMerkleState copyWith({
    MirrorTipJournal? journal,
    int? saplingSubtreeIndex,
    int? orchardSubtreeIndex,
    int? ironwoodSubtreeIndex,
  }) {
    return NativeMerkleState(
      journal: journal ?? this.journal,
      saplingSubtreeIndex: saplingSubtreeIndex ?? this.saplingSubtreeIndex,
      orchardSubtreeIndex: orchardSubtreeIndex ?? this.orchardSubtreeIndex,
      ironwoodSubtreeIndex: ironwoodSubtreeIndex ?? this.ironwoodSubtreeIndex,
    );
  }
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

  final SerializableTreeInsertReport<OrchardMerkleHash>? ironwood;
  final int height;
  final ChainState chainState;
  final int finalOrchardTree;
  final int finalSaplingTree;

  final int finalIronwoodTree;

  const SerializableMerkleInsertReport({
    this.sapling,
    this.orchard,
    required this.height,
    required this.finalOrchardTree,
    required this.finalSaplingTree,
    required this.chainState,
    this.ironwood,
    required this.finalIronwoodTree,
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
    final ironwoodObj = values.objectAt<CborObject?>(6);
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
      ironwood:
          ironwoodObj == null
              ? null
              : SerializableTreeInsertReport.deserialize(
                hashContext: orchardHashable,
                fromBytes: OrchardMerkleHash.fromBytes,
                object: ironwoodObj,
              ),
      finalIronwoodTree: values.rawValueAt(7),
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
    ironwood?.toCbor(),
    finalIronwoodTree.toCbor(),
  ];

  SerializableMerkleInsertReport copyWith({
    SerializableTreeInsertReport<SaplingNode>? sapling,
    SerializableTreeInsertReport<OrchardMerkleHash>? orchard,
    int? height,
    ChainState? chainState,
    int? finalOrchardTree,
    int? finalSaplingTree,
    SerializableTreeInsertReport<OrchardMerkleHash>? ironwood,
    int? finalIronwoodTree,
  }) {
    return SerializableMerkleInsertReport(
      sapling: sapling ?? this.sapling,
      orchard: orchard ?? this.orchard,
      height: height ?? this.height,
      chainState: chainState ?? this.chainState,
      finalOrchardTree: finalOrchardTree ?? this.finalOrchardTree,
      finalSaplingTree: finalSaplingTree ?? this.finalSaplingTree,
      ironwood: ironwood ?? this.ironwood,
      finalIronwoodTree: finalIronwoodTree ?? this.finalIronwoodTree,
    );
  }
}

/// Tip-leaf journal for exact native-mirror restore (no opaque blob).
///
/// Per pool (sapling, orchard, ironwood, in that order) the journal covers a
/// contiguous tip range `[base, base + leaves.length ~/ 32)` plus the
/// checkpoints snapshotted while it was maintained. Old states (written
/// before journals existed, or holding a legacy blob byte-string at this
/// slot) decode to `null` and restore Dart trees only.
class PoolTipJournal {
  /// First leaf position covered.
  final int base;

  /// Concatenated 32-byte leaf hashes, positions `[base, ...)`.
  final List<int> leaves;

  /// Checkpoint id -> tree size at snapshot.
  final Map<int, int> checkpoints;
  const PoolTipJournal({
    this.base = 0,
    this.leaves = const [],
    Map<int, int>? checkpoints,
  }) : checkpoints = checkpoints ?? const {};

  /// Number of leaves covered.
  int get length => leaves.length ~/ 32;

  /// Tree size at the journal tip.
  int get tipSize => base + length;

  bool get isEmpty => leaves.isEmpty && checkpoints.isEmpty && base == 0;
}

/// Exact tip journals for the three native pools, in
/// sapling/orchard/ironwood order.
class MirrorTipJournal {
  final PoolTipJournal sapling;
  final PoolTipJournal orchard;
  final PoolTipJournal ironwood;
  const MirrorTipJournal({
    this.sapling = const PoolTipJournal(),
    this.orchard = const PoolTipJournal(),
    this.ironwood = const PoolTipJournal(),
  });

  bool get isEmpty => sapling.isEmpty && orchard.isEmpty && ironwood.isEmpty;

  /// Lenient decode: any shape mismatch yields null (caller falls back to
  /// mirrorless operation), never throws.
  static MirrorTipJournal? tryDecode(CborObject? object) {
    try {
      // NOTE: objectAt/rawValueAt/value live on CborIterableObject, not on
      // the base CborObject, so cast to CborListValue before touching them.
      if (object is! CborListValue) return null;
      final top = object;
      if (top.value.length != 3) return null;
      PoolTipJournal pool(CborObject? o) {
        if (o is! CborListValue) throw const FormatException();
        if (o.value.length != 3) throw const FormatException();
        final base = o.rawValueAt<int>(0);
        final leaves = List<int>.from(o.objectAt<CborBytesValue>(1).value);
        final ckpts = o.objectAt<CborListValue>(2);
        final map = <int, int>{};
        for (var i = 0; i < ckpts.value.length; i++) {
          final e = ckpts.objectAt<CborListValue>(i);
          if (e.value.length != 2) throw const FormatException();
          final id = e.rawValueAt<int>(0);
          final size = e.rawValueAt<int>(1);
          if (id < 0 || size < 0 || leaves.length % 32 != 0) {
            throw const FormatException();
          }
          map[id] = size;
        }
        if (base < 0) throw const FormatException();
        return PoolTipJournal(base: base, leaves: leaves, checkpoints: map);
      }

      return MirrorTipJournal(
        sapling: pool(top.objectAt(0)),
        orchard: pool(top.objectAt(1)),
        ironwood: pool(top.objectAt(2)),
      );
    } catch (_) {
      return null;
    }
  }

  CborObject toCbor() {
    CborObject pool(PoolTipJournal p) {
      return CborListValue<CborObject>.definite(<CborObject>[
        p.base.toCbor(),
        CborBytesValue(p.leaves),
        CborListValue<CborObject>.definite(<CborObject>[
          for (final e in p.checkpoints.entries)
            CborListValue<CborObject>.definite(<CborObject>[
              e.key.toCbor(),
              e.value.toCbor(),
            ]),
        ]),
      ]);
    }

    return CborListValue<CborObject>.definite(<CborObject>[
      pool(sapling),
      pool(orchard),
      pool(ironwood),
    ]);
  }
}

class ChainMerkleState with CborTagSerializable {
  final SaplingShardTree sapling;
  final OrchardShardTree orchard;

  final OrchardShardTree ironwood;
  final int saplingSubtreeIndex;
  final int orchardSabtreeIndex;

  final int ironwoodSubtreeIndex;

  /// Tip-leaf journal for the native mirror (5th CBOR item). Null
  /// serializes as a CBOR null placeholder so later fixed-position items
  /// (ironwood subtree index at 6th, ironwood tree at 7th) keep stable
  /// indices. States written before journals existed decode a missing 5th
  /// item as null and restore Dart trees only.
  const ChainMerkleState({
    required this.sapling,
    required this.orchard,
    required this.saplingSubtreeIndex,
    required this.orchardSabtreeIndex,
    required this.ironwood,
    required this.ironwoodSubtreeIndex,
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
      ironwoodSubtreeIndex: values.rawValueAt(5),
      ironwood: OrchardShardTree.deserialize(
        store: OrchardShardStore(orchardHashable),
        object: values.objectAt(6),
      ),
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
    CborNullValue(),
    ironwoodSubtreeIndex.toCbor(),
    ironwood.toSerializableShardTree().toCbor(),
  ];

  ChainMerkleState copyWith({
    SaplingShardTree? sapling,
    OrchardShardTree? orchard,
    int? saplingSubtreeIndex,
    int? orchardSabtreeIndex,
    MirrorTipJournal? tipJournal,
    OrchardShardTree? ironwood,
    int? ironwoodSubtreeIndex,
  }) {
    return ChainMerkleState(
      sapling: sapling ?? this.sapling,
      orchard: orchard ?? this.orchard,
      saplingSubtreeIndex: saplingSubtreeIndex ?? this.saplingSubtreeIndex,
      orchardSabtreeIndex: orchardSabtreeIndex ?? this.orchardSabtreeIndex,
      ironwood: ironwood ?? this.ironwood,
      ironwoodSubtreeIndex: ironwoodSubtreeIndex ?? this.ironwoodSubtreeIndex,
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
