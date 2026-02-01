import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/exception.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/walletd/models/models.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transaction/sighash_digest/types.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';

abstract mixin class CompactBlock {
  int? get saplingCommitmentTreeSize;
  int? get orchardCommitmentTreeSize;
  int get height;
  List<int>? get hash;
  List<CompactTx>? get vtx;
  int? get time;

  List<CompactAction> getCompactActions() =>
      vtx?.expand((e) => e.getCompactActions()).toList() ?? [];
  List<CompactOutputDescription> getOutputDescription() =>
      vtx?.expand((e) => e.getOutputDescription()).toList() ?? [];
  List<SaplingNullifier> getSpends() =>
      vtx?.expand((e) => e.getSpends()).toList() ?? [];
  bool isValid() {
    return hash != null && time != null;
  }

  String? getHash() {
    final hash = this.hash;
    if (hash == null) return null;
    return BytesUtils.toHexString(hash);
  }

  int? timestamp() {
    return time;
  }

  int getHeight() {
    final height = this.height;
    return height.toU32;
  }

  int totalSaplingOutputs() =>
      vtx?.fold<int>(0, (p, c) => p + (c.outputs?.length ?? 0)) ?? 0;
  int totalOrchardOutputs() =>
      vtx?.fold<int>(0, (p, c) => p + (c.actions?.length ?? 0)) ?? 0;
}

abstract mixin class CompactOrchardAction implements Equality {
  List<int>? get nullifier;
  List<int>? get cmx;
  List<int>? get ephemeralKey;
  List<int>? get ciphertext;
  CompactAction toAction(int outputIndex) {
    final nullifier = this.nullifier;
    if (nullifier == null) {
      throw ZCashBlockScannerException.invalidCompact("action",
          reason: "Nullifier missing.");
    }

    final cmx = this.cmx;
    if (cmx == null) {
      throw ZCashBlockScannerException.invalidCompact("action",
          reason: "cmx missing.");
    }
    final ephemeralKey = this.ephemeralKey;
    if (ephemeralKey == null) {
      throw ZCashBlockScannerException.invalidCompact("action",
          reason: "ephemeralKey missing.");
    }
    final ciphertext = this.ciphertext;
    if (ciphertext == null) {
      throw ZCashBlockScannerException.invalidCompact("action",
          reason: "ciphertext missing.");
    }
    return CompactAction(
        nf: OrchardNullifier.fromBytes(nullifier),
        cmx: OrchardExtractedNoteCommitment(PallasNativeFp.fromBytes(cmx)),
        ephemeralKey: EphemeralKeyBytes(ephemeralKey),
        encCiphertextCompact: ciphertext,
        outputIndex: outputIndex);
  }
}

abstract mixin class CompactSaplingOutput implements Equality {
  List<int>? get cmu;
  List<int>? get ephemeralKey;
  List<int>? get ciphertext;
  bool isValid() => cmu != null && ephemeralKey != null && ciphertext != null;
  CompactOutputDescription toOutputDescription(int outputIndex) {
    final cmu = this.cmu;
    final ephemeralKey = this.ephemeralKey;
    final ciphertext = this.ciphertext;
    if (cmu == null || ephemeralKey == null || ciphertext == null) {
      throw ZCashBlockScannerException.invalidCompact("output");
    }
    return CompactOutputDescription(
        cmu: SaplingExtractedNoteCommitment(JubJubNativeFq.fromBytes(cmu)),
        ephemeralKey: EphemeralKeyBytes(ephemeralKey),
        encCiphertextCompact: ciphertext,
        outputIndex: outputIndex);
  }
}

abstract mixin class CompactSaplingSpend implements Equality {
  List<int>? get nf;
  bool isValid() => nf != null;
}

abstract mixin class CompactTx {
  int get index;
  List<int>? get hash;
  List<CompactSaplingSpend>? get spends;
  List<CompactSaplingOutput>? get outputs;
  List<CompactOrchardAction>? get actions;
  List<SaplingNullifier> getSpends() {
    final spends = this.spends;
    if (spends == null) return [];
    List<SaplingNullifier> sSpends = [];
    for (final i in spends) {
      final nf = i.nf;
      if (nf == null) {
        throw ZCashBlockScannerException.invalidCompact("spend",
            reason: "Nullifier missing.");
      }
      sSpends.add(SaplingNullifier(nf));
    }
    return sSpends;
  }

  List<CompactAction> getCompactActions() {
    final actions = this.actions;
    if (actions == null) return [];
    List<CompactAction> cActions = [];
    for (final i in actions.indexed) {
      final action = i.$2.toAction(i.$1);
      cActions.add(action);
    }
    return cActions;
  }

  ZCashTxId getTxId() {
    final hash = this.hash;
    if (hash != null && hash.length == QuickCrypto.blake2b256DigestSize) {
      return ZCashTxId(hash);
    }
    throw ZCashBlockScannerException.invalidCompact("tx",
        reason: "Transaction hash missing or invalid.");
  }

  int getTxIndex() {
    final index = this.index;
    if (index.isNegative) {
      throw ZCashBlockScannerException.invalidCompact("tx",
          reason: "Invalid transaction index.");
    }
    return index.toU32;
  }

  List<CompactOutputDescription> getOutputDescription() {
    final outputs = this.outputs;
    if (outputs == null) return [];
    List<CompactOutputDescription> descriptions = [];
    for (final i in outputs.indexed) {
      final action = i.$2.toOutputDescription(i.$1);
      descriptions.add(action);
    }
    return descriptions;
  }
}

class CompactAction extends OrchardShildOutput {
  @override
  final OrchardNullifier nf;
  final OrchardExtractedNoteCommitment cmx;
  @override
  final EphemeralKeyBytes ephemeralKey;
  @override
  final List<int> encCiphertextCompact;

  final int outputIndex;
  const CompactAction(
      {required this.nf,
      required this.cmx,
      required this.ephemeralKey,
      required this.encCiphertextCompact,
      required this.outputIndex});

  @override
  OrchardExtractedNoteCommitment cmstar() {
    return cmx;
  }

  @override
  List<int> cmstarBytes() {
    return cmx.toBytes();
  }

  @override
  List<int> get encCiphertext => throw ZCashBlockScannerException(
      "`encCiphertext` not available in compact action.");
}

class CompactOutputDescription extends SaplingShildOutput {
  @override
  final EphemeralKeyBytes ephemeralKey;
  @override
  final List<int> encCiphertextCompact;
  final SaplingExtractedNoteCommitment cmu;

  final int outputIndex;
  const CompactOutputDescription({
    required this.encCiphertextCompact,
    required this.ephemeralKey,
    required this.cmu,
    required this.outputIndex,
  });

  @override
  SaplingExtractedNoteCommitment cmstar() {
    return cmu;
  }

  @override
  List<int> cmstarBytes() {
    return cmu.toBytes();
  }

  @override
  List<int> get encCiphertext => throw ZCashBlockScannerException(
      "`encCiphertext` not available in compact output.");
}

class ScannedTx with LayoutSerializable, Equality {
  final ZCashTxId txId;
  final int index;
  final List<SaplingScannedOutput> saplingOutputs;
  final List<OrchardScannedOutput> orchardOutputs;
  final List<OrchardNullifier> orchardSpends;
  final List<SaplingNullifier> saplingSpends;
  const ScannedTx(
      {required this.txId,
      required this.index,
      required this.saplingOutputs,
      required this.orchardOutputs,
      required this.orchardSpends,
      required this.saplingSpends});
  factory ScannedTx.deserializeJson(Map<String, dynamic> json) {
    return ScannedTx(
        txId: ZCashTxId.deserializeJson(json.valueAs("tx_id")),
        index: json.valueAs("index"),
        saplingOutputs: json
            .valueEnsureAsList<Map<String, dynamic>>("saplingOutputs")
            .map((e) => SaplingScannedOutput.deserializeJson(e))
            .toList(),
        orchardOutputs: json
            .valueEnsureAsList<Map<String, dynamic>>("orchardOutputs")
            .map((e) => OrchardScannedOutput.deserializeJson(e))
            .toList(),
        orchardSpends: json
            .valueEnsureAsList<Map<String, dynamic>>("orchardSpends")
            .map((e) => OrchardNullifier.deserializeJson(e))
            .toList(),
        saplingSpends: json
            .valueEnsureAsList<Map<String, dynamic>>("saplingSpends")
            .map((e) => SaplingNullifier.deserializeJson(e))
            .toList());
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      ZCashTxId.layout(property: "tx_id"),
      LayoutConst.lebU32(property: "index"),
      LayoutConst.bcsVector(ScannedOutput.layout(), property: "saplingOutputs"),
      LayoutConst.bcsVector(ScannedOutput.layout(), property: "orchardOutputs"),
      LayoutConst.bcsVector(Nullifier.layout(), property: "orchardSpends"),
      LayoutConst.bcsVector(Nullifier.layout(), property: "saplingSpends")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "tx_id": txId.toSerializeJson(),
      "index": index,
      "saplingOutputs": saplingOutputs.map((e) => e.toSerializeJson()).toList(),
      "orchardOutputs": orchardOutputs.map((e) => e.toSerializeJson()).toList(),
      "orchardSpends": orchardSpends.map((e) => e.toSerializeJson()).toList(),
      "saplingSpends": saplingSpends.map((e) => e.toSerializeJson()).toList()
    };
  }

  ScannedTx copyWith({
    ZCashTxId? txId,
    int? index,
    List<SaplingScannedOutput>? saplingOutputs,
    List<OrchardScannedOutput>? orchardOutputs,
    List<OrchardNullifier>? orchardSpends,
    List<SaplingNullifier>? saplingSpends,
  }) {
    return ScannedTx(
        txId: txId ?? this.txId,
        index: index ?? this.index,
        saplingOutputs: saplingOutputs ?? this.saplingOutputs,
        orchardOutputs: orchardOutputs ?? this.orchardOutputs,
        orchardSpends: orchardSpends ?? this.orchardSpends,
        saplingSpends: saplingSpends ?? this.saplingSpends);
  }

  @override
  List<dynamic> get variables => [
        txId,
        index,
        saplingOutputs,
        orchardOutputs,
        orchardSpends,
        saplingSpends
      ];
}

abstract class ScannedOutput<
    ADDR extends ShieldAddress,
    IVK extends IncomingViewingKey,
    NOTE extends Note,
    NULLIFIER extends Nullifier> with LayoutSerializable, Equality {
  ShieldedProtocol get protocol;
  final int index;
  final EphemeralKeyBytes ephemeralKey;
  final NOTE note;
  final LeafPosition noteCommitmentTreePosition;
  final IVK account;
  final bool isChange;

  /// Only exists if fvk provided for scanning
  final NULLIFIER? nullifier;

  T cast<T extends ScannedOutput>() {
    if (this is! T) throw CastFailedException(value: this);
    return this as T;
  }

  const ScannedOutput(
      {required this.index,
      required this.ephemeralKey,
      required this.note,
      required this.noteCommitmentTreePosition,
      required this.account,
      required this.isChange,
      required this.nullifier});
  factory ScannedOutput.deserializeJson(Map<String, dynamic> json) {
    final type = ShieldedProtocol.fromValue(json.valueAs("protocol"));
    final scanedOutput = switch (type) {
      ShieldedProtocol.orchard => OrchardScannedOutput.deserializeJson(json),
      ShieldedProtocol.sapling => SaplingScannedOutput.deserializeJson(json),
      _ => throw ZCashBlockScannerException.failed("deserializeJson",
          reason: "Unknown scaned output protocol type.")
    };
    return (scanedOutput as ScannedOutput).cast();
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.u8(property: "protocol"),
      LayoutConst.lebU32(property: "index"),
      EphemeralKeyBytes.layout(property: "ephemeralKey"),
      SaplingNote.layout(property: "note"),
      LayoutConst.lebU32(property: "noteCommitmentTreePosition"),
      LayoutConst.fixedBlobN(64, property: "account"),
      LayoutConst.boolean(property: "isChange"),
      LayoutConst.optional(Nullifier.layout(), property: "nullifier")
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "protocol": protocol.protoValue,
      "index": index,
      "ephemeralKey": ephemeralKey.toSerializeJson(),
      "note": note.toSerializeJson(),
      "noteCommitmentTreePosition": noteCommitmentTreePosition.position,
      "account": account.toBytes(),
      "isChange": isChange,
      "nullifier": nullifier?.toSerializeJson()
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  List<dynamic> get variables => [
        protocol,
        index,
        ephemeralKey,
        note,
        noteCommitmentTreePosition,
        account,
        isChange,
      ];
}

class SaplingScannedOutput extends ScannedOutput<SaplingPaymentAddress,
    SaplingIncomingViewingKey, SaplingNote, SaplingNullifier> {
  const SaplingScannedOutput(
      {required super.index,
      required super.ephemeralKey,
      required super.note,
      required super.noteCommitmentTreePosition,
      required super.account,
      required super.isChange,
      super.nullifier});
  factory SaplingScannedOutput.deserializeJson(Map<String, dynamic> json) {
    return SaplingScannedOutput(
        index: json.valueAs("index"),
        ephemeralKey:
            EphemeralKeyBytes.deserializeJson(json.valueAs("ephemeralKey")),
        note: SaplingNote.deserializeJson(json.valueAs("note")),
        noteCommitmentTreePosition:
            LeafPosition(json.valueAs("noteCommitmentTreePosition")),
        account:
            SaplingIncomingViewingKey.fromBytes(json.valueAsBytes("account")),
        isChange: json.valueAs("isChange"),
        nullifier: json.valueTo<SaplingNullifier?, Map<String, dynamic>>(
            key: "nullifier",
            parse: (e) => SaplingNullifier.deserializeJson(e)));
  }

  SaplingNullifier deriveNullifier({
    required ZCashCryptoContext context,
    required SaplingNullifierDerivingKey nk,
  }) {
    return note.nullifier(
        nk: nk,
        position: noteCommitmentTreePosition.position,
        context: context);
  }

  @override
  ShieldedProtocol get protocol => ShieldedProtocol.sapling;
}

class OrchardScannedOutput extends ScannedOutput<OrchardAddress,
    OrchardIncomingViewingKey, OrchardNote, OrchardNullifier> {
  const OrchardScannedOutput(
      {required super.index,
      required super.ephemeralKey,
      required super.note,
      required super.noteCommitmentTreePosition,
      required super.account,
      required super.isChange,
      super.nullifier});

  factory OrchardScannedOutput.deserializeJson(Map<String, dynamic> json) {
    return OrchardScannedOutput(
        index: json.valueAs("index"),
        ephemeralKey:
            EphemeralKeyBytes.deserializeJson(json.valueAs("ephemeralKey")),
        note: OrchardNote.deserializeJson(json.valueAs("note")),
        noteCommitmentTreePosition:
            LeafPosition(json.valueAs("noteCommitmentTreePosition")),
        account:
            OrchardIncomingViewingKey.fromBytes(json.valueAsBytes("account")),
        isChange: json.valueAs("isChange"),
        nullifier: json.valueTo<OrchardNullifier?, Map<String, dynamic>>(
            key: "nullifier",
            parse: (e) => OrchardNullifier.deserializeJson(e)));
  }

  OrchardNullifier deriveNullifier(
      {required OrchardFullViewingKey fvk,
      required ZCashCryptoContext context}) {
    return note.nullifier(fvk: fvk, context: context);
  }

  @override
  ShieldedProtocol get protocol => ShieldedProtocol.orchard;
}

class ScannedBlockNullifiers<N extends Nullifier>
    with LayoutSerializable, Equality {
  final ZCashTxId txId;
  final int index;
  final N nullifier;
  const ScannedBlockNullifiers(
      {required this.txId, required this.index, required this.nullifier});
  factory ScannedBlockNullifiers._deserializeJson(Map<String, dynamic> json,
      N Function(Map<String, dynamic>) parseNullifier) {
    return ScannedBlockNullifiers(
        nullifier: parseNullifier(json.valueAs("nullifier")),
        index: json.valueAs("index"),
        txId: ZCashTxId.deserializeJson(json.valueAs("tx_id")));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      ZCashTxId.layout(property: "tx_id"),
      LayoutConst.lebU32(property: "index"),
      Nullifier.layout(property: "nullifier")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "tx_id": txId.toSerializeJson(),
      "index": index,
      "nullifier": nullifier.toSerializeJson()
    };
  }

  @override
  List<dynamic> get variables => [txId, index, nullifier];
}

class ScannedBlockCommitment<NODE extends LayoutSerializable>
    with Equality, LayoutSerializable {
  final NODE node;
  final Retention<int> retention;
  const ScannedBlockCommitment({required this.node, required this.retention});
  factory ScannedBlockCommitment._deserializeJson(
      Map<String, dynamic> json, NODE Function(List<int>) parseNode) {
    final type = RetentionType.fromValue(json.valueAs("type"));
    return ScannedBlockCommitment(
        node: parseNode(json.valueAsBytes("node")),
        retention: switch (type) {
          RetentionType.ephemeral => RetentionEphemeral(),
          RetentionType.marked => RetentionMarked(),
          RetentionType.reference => RetentionReference(),
          _ => (() {
              final checkpoint =
                  json.valueEnsureAsMap<String, dynamic>("checkpoint");
              return RetentionCheckpoint(
                  marking:
                      MarkingState.fromValue(checkpoint.valueAs("marking")),
                  id: checkpoint.valueAsInt<int>("id"));
            }())
        });
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyStruct<LayoutRepository>([
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              LayoutConst.fixedBlob32(property: property),
          property: "node"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.u8(), property: "type"),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            final type = RetentionType.fromValue(
                params.sourceOrResult.valueAsInt("type"));
            if (type == RetentionType.checkpoint) {
              return LayoutConst.struct([
                LayoutConst.lebU32(property: "id"),
                LayoutConst.u8(property: "marking"),
              ], property: property);
            }
            return LayoutConst.none(property: property);
          },
          property: "checkpoint")
    ], property: property);
  }

  @override
  List<dynamic> get variables => [node, retention];

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    final retention = this.retention;
    return {
      "node": node.toSerializeBytes(),
      "type": retention.type.value,
      "checkpoint": switch (retention) {
        RetentionCheckpoint(id: int id, marking: MarkingState marking) => {
            "id": id,
            "marking": marking.value,
          },
        _ => null
      }
    };
  }
}

abstract class ScannedBundles<NODE extends LayoutSerializable,
    NULLIFIER extends Nullifier> with LayoutSerializable, Equality {
  final int finalTreeSize;
  final List<ScannedBlockCommitment<NODE>> commitments;
  final List<ScannedBlockNullifiers<NULLIFIER>> nullifiers;
  const ScannedBundles(
      {required this.finalTreeSize,
      this.commitments = const [],
      this.nullifiers = const []});

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "finalTreeSize": finalTreeSize,
      "commitments": commitments.map((e) => e.toSerializeJson()).toList(),
      "nullifiers": nullifiers.map((e) => e.toSerializeJson()).toList()
    };
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "finalTreeSize"),
      LayoutConst.bcsVector(ScannedBlockCommitment.layout(),
          property: "commitments"),
      LayoutConst.bcsVector(ScannedBlockNullifiers.layout(),
          property: "nullifiers")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  List<dynamic> get variables => [finalTreeSize, commitments, nullifiers];
}

class SaplingScannedBundles
    extends ScannedBundles<SaplingNode, SaplingNullifier> {
  SaplingScannedBundles(
      {required super.finalTreeSize, super.commitments, super.nullifiers});
  factory SaplingScannedBundles.deserializeJson(Map<String, dynamic> json) {
    return SaplingScannedBundles(
        finalTreeSize: json.valueAsInt("finalTreeSize"),
        nullifiers: json
            .valueEnsureAsList<Map<String, dynamic>>("nullifiers")
            .map((e) => ScannedBlockNullifiers._deserializeJson(
                  e,
                  (v) => SaplingNullifier.deserializeJson(v),
                ))
            .toList(),
        commitments: json
            .valueEnsureAsList<Map<String, dynamic>>("commitments")
            .map((e) {
          return ScannedBlockCommitment._deserializeJson(
              e, (v) => SaplingNode.fromBytes(v));
        }).toList());
  }
}

class OrchardScannedBundles
    extends ScannedBundles<OrchardMerkleHash, OrchardNullifier> {
  OrchardScannedBundles(
      {required super.finalTreeSize, super.commitments, super.nullifiers});
  factory OrchardScannedBundles.deserializeJson(Map<String, dynamic> json) {
    return OrchardScannedBundles(
        finalTreeSize: json.valueAsInt("finalTreeSize"),
        nullifiers: json
            .valueEnsureAsList<Map<String, dynamic>>("nullifiers")
            .map((e) => ScannedBlockNullifiers._deserializeJson(
                  e,
                  (v) => OrchardNullifier.deserializeJson(v),
                ))
            .toList(),
        commitments: json
            .valueEnsureAsList<Map<String, dynamic>>("commitments")
            .map((e) {
          return ScannedBlockCommitment._deserializeJson(
              e, (v) => OrchardMerkleHash.fromBytes(v));
        }).toList());
  }
}

class ScannedBlock with LayoutSerializable, Equality {
  final int blockId;
  final int? timestamp;
  final String? blockhash;
  final List<ScannedTx> txes;
  final SaplingScannedBundles sapling;
  final OrchardScannedBundles orchard;
  const ScannedBlock(
      {required this.blockId,
      required this.timestamp,
      required this.blockhash,
      this.txes = const [],
      required this.sapling,
      required this.orchard});
  factory ScannedBlock.deserializeJson(Map<String, dynamic> json) {
    return ScannedBlock(
        blockId: json.valueAs("blockId"),
        timestamp: json.valueAs("timestamp"),
        blockhash: json.valueAs("blockhash"),
        txes: json
            .valueEnsureAsList<Map<String, dynamic>>("txes")
            .map((e) => ScannedTx.deserializeJson(e))
            .toList(),
        sapling: SaplingScannedBundles.deserializeJson(json.valueAs("sapling")),
        orchard:
            OrchardScannedBundles.deserializeJson(json.valueAs("orchard")));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "blockId"),
      LayoutConst.optional(LayoutConst.lebU32(), property: "timestamp"),
      LayoutConst.optional(LayoutConst.bcsString(), property: "blockhash"),
      LayoutConst.bcsVector(ScannedTx.layout(), property: "txes"),
      ScannedBundles.layout(property: "sapling"),
      ScannedBundles.layout(property: "orchard"),
    ], property: property);
  }

  ScannedBlock copyWith({
    int? blockId,
    int? timestamp,
    String? blockhash,
    List<ScannedTx>? txes,
    SaplingScannedBundles? sapling,
    OrchardScannedBundles? orchard,
  }) {
    return ScannedBlock(
        blockId: blockId ?? this.blockId,
        timestamp: timestamp ?? this.timestamp,
        blockhash: blockhash ?? this.blockhash,
        txes: txes ?? this.txes,
        sapling: sapling ?? this.sapling,
        orchard: orchard ?? this.orchard);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "blockId": blockId,
      "timestamp": timestamp,
      "blockhash": blockhash,
      "txes": txes.map((e) => e.toSerializeJson()).toList(),
      "sapling": sapling.toSerializeJson(),
      "orchard": orchard.toSerializeJson()
    };
  }

  @override
  List<dynamic> get variables =>
      [blockId, timestamp, blockhash, txes, sapling, orchard];
}

class ScannedBlocks with LayoutSerializable, Equality {
  final List<ScannedBlock> blocks;
  ScannedBlocks(List<ScannedBlock> blocks) : blocks = blocks.immutable;
  factory ScannedBlocks.deserialize(List<int> bytes) {
    final decode =
        LayoutSerializable.deserialize(bytes: bytes, layout: layout());
    return ScannedBlocks.deserializeJson(decode);
  }
  factory ScannedBlocks.deserializeJson(Map<String, dynamic> json) {
    return ScannedBlocks(json
        .valueEnsureAsList<Map<String, dynamic>>("blocks")
        .map((e) => ScannedBlock.deserializeJson(e))
        .toList());
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct(
        [LayoutConst.bcsVector(ScannedBlock.layout(), property: "blocks")],
        property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"blocks": blocks.map((e) => e.toSerializeJson()).toList()};
  }

  @override
  List<dynamic> get variables => [blocks];
}

class BlockStateInfo {
  final NetworkUpgrade upgrade;
  final int saplingCommitmentTreeSize;
  final int orchardCommitmentTreeSize;
  final int orchardFinalTreeSize;
  final int saplingFinalTreeSize;
  final int blockId;
  final int? timestamp;
  final String? blockhash;
  final Zip212Enforcement zip212enforcement;
  const BlockStateInfo(
      {required this.upgrade,
      required this.saplingCommitmentTreeSize,
      required this.orchardCommitmentTreeSize,
      required this.orchardFinalTreeSize,
      required this.saplingFinalTreeSize,
      required this.timestamp,
      required this.blockId,
      required this.blockhash,
      required this.zip212enforcement});
}

class ZCashBlockProcessorConfig {
  final ZCashNetwork network;
  final List<
      ZCashBlockProcessorScanKey<SaplingFullViewingKey,
          SaplingIncomingViewingKey>> saplingViewKeys;
  final List<
      ZCashBlockProcessorScanKey<OrchardFullViewingKey,
          OrchardIncomingViewingKey>> orchardViewKeys;
  final SaplingDomainNative saplingDomain;
  final OrchardDomainNative orchardDomain;
  final ZCashCryptoContext context;
  late final List<SaplingIvk> saplingIvks = saplingViewKeys
      .expand((e) => e.viewKeys)
      .map((e) => e.ivk)
      .toImutableList;
  late final List<OrchardKeyAgreementPrivateKey> orchardIvks = orchardViewKeys
      .expand((e) => e.viewKeys)
      .map((e) => e.ivk)
      .toImutableList;
  ({
    ZCashBlockProcessorScanKey<SaplingFullViewingKey,
        SaplingIncomingViewingKey> scanKey,
    SaplingIncomingViewingKey ivk
  }) findSaplingScanKey(SaplingIvk ivk) {
    for (final i in saplingViewKeys) {
      for (final k in i.viewKeys) {
        if (k.ivk == ivk) return (scanKey: i, ivk: k);
      }
    }
    throw ZCashBlockScannerException.failed("findSaplingIncommingViewKey",
        reason: "key not found.");
  }

  ({
    ZCashBlockProcessorScanKey<OrchardFullViewingKey,
        OrchardIncomingViewingKey> scanKey,
    OrchardIncomingViewingKey ivk
  }) findOrchardScanKey(OrchardKeyAgreementPrivateKey ivk) {
    for (final i in orchardViewKeys) {
      for (final k in i.viewKeys) {
        if (k.ivk == ivk) return (scanKey: i, ivk: k);
      }
    }
    throw ZCashBlockScannerException.failed("findOrchardIncommingViewKey",
        reason: "key not found.");
  }

  ZCashBlockProcessorConfig(
      {required this.network,
      required this.context,
      List<
              ZCashBlockProcessorScanKey<SaplingFullViewingKey,
                  SaplingIncomingViewingKey>>
          saplingViewKeys = const [],
      List<
              ZCashBlockProcessorScanKey<OrchardFullViewingKey,
                  OrchardIncomingViewingKey>>
          orchardViewKeys = const [],
      SaplingDomainNative? saplingDomain,
      OrchardDomainNative? orchardDomain})
      : saplingDomain = saplingDomain ?? SaplingDomainNative(context),
        orchardDomain = orchardDomain ?? OrchardDomainNative(context),
        saplingViewKeys = saplingViewKeys.immutable,
        orchardViewKeys = orchardViewKeys.immutable;
}

class ZCashBlockProcessorScanKey<FVK extends Object,
    IVK extends IncomingViewingKey> {
  final FVK? fvk;
  final List<IVK> viewKeys;
  ZCashBlockProcessorScanKey({this.fvk, List<IVK> viewKeys = const []})
      : viewKeys = viewKeys.immutable;
}

class ChainState {
  final List<int> blockHash;
  final int blockHeight;
  final Frontier<OrchardMerkleHash> finalOrchardTree;
  final Frontier<SaplingNode> finalSaplingTree;
  const ChainState(
      {required this.blockHash,
      required this.blockHeight,
      required this.finalOrchardTree,
      required this.finalSaplingTree});
}
