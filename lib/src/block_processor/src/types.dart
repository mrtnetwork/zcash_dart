import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/address.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/transaction/sighash_digest/types.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';
import 'package:zcash_dart/src/value/value.dart';

abstract mixin class ChainMetadata {
  int? get saplingCommitmentTreeSize;
  int? get orchardCommitmentTreeSize;

  /// Ironwood note commitment tree size (NU6.3+). Null when the serving
  /// lightwalletd predates Ironwood compact support.
  int? get ironwoodCommitmentTreeSize;
}

abstract mixin class CompactBlock {
  ChainMetadata? get chainMetadata;
  int? get saplingCommitmentTreeSize =>
      chainMetadata?.saplingCommitmentTreeSize;
  int? get orchardCommitmentTreeSize =>
      chainMetadata?.orchardCommitmentTreeSize;
  int? get ironwoodCommitmentTreeSize =>
      chainMetadata?.ironwoodCommitmentTreeSize;
  BigInt? get height;
  List<int>? get hash;
  List<CompactTx>? get vtx;
  int? get time;

  List<CompactAction> getCompactActions() =>
      vtx?.expand((e) => e.getCompactActions()).toList() ?? [];

  /// Ironwood-pool compact actions (NU6.3 second slot). Empty when the
  /// serving lightwalletd predates Ironwood compact support.
  List<CompactAction> getCompactIronwoodActions() =>
      vtx?.expand((e) => e.getCompactIronwoodActions()).toList() ?? [];
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

  int timestamp() {
    final time = this.time;
    if (time == null) {
      throw ZcashErrors.scannerInvalidCompact(
        "time",
        reason: "Missing block timestamp.",
      );
    }
    return time;
  }

  int getHeight() {
    final height = this.height;
    if (height == null) {
      throw ZcashErrors.scannerInvalidCompact(
        "height",
        reason: "Missing block height.",
      );
    }
    return height.toU32;
  }

  int totalSaplingOutputs() =>
      vtx?.fold<int>(0, (p, c) => p + (c.outputs?.length ?? 0)) ?? 0;
  int totalOrchardOutputs() =>
      vtx?.fold<int>(0, (p, c) => p + (c.actions?.length ?? 0)) ?? 0;
  int totalIronwoodOutputs() =>
      vtx?.fold<int>(0, (p, c) => p + (c.ironwoodActions?.length ?? 0)) ?? 0;
}

abstract mixin class CompactOrchardAction implements Equality {
  List<int>? get nullifier;
  List<int>? get cmx;
  List<int>? get ephemeralKey;
  List<int>? get ciphertext;
  CompactAction toAction(int outputIndex) {
    final nullifier = this.nullifier;
    if (nullifier == null) {
      throw ZcashErrors.scannerInvalidCompact(
        "action",
        reason: "Nullifier missing.",
      );
    }

    final cmx = this.cmx;
    if (cmx == null) {
      throw ZcashErrors.scannerInvalidCompact("action", reason: "cmx missing.");
    }
    final ephemeralKey = this.ephemeralKey;
    if (ephemeralKey == null) {
      throw ZcashErrors.scannerInvalidCompact(
        "action",
        reason: "ephemeralKey missing.",
      );
    }
    final ciphertext = this.ciphertext;
    if (ciphertext == null) {
      throw ZcashErrors.scannerInvalidCompact(
        "action",
        reason: "ciphertext missing.",
      );
    }
    return CompactAction(
      nf: OrchardNullifier.fromBytes(nullifier),
      cmx: OrchardExtractedNoteCommitment(PallasFp.fromBytes(cmx)),
      ephemeralKey: EphemeralKeyBytes(ephemeralKey),
      encCiphertextCompact: ciphertext,
      outputIndex: outputIndex,
    );
  }

  @override
  List<dynamic> get variables => [nullifier, cmx, ephemeralKey, ciphertext];
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
      throw ZcashErrors.scannerInvalidCompact("output");
    }
    return CompactOutputDescription(
      cmu: SaplingExtractedNoteCommitment(JubJubFq.fromBytes(cmu)),
      ephemeralKey: EphemeralKeyBytes(ephemeralKey),
      encCiphertextCompact: ciphertext,
      outputIndex: outputIndex,
    );
  }

  @override
  List<dynamic> get variables => [cmu, ephemeralKey, ciphertext];
}

abstract mixin class CompactSaplingSpend implements Equality {
  List<int>? get nf;
  bool isValid() => nf != null;

  @override
  List<dynamic> get variables => [nf];
}

abstract mixin class CompactTx {
  BigInt? get index;
  List<int>? get txid;
  List<CompactSaplingSpend>? get spends;
  List<CompactSaplingOutput>? get outputs;
  List<CompactOrchardAction>? get actions;

  /// Ironwood-pool compact actions (NU6.3). Same wire shape as [actions].
  List<CompactOrchardAction>? get ironwoodActions;
  List<SaplingNullifier> getSpends() {
    final spends = this.spends;
    if (spends == null) return [];
    List<SaplingNullifier> sSpends = [];
    for (final i in spends) {
      final nf = i.nf;
      if (nf == null) {
        throw ZcashErrors.scannerInvalidCompact(
          "spend",
          reason: "Nullifier missing.",
        );
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

  List<CompactAction> getCompactIronwoodActions() {
    final actions = ironwoodActions;
    if (actions == null) return [];
    List<CompactAction> cActions = [];
    for (final i in actions.indexed) {
      final action = i.$2.toAction(i.$1);
      cActions.add(action);
    }
    return cActions;
  }

  ZcashTxId getTxId() {
    final hash = txid;
    if (hash != null && hash.length == QuickCrypto.blake2b256DigestSize) {
      return ZcashTxId(hash);
    }
    throw ZcashErrors.scannerInvalidCompact(
      "tx",
      reason: "Transaction hash missing or invalid.",
    );
  }

  int getTxIndex() {
    final index = this.index ?? BigInt.zero;
    if (index.isNegative) {
      throw ZcashErrors.scannerInvalidCompact(
        "tx",
        reason: "Invalid transaction index.",
      );
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
  const CompactAction({
    required this.nf,
    required this.cmx,
    required this.ephemeralKey,
    required this.encCiphertextCompact,
    required this.outputIndex,
  });

  @override
  OrchardExtractedNoteCommitment cmstar() {
    return cmx;
  }

  @override
  List<int> cmstarBytes() {
    return cmx.toBytes();
  }

  @override
  List<int> get encCiphertext =>
      throw BuError(
        DefaultErrorType.unsupported,
        "`encCiphertext` not available in compact action.",
      );
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
  List<int> get encCiphertext =>
      throw BuError(
        DefaultErrorType.unsupported,
        "`encCiphertext` not available in compact output.",
      );
}

class ScannedTx with LayoutSerializable, Equality {
  final ZcashTxId txId;
  final int index;
  final List<SaplingScannedOutputWithIvk> saplingOutputs;
  final List<OrchardScannedOutputWithIvk> orchardOutputs;

  /// Ironwood-pool scanned outputs (NU6.3). Same element type as the
  /// Orchard pool (Ironwood notes are Orchard-shaped, v3); pool
  /// membership is given by list placement.
  final List<OrchardScannedOutputWithIvk> ironwoodOutputs;
  ScannedTx({
    required this.txId,
    required this.index,
    required List<SaplingScannedOutputWithIvk> saplingOutputs,
    required List<OrchardScannedOutputWithIvk> orchardOutputs,
    List<OrchardScannedOutputWithIvk> ironwoodOutputs = const [],
  }) : saplingOutputs = saplingOutputs.immutable,
       orchardOutputs = orchardOutputs.immutable,
       ironwoodOutputs = ironwoodOutputs.immutable;
  factory ScannedTx.deserializeJson(Map<String, dynamic> json) {
    return ScannedTx(
      txId: ZcashTxId.deserializeJson(json.valueAs("tx_id")),
      index: json.valueAs("index"),
      saplingOutputs:
          json
              .valueEnsureAsList<Map<String, dynamic>>("saplingOutputs")
              .map((e) => SaplingScannedOutputWithIvk.deserializeJson(e))
              .toList(),
      orchardOutputs:
          json
              .valueEnsureAsList<Map<String, dynamic>>("orchardOutputs")
              .map((e) => OrchardScannedOutputWithIvk.deserializeJson(e))
              .toList(),
      ironwoodOutputs:
          json
              .valueEnsureAsList<Map<String, dynamic>>(
                "ironwoodOutputs",
                onMissing: () => [],
              )
              .map((e) => OrchardScannedOutputWithIvk.deserializeJson(e))
              .toList(),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      ZcashTxId.layout(property: "tx_id"),
      LayoutConst.lebU32(property: "index"),
      LayoutConst.bcsVector(
        ScannedOutputWithIvk.layout(),
        property: "saplingOutputs",
      ),
      LayoutConst.bcsVector(
        ScannedOutputWithIvk.layout(),
        property: "orchardOutputs",
      ),
      LayoutConst.bcsVector(
        ScannedOutputWithIvk.layout(),
        property: "ironwoodOutputs",
      ),
    ], property: property);
  }

  /// Layout without the trailing Ironwood field, for scans stored
  /// before NU6.3 support.
  static Layout<Map<String, dynamic>> legacyLayout({String? property}) {
    return LayoutConst.struct([
      ZcashTxId.layout(property: "tx_id"),
      LayoutConst.lebU32(property: "index"),
      LayoutConst.bcsVector(
        ScannedOutputWithIvk.layout(),
        property: "saplingOutputs",
      ),
      LayoutConst.bcsVector(
        ScannedOutputWithIvk.layout(),
        property: "orchardOutputs",
      ),
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
      "ironwoodOutputs":
          ironwoodOutputs.map((e) => e.toSerializeJson()).toList(),
    };
  }

  ScannedTx copyWith({
    ZcashTxId? txId,
    int? index,
    List<SaplingScannedOutputWithIvk>? saplingOutputs,
    List<OrchardScannedOutputWithIvk>? orchardOutputs,
    List<OrchardScannedOutputWithIvk>? ironwoodOutputs,
    List<OrchardNullifier>? orchardSpends,
    List<SaplingNullifier>? saplingSpends,
  }) {
    return ScannedTx(
      txId: txId ?? this.txId,
      index: index ?? this.index,
      saplingOutputs: saplingOutputs ?? this.saplingOutputs,
      orchardOutputs: orchardOutputs ?? this.orchardOutputs,
      ironwoodOutputs: ironwoodOutputs ?? this.ironwoodOutputs,
    );
  }

  @override
  List<dynamic> get variables => [
    txId,
    index,
    saplingOutputs,
    orchardOutputs,
    ironwoodOutputs,
  ];

  List<ScannedOutputWithIvk> scannedOutputs() => [
    ...orchardOutputs,
    ...ironwoodOutputs,
    ...saplingOutputs,
  ];
}

abstract class ScannedOutput<NOTE extends Note>
    with LayoutSerializable, PartialEquality {
  ZcashProtocol get protocol;
  final int index;
  final EphemeralKeyBytes ephemeralKey;
  final NOTE note;
  final LeafPosition noteCommitmentTreePosition;
  ZAmount get amount => note.value;

  ScannedOutput({
    required this.index,
    required this.ephemeralKey,
    required this.note,
    required this.noteCommitmentTreePosition,
  });

  T cast<T extends ScannedOutput>() {
    if (this is! T) {
      throw BuError(
        DefaultErrorType.castFailed,
        "Failed to cast value",
        details: {"expected": "T", "value": runtimeType.toString()},
      );
    }
    return this as T;
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "index"),
      EphemeralKeyBytes.layout(property: "ephemeralKey"),
      LayoutConst.bcsBytes(property: "note"),
      LayoutConst.lebU32(property: "noteCommitmentTreePosition"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "index": index,
      "ephemeralKey": ephemeralKey.toSerializeJson(),
      "note": note.toSerializeBytes(),
      "noteCommitmentTreePosition": noteCommitmentTreePosition.position,
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  List<dynamic> get parts => [protocol, noteCommitmentTreePosition];
}

class SaplingScannedOutput extends ScannedOutput<SaplingNote> {
  SaplingScannedOutput({
    required super.index,
    required super.ephemeralKey,
    required super.note,
    required super.noteCommitmentTreePosition,
  });
  factory SaplingScannedOutput.dummy({SaplingNote? note}) {
    note ??= SaplingNote.dummy().note;
    return SaplingScannedOutput(
      index: QuickCrypto.generateRandomInt(BinaryOps.mask8),
      ephemeralKey: EphemeralKeyBytes.random(),
      note: note,
      noteCommitmentTreePosition: LeafPosition(QuickCrypto.nextU32()),
    );
  }
  factory SaplingScannedOutput.deserializeJson(Map<String, dynamic> json) {
    return SaplingScannedOutput(
      index: json.valueAs("index"),
      ephemeralKey: EphemeralKeyBytes.deserializeJson(
        json.valueAs("ephemeralKey"),
      ),
      note: SaplingNote.deserialize(json.valueAsBytes("note")),
      noteCommitmentTreePosition: LeafPosition(
        json.valueAs("noteCommitmentTreePosition"),
      ),
    );
  }

  SaplingNullifier deriveNullifier({
    required ZcashCryptoContext context,
    required SaplingNullifierDerivingKey nk,
  }) {
    return note.nullifier(
      nk: nk,
      position: noteCommitmentTreePosition.position,
      context: context,
    );
  }

  @override
  ZcashProtocol get protocol => ZcashProtocol.sapling;
}

class OrchardScannedOutput extends ScannedOutput<OrchardNote> {
  factory OrchardScannedOutput.dummy({
    OrchardNote? note,
    ZcashCryptoContext? context,
  }) {
    note ??= OrchardNote.dummy(context ?? DefaultZcashCryptoContext.lazy()).$3;
    return OrchardScannedOutput(
      index: QuickCrypto.generateRandomInt(BinaryOps.mask8),
      ephemeralKey: EphemeralKeyBytes.random(),
      note: note,
      noteCommitmentTreePosition: LeafPosition(QuickCrypto.nextU32()),
    );
  }
  OrchardScannedOutput({
    required super.index,
    required super.ephemeralKey,
    required super.note,
    required super.noteCommitmentTreePosition,
  });

  factory OrchardScannedOutput.deserializeJson(Map<String, dynamic> json) {
    return OrchardScannedOutput(
      index: json.valueAs("index"),
      ephemeralKey: EphemeralKeyBytes.deserializeJson(
        json.valueAs("ephemeralKey"),
      ),
      note: OrchardNote.deserialize(json.valueAsBytes("note")),
      noteCommitmentTreePosition: LeafPosition(
        json.valueAs("noteCommitmentTreePosition"),
      ),
    );
  }

  OrchardNullifier deriveNullifier({
    required OrchardFullViewingKey fvk,
    required ZcashCryptoContext context,
  }) {
    return note.nullifier(fvk: fvk, context: context);
  }

  @override
  ZcashProtocol get protocol => ZcashProtocol.orchard;
}

abstract class ScannedOutputWithIvk<
  IVK extends IncomingViewingKey,
  OUTPUT extends ScannedOutput,
  NULLIFIER extends Nullifier
>
    with LayoutSerializable, PartialEquality {
  final OUTPUT output;
  final IVK ivk;
  final NULLIFIER? nullifier;
  final List<int>? memo;

  const ScannedOutputWithIvk({
    required this.output,
    required this.ivk,
    this.nullifier,
    this.memo,
  });

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      ScannedOutput.layout(property: "output"),
      LayoutConst.fixedBlobN(64, property: "ivk"),
      LayoutConst.optional(Nullifier.layout(), property: "nullifier"),
      LayoutConst.optional(LayoutConst.bcsBytes(), property: "memo"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "output": output.toSerializeJson(),
      "ivk": ivk.toBytes(),
      "nullifier": nullifier?.toSerializeJson(),
      "memo": memo,
    };
  }

  @override
  List<dynamic> get parts => [output];

  ScannedOutputWithIvk<IVK, OUTPUT, NULLIFIER> withNullifier({
    required DiversifiableFullViewingKey<
      ShieldAddress,
      IVK,
      OutgoingViewingKey,
      KeyAgreementPrivateKey
    >
    fvk,
    required ZcashCryptoContext context,
  });

  FullScannedOutput toScannecOutputWithNullifier({
    required DiversifiableFullViewingKey fvk,
    required int blockHeight,
    required ZcashTxId txId,
    required ZcashCryptoContext context,
    required int blocktime,
  });
}

class SaplingScannedOutputWithIvk
    extends
        ScannedOutputWithIvk<
          SaplingIncomingViewingKey,
          SaplingScannedOutput,
          SaplingNullifier
        > {
  const SaplingScannedOutputWithIvk({
    required super.output,
    required super.ivk,
    super.nullifier,
    super.memo,
  });
  factory SaplingScannedOutputWithIvk.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return SaplingScannedOutputWithIvk(
      output: SaplingScannedOutput.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("output"),
      ),
      ivk: SaplingIncomingViewingKey.fromBytes(json.valueAsBytes("ivk")),
      nullifier: json.valueTo<SaplingNullifier?, Map<String, dynamic>>(
        key: "nullifier",
        parse: (v) => SaplingNullifier.deserializeJson(v),
      ),
      memo: json.valueAsBytes("memo"),
    );
  }

  @override
  FullScannedOutput toScannecOutputWithNullifier({
    required DiversifiableFullViewingKey fvk,
    required int blockHeight,
    required ZcashTxId txId,
    required ZcashCryptoContext context,
    required int blocktime,
  }) {
    final nullifier = this.output.deriveNullifier(
      context: context,
      nk: fvk.cast<SaplingDiversifiableFullViewingKey>().fvk.vk.nk,
    );
    final output = SaplingScannedOutputWithNullifier(
      output: this.output,
      nullifier: nullifier,
      blockHeight: blockHeight,
      txId: txId,
      blocktime: blocktime,
      memo: memo,
    );
    final scope = fvk.getScopeAndDiversifierIndex(
      output.output.note.recipient,
      context: context,
    );
    if (scope == null) {
      throw ZcashErrors.scannerFailed(
        "toScannecOutputWithNullifier",
        reason: "Failed to derive output scope and diversifier index.",
      );
    }
    return FullScannedOutput(
      viewKey: ivk,
      output: output,
      changes: scope.$2,
      index: scope.$1,
    );
  }

  @override
  SaplingScannedOutputWithIvk withNullifier({
    required DiversifiableFullViewingKey fvk,
    required ZcashCryptoContext context,
  }) {
    if (this.nullifier != null) return this;
    final nullifier = output.deriveNullifier(
      context: context,
      nk: fvk.cast<SaplingDiversifiableFullViewingKey>().fvk.vk.nk,
    );
    return SaplingScannedOutputWithIvk(
      output: output,
      ivk: ivk,
      nullifier: nullifier,
    );
  }
}

class OrchardScannedOutputWithIvk
    extends
        ScannedOutputWithIvk<
          OrchardIncomingViewingKey,
          OrchardScannedOutput,
          OrchardNullifier
        > {
  const OrchardScannedOutputWithIvk({
    required super.output,
    required super.ivk,
    super.nullifier,
    super.memo,
  });
  factory OrchardScannedOutputWithIvk.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return OrchardScannedOutputWithIvk(
      output: OrchardScannedOutput.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("output"),
      ),
      ivk: OrchardIncomingViewingKey.fromBytes(json.valueAsBytes("ivk")),
      nullifier: json.valueTo<OrchardNullifier?, Map<String, dynamic>>(
        key: "nullifier",
        parse: (v) => OrchardNullifier.deserializeJson(v),
      ),
      memo: json.valueAsBytes("memo"),
    );
  }
  @override
  FullScannedOutput toScannecOutputWithNullifier({
    required DiversifiableFullViewingKey fvk,
    required int blockHeight,
    required ZcashTxId txId,
    required ZcashCryptoContext context,
    required int blocktime,
  }) {
    final nullifier = this.output.deriveNullifier(
      context: context,
      fvk: fvk.cast<OrchardFullViewingKey>(),
    );
    final output = OrchardScannedOutputWithNullifier(
      output: this.output,
      nullifier: nullifier,
      blockHeight: blockHeight,
      txId: txId,
      blocktime: blocktime,
      memo: memo,
    );
    final scope = fvk.getScopeAndDiversifierIndex(
      output.output.note.recipient,
      context: context,
    );
    if (scope == null) {
      throw ZcashErrors.scannerFailed(
        "toScannecOutputWithNullifier",
        reason: "Failed to derive output scope and diversifier index.",
      );
    }
    return FullScannedOutput(
      viewKey: ivk,
      output: output,
      changes: scope.$2,
      index: scope.$1,
    );
  }

  @override
  OrchardScannedOutputWithIvk withNullifier({
    required DiversifiableFullViewingKey fvk,
    required ZcashCryptoContext context,
  }) {
    if (this.nullifier != null) return this;
    final nullifier = output.deriveNullifier(
      context: context,
      fvk: fvk.cast<OrchardFullViewingKey>(),
    );
    return OrchardScannedOutputWithIvk(
      output: output,
      ivk: ivk,
      nullifier: nullifier,
    );
  }
}

class ScannedBlockNullifier<N extends Nullifier>
    with LayoutSerializable, CborTagSerializable, Equality {
  final ZcashTxId txId;
  final int index;
  final N nullifier;
  const ScannedBlockNullifier({
    required this.txId,
    required this.index,
    required this.nullifier,
  });
  factory ScannedBlockNullifier.deserialize({
    List<int>? bytes,
    CborObject? object,
    required N Function(List<int>) fromBytes,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.scanedBlockNullifier,
      cborBytes: bytes,
      cborObject: object,
    );
    return ScannedBlockNullifier(
      txId: ZcashTxId(values.rawValueAt(0)),
      index: values.rawValueAt(1),
      nullifier: fromBytes(values.rawValueAt(2)),
    );
  }
  factory ScannedBlockNullifier._deserializeJson({
    required Map<String, dynamic> json,
    required N Function(List<int>) fromBytes,
  }) {
    return ScannedBlockNullifier(
      nullifier: fromBytes(json.valueAsBytes("nullifier")),
      index: json.valueAs("index"),
      txId: ZcashTxId.deserializeJson(json.valueAs("tx_id")),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      ZcashTxId.layout(property: "tx_id"),
      LayoutConst.lebU32(property: "index"),
      LayoutConst.bcsBytes(property: "nullifier"),
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
      "nullifier": nullifier.toBytes(),
    };
  }

  @override
  List<dynamic> get variables => [txId, index, nullifier];

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.scanedBlockNullifier;

  @override
  List<CborObject?> get serializationItems => [
    CborBytesValue(txId.hash),
    index.toCbor(),
    nullifier.toCbor(),
  ];
}

class ScannedBlockCommitment<NODE extends MerkleNodeValue>
    with Equality, LayoutSerializable, CborTagSerializable {
  final NODE node;
  final Retention<int> retention;
  const ScannedBlockCommitment({required this.node, required this.retention});
  factory ScannedBlockCommitment.deserialize({
    required NODE Function(List<int>) fromBytes,
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.blockCommitment,
      cborBytes: bytes,
      cborObject: object,
    );
    return ScannedBlockCommitment(
      node: fromBytes(values.rawValueAt(0)),
      retention: ExtRetentionEncoding.deserialize(obj: values.objectAt(1)),
    );
  }

  factory ScannedBlockCommitment._deserializeJson({
    required Map<String, dynamic> json,
    required NODE Function(List<int>) fromBytes,
  }) {
    final type = RetentionType.fromValue(json.valueAs("type"));
    return ScannedBlockCommitment(
      node: fromBytes(json.valueAsBytes("node")),
      retention: switch (type) {
        RetentionType.ephemeral => RetentionEphemeral(),
        RetentionType.marked => RetentionMarked(),
        RetentionType.reference => RetentionReference(),
        _ => (() {
          final checkpoint = json.valueEnsureAsMap<String, dynamic>(
            "checkpoint",
          );
          return RetentionCheckpoint(
            marking: MarkingState.fromValue(checkpoint.valueAs("marking")),
            id: checkpoint.valueAsInt<int>("id"),
          );
        }()),
      },
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyStruct<LayoutRepository>([
      LazyStructLayoutBuilder(
        layout:
            (property, params) => LayoutConst.fixedBlob32(property: property),
        property: "node",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) => LayoutConst.u8(),
        property: "type",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          final type = RetentionType.fromValue(
            params.sourceOrResult.valueAsInt("type"),
          );
          if (type == RetentionType.checkpoint) {
            return LayoutConst.struct([
              LayoutConst.lebU32(property: "id"),
              LayoutConst.u8(property: "marking"),
            ], property: property);
          }
          return LayoutConst.none(property: property);
        },
        property: "checkpoint",
      ),
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
        _ => null,
      },
    };
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.blockCommitment;

  @override
  List<CborObject?> get serializationItems => [
    CborBytesValue(node.toBytes()),
    retention.toCbor(),
  ];
}

class ScannedProtocolBundles<NODE extends MerkleNodeValue>
    with LayoutSerializable, CborTagSerializable, Equality {
  final int finalTreeSize;
  final List<ScannedBlockCommitment<NODE>> commitments;
  factory ScannedProtocolBundles.deserialize({
    required NODE Function(List<int> bytes) fromBytes,
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.scannedProtocolBundles,
      cborBytes: bytes,
      cborObject: obj,
    );
    return ScannedProtocolBundles(
      finalTreeSize: values.rawValueAt(0),
      commitments:
          values
              .listAt<CborTagValue>(1)
              .map(
                (e) => ScannedBlockCommitment.deserialize(
                  object: e,
                  fromBytes: fromBytes,
                ),
              )
              .toList(),
    );
  }

  factory ScannedProtocolBundles.deserializeJson({
    required Map<String, dynamic> json,
    required NODE Function(List<int> bytes) fromBytes,
  }) {
    return ScannedProtocolBundles(
      finalTreeSize: json.valueAs("finalTreeSize"),
      commitments:
          json
              .valueEnsureAsList<Map<String, dynamic>>("commitments")
              .map(
                (e) => ScannedBlockCommitment._deserializeJson(
                  json: e,
                  fromBytes: fromBytes,
                ),
              )
              .toList(),
    );
  }

  ScannedProtocolBundles({
    required this.finalTreeSize,
    List<ScannedBlockCommitment<NODE>> commitments = const [],
  }) : commitments = commitments.immutable;

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "finalTreeSize": finalTreeSize,
      "commitments": commitments.map((e) => e.toSerializeJson()).toList(),
    };
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "finalTreeSize"),
      LayoutConst.bcsVector(
        ScannedBlockCommitment.layout(),
        property: "commitments",
      ),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  List<dynamic> get variables => [finalTreeSize, commitments];

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.scannedProtocolBundles;

  @override
  List<CborObject?> get serializationItems => [
    finalTreeSize.toCbor(),
    CborTagSerializable.listFromDynamic(
      commitments.map((e) => e.toCbor()).toList(),
    ),
  ];
}

class ScannedBlockBundles
    with CborTagSerializable, LayoutSerializable, Equality {
  final ScannedProtocolBundles<SaplingNode> sapling;
  final ScannedProtocolBundles<OrchardMerkleHash> orchard;

  /// Ironwood note-commitment bundle data (NU6.3 second pool).
  final ScannedProtocolBundles<OrchardMerkleHash> ironwood;
  ScannedBlockBundles({
    required this.sapling,
    required this.orchard,
    ScannedProtocolBundles<OrchardMerkleHash>? ironwood,
  }) : ironwood =
           ironwood ??
           ScannedProtocolBundles<OrchardMerkleHash>(finalTreeSize: 0);
  factory ScannedBlockBundles.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.scannedBlockBundles,
      cborBytes: bytes,
      cborObject: object,
    );
    ScannedProtocolBundles<OrchardMerkleHash> readIronwood() {
      try {
        final obj = values.objectAt(2);
        if (obj == null) {
          return ScannedProtocolBundles<OrchardMerkleHash>(finalTreeSize: 0);
        }
        return ScannedProtocolBundles.deserialize(
          fromBytes: OrchardMerkleHash.fromBytes,
          obj: obj,
        );
      } catch (_) {
        // Scans stored before NU6.3 support have no third item.
        return ScannedProtocolBundles<OrchardMerkleHash>(finalTreeSize: 0);
      }
    }

    return ScannedBlockBundles(
      sapling: ScannedProtocolBundles.deserialize(
        fromBytes: SaplingNode.fromBytes,
        obj: values.objectAt(0),
      ),
      orchard: ScannedProtocolBundles.deserialize(
        fromBytes: OrchardMerkleHash.fromBytes,
        obj: values.objectAt(1),
      ),
      ironwood: readIronwood(),
    );
  }
  factory ScannedBlockBundles.deserializeJson(Map<String, dynamic> json) {
    ScannedProtocolBundles<OrchardMerkleHash> readIronwood() {
      try {
        return ScannedProtocolBundles.deserializeJson(
          json: json.valueAs("ironwood"),
          fromBytes: OrchardMerkleHash.fromBytes,
        );
      } catch (_) {
        return ScannedProtocolBundles<OrchardMerkleHash>(finalTreeSize: 0);
      }
    }

    return ScannedBlockBundles(
      sapling: ScannedProtocolBundles.deserializeJson(
        json: json.valueAs("orchard"),
        fromBytes: SaplingNode.fromBytes,
      ),
      orchard: ScannedProtocolBundles.deserializeJson(
        json: json.valueAs("orchard"),
        fromBytes: OrchardMerkleHash.fromBytes,
      ),
      ironwood: readIronwood(),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      ScannedProtocolBundles.layout(property: "sapling"),
      ScannedProtocolBundles.layout(property: "orchard"),
      ScannedProtocolBundles.layout(property: "ironwood"),
    ], property: property);
  }

  /// Layout without the trailing Ironwood bundle, for scans stored
  /// before NU6.3 support.
  static Layout<Map<String, dynamic>> legacyLayout({String? property}) {
    return LayoutConst.struct([
      ScannedProtocolBundles.layout(property: "sapling"),
      ScannedProtocolBundles.layout(property: "orchard"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.scannedBlockBundles;

  @override
  List<CborObject?> get serializationItems => [
    sapling.toCbor(),
    orchard.toCbor(),
    ironwood.toCbor(),
  ];

  @override
  List<dynamic> get variables => [sapling, orchard, ironwood];

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "sapling": sapling.toSerializeJson(),
      "orchard": orchard.toSerializeJson(),
      "ironwood": ironwood.toSerializeJson(),
    };
  }
}

class ScannedBlock with LayoutSerializable, Equality {
  final int blockId;
  final int timestamp;
  final String? blockhash;
  final List<ScannedTx> txes;
  final ScannedBlockBundles bundles;
  final List<ScannedBlockNullifier<SaplingNullifier>> saplingNullifiers;
  final List<ScannedBlockNullifier<OrchardNullifier>> orchardNullifiers;

  /// Ironwood-pool nullifiers (NU6.3 second pool, separate nullifier set).
  final List<ScannedBlockNullifier<OrchardNullifier>> ironwoodNullifiers;
  ScannedBlock({
    required this.blockId,
    required this.timestamp,
    required this.blockhash,
    List<ScannedTx> txes = const [],
    required List<ScannedBlockNullifier<SaplingNullifier>> saplingNullifiers,
    required List<ScannedBlockNullifier<OrchardNullifier>> orchardNullifiers,
    List<ScannedBlockNullifier<OrchardNullifier>> ironwoodNullifiers = const [],
    required this.bundles,
  }) : txes = txes.immutable,
       saplingNullifiers = saplingNullifiers.immutable,
       orchardNullifiers = orchardNullifiers.immutable,
       ironwoodNullifiers = ironwoodNullifiers.immutable;
  factory ScannedBlock.deserializeJson(Map<String, dynamic> json) {
    return ScannedBlock(
      blockId: json.valueAs("blockId"),
      timestamp: json.valueAs("timestamp"),
      blockhash: json.valueAs("blockhash"),
      txes:
          json
              .valueEnsureAsList<Map<String, dynamic>>("txes")
              .map((e) => ScannedTx.deserializeJson(e))
              .toList(),
      bundles: ScannedBlockBundles.deserializeJson(json.valueAs("bundles")),

      orchardNullifiers:
          json
              .valueEnsureAsList<Map<String, dynamic>>("orchardNullifiers")
              .map(
                (e) => ScannedBlockNullifier._deserializeJson(
                  json: e,
                  fromBytes: OrchardNullifier.fromBytes,
                ),
              )
              .toList(),
      saplingNullifiers:
          json
              .valueEnsureAsList<Map<String, dynamic>>("saplingNullifiers")
              .map(
                (e) => ScannedBlockNullifier._deserializeJson(
                  json: e,
                  fromBytes: (bytes) => SaplingNullifier(bytes),
                ),
              )
              .toList(),
      ironwoodNullifiers:
          json
              .valueEnsureAsList<Map<String, dynamic>>(
                "ironwoodNullifiers",
                onMissing: () => [],
              )
              .map(
                (e) => ScannedBlockNullifier._deserializeJson(
                  json: e,
                  fromBytes: OrchardNullifier.fromBytes,
                ),
              )
              .toList(),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "blockId"),
      LayoutConst.optional(LayoutConst.lebU32(), property: "timestamp"),
      LayoutConst.optional(LayoutConst.bcsString(), property: "blockhash"),
      LayoutConst.bcsVector(ScannedTx.layout(), property: "txes"),
      ScannedBlockBundles.layout(property: "bundles"),

      LayoutConst.bcsVector(
        ScannedBlockNullifier.layout(),
        property: "saplingNullifiers",
      ),
      LayoutConst.bcsVector(
        ScannedBlockNullifier.layout(),
        property: "orchardNullifiers",
      ),
      LayoutConst.bcsVector(
        ScannedBlockNullifier.layout(),
        property: "ironwoodNullifiers",
      ),
    ], property: property);
  }

  /// Layout without the trailing Ironwood fields, for scans stored
  /// before NU6.3 support.
  static Layout<Map<String, dynamic>> legacyLayout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU32(property: "blockId"),
      LayoutConst.optional(LayoutConst.lebU32(), property: "timestamp"),
      LayoutConst.optional(LayoutConst.bcsString(), property: "blockhash"),
      LayoutConst.bcsVector(ScannedTx.legacyLayout(), property: "txes"),
      ScannedBlockBundles.legacyLayout(property: "bundles"),

      LayoutConst.bcsVector(
        ScannedBlockNullifier.layout(),
        property: "saplingNullifiers",
      ),
      LayoutConst.bcsVector(
        ScannedBlockNullifier.layout(),
        property: "orchardNullifiers",
      ),
    ], property: property);
  }

  ScannedBlock copyWith({
    int? blockId,
    int? timestamp,
    String? blockhash,
    List<ScannedTx>? txes,
    ScannedBlockBundles? bundles,
    List<ScannedBlockNullifier<SaplingNullifier>>? saplingNullifiers,
    List<ScannedBlockNullifier<OrchardNullifier>>? orchardNullifiers,
    List<ScannedBlockNullifier<OrchardNullifier>>? ironwoodNullifiers,
  }) {
    return ScannedBlock(
      blockId: blockId ?? this.blockId,
      timestamp: timestamp ?? this.timestamp,
      blockhash: blockhash ?? this.blockhash,
      txes: txes ?? this.txes,
      bundles: bundles ?? this.bundles,
      orchardNullifiers: orchardNullifiers ?? this.orchardNullifiers,
      saplingNullifiers: saplingNullifiers ?? this.saplingNullifiers,
      ironwoodNullifiers: ironwoodNullifiers ?? this.ironwoodNullifiers,
    );
  }

  List<ScannedOutputWithIvk> scannedOutputs() =>
      txes.expand((e) => e.scannedOutputs()).toList();
  List<Nullifier> nullifiers() => [
    ...saplingNullifiers.map((e) => e.nullifier),
    ...orchardNullifiers.map((e) => e.nullifier),
    ...ironwoodNullifiers.map((e) => e.nullifier),
  ];

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
      "bundles": bundles.toSerializeJson(),
      "saplingNullifiers":
          saplingNullifiers.map((e) => e.toSerializeJson()).toList(),
      "orchardNullifiers":
          orchardNullifiers.map((e) => e.toSerializeJson()).toList(),
      "ironwoodNullifiers":
          ironwoodNullifiers.map((e) => e.toSerializeJson()).toList(),
    };
  }

  @override
  List<dynamic> get variables => [
    blockId,
    timestamp,
    blockhash,
    txes,
    bundles,
    ironwoodNullifiers,
  ];
}

class ScannedBlocks with LayoutSerializable, Equality {
  final List<ScannedBlock> blocks;
  ScannedBlocks(List<ScannedBlock> blocks) : blocks = blocks.immutable;
  factory ScannedBlocks.deserialize(List<int> bytes) {
    try {
      final decode = LayoutSerializable.deserialize(
        bytes: bytes,
        layout: layout(),
      );
      return ScannedBlocks.deserializeJson(decode);
    } on BuError {
      // Scans stored before NU6.3 support lack the Ironwood fields.
      final decode = LayoutSerializable.deserialize(
        bytes: bytes,
        layout: legacyLayout(),
      );
      return ScannedBlocks.deserializeJson(decode);
    }
  }
  factory ScannedBlocks.deserializeJson(Map<String, dynamic> json) {
    return ScannedBlocks(
      json
          .valueEnsureAsList<Map<String, dynamic>>("blocks")
          .map((e) => ScannedBlock.deserializeJson(e))
          .toList(),
    );
  }

  List<ScannedOutputWithIvk> scannedOutputs() =>
      blocks.expand((e) => e.scannedOutputs()).toList();
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.bcsVector(ScannedBlock.layout(), property: "blocks"),
    ], property: property);
  }

  /// Layout without the trailing Ironwood fields, for scans stored
  /// before NU6.3 support.
  static Layout<Map<String, dynamic>> legacyLayout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.bcsVector(ScannedBlock.legacyLayout(), property: "blocks"),
    ], property: property);
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
  final ZcashNetworkProtocol upgrade;
  final int saplingCommitmentTreeSize;
  final int orchardCommitmentTreeSize;
  final int ironwoodCommitmentTreeSize;
  final int orchardFinalTreeSize;
  final int saplingFinalTreeSize;
  final int ironwoodFinalTreeSize;
  final int blockId;
  final int timestamp;
  final String? blockhash;
  final Zip212Enforcement zip212enforcement;
  const BlockStateInfo({
    required this.upgrade,
    required this.saplingCommitmentTreeSize,
    required this.orchardCommitmentTreeSize,
    this.ironwoodCommitmentTreeSize = 0,
    required this.orchardFinalTreeSize,
    required this.saplingFinalTreeSize,
    this.ironwoodFinalTreeSize = 0,
    required this.timestamp,
    required this.blockId,
    required this.blockhash,
    required this.zip212enforcement,
  });
}

class ZcashBlockProcessorConfig {
  final ZcashNetwork network;
  final List<
    ZcashBlockProcessorScanKey<SaplingFullViewingKey, SaplingIncomingViewingKey>
  >
  saplingViewKeys;
  final List<
    ZcashBlockProcessorScanKey<OrchardFullViewingKey, OrchardIncomingViewingKey>
  >
  orchardViewKeys;
  final SaplingDomain saplingDomain;
  final OrchardDomain orchardDomain;

  /// Trial-decryption domain for the Ironwood pool (NU6.3): Orchard-shaped
  /// notes with note version v3. Same viewing keys as the Orchard pool.
  final OrchardDomain ironwoodDomain;
  final ZcashCryptoContext context;
  final UpgradeActivationProvider activationProvider;
  final bool exportMemos;

  late final List<IVKWithActivationHeight<SaplingIncomingViewingKey>>
  saplingIvks = saplingViewKeys.expand((e) => e.viewKeys).toImutableList;
  late final List<IVKWithActivationHeight<OrchardIncomingViewingKey>>
  orchardIvks = orchardViewKeys.expand((e) => e.viewKeys).toImutableList;

  List<SaplingIvk> getSaplingIvks(int height) {
    return saplingIvks
        .where((e) => e.activationHeight <= height)
        .map((e) => e.ivk.ivk)
        .toList();
  }

  List<SaplingIvk> getSplingIvks(int height) {
    return saplingIvks
        .where((e) => e.activationHeight <= height)
        .map((e) => e.ivk.ivk)
        .toList();
  }

  List<OrchardKeyAgreementPrivateKey> getOrchardIvks(int height) {
    return orchardIvks
        .where((e) => e.activationHeight <= height)
        .map((e) => e.ivk.ivk)
        .toList();
  }

  ({
    ZcashBlockProcessorScanKey<SaplingFullViewingKey, SaplingIncomingViewingKey>
    scanKey,
    SaplingIncomingViewingKey ivk,
  })
  findSaplingScanKey(SaplingIvk ivk) {
    for (final i in saplingViewKeys) {
      for (final k in i.viewKeys) {
        if (k.ivk.ivk == ivk) return (scanKey: i, ivk: k.ivk);
      }
    }
    throw ZcashErrors.scannerFailed(
      "findSaplingIncommingViewKey",
      reason: "key not found.",
    );
  }

  ({
    ZcashBlockProcessorScanKey<OrchardFullViewingKey, OrchardIncomingViewingKey>
    scanKey,
    OrchardIncomingViewingKey ivk,
  })
  findOrchardScanKey(OrchardKeyAgreementPrivateKey ivk) {
    for (final i in orchardViewKeys) {
      for (final k in i.viewKeys) {
        if (k.ivk.ivk == ivk) return (scanKey: i, ivk: k.ivk);
      }
    }
    throw ZcashErrors.scannerFailed(
      "findOrchardIncommingViewKey",
      reason: "key not found.",
    );
  }

  ZcashBlockProcessorConfig({
    required this.network,
    required this.context,
    this.exportMemos = false,
    UpgradeActivationProvider? activationProvider,

    List<
          ZcashBlockProcessorScanKey<
            SaplingFullViewingKey,
            SaplingIncomingViewingKey
          >
        >
        saplingViewKeys =
        const [],
    List<
          ZcashBlockProcessorScanKey<
            OrchardFullViewingKey,
            OrchardIncomingViewingKey
          >
        >
        orchardViewKeys =
        const [],
    SaplingDomain? saplingDomain,
    OrchardDomain? orchardDomain,
    OrchardDomain? ironwoodDomain,
  }) : saplingDomain = saplingDomain ?? SaplingDomain(context),
       orchardDomain = orchardDomain ?? OrchardDomain(context),
       ironwoodDomain =
           ironwoodDomain ??
           OrchardDomain(context, version: OrchardNoteVersion.v3),
       saplingViewKeys = saplingViewKeys.immutable,
       orchardViewKeys = orchardViewKeys.immutable,
       activationProvider =
           activationProvider ?? DefaultUpgradeActivationProvider();
}

class IVKWithActivationHeight<IVK extends IncomingViewingKey> {
  final IVK ivk;
  final int activationHeight;
  const IVKWithActivationHeight({required this.ivk, this.activationHeight = 0});
}

class ZcashBlockProcessorScanKey<
  FVK extends Object,
  IVK extends IncomingViewingKey
> {
  final FVK? fvk;
  final List<IVKWithActivationHeight<IVK>> viewKeys;
  ZcashBlockProcessorScanKey({
    this.fvk,
    List<IVKWithActivationHeight<IVK>> viewKeys = const [],
  }) : viewKeys = viewKeys.immutable;
}

class ChainState with LayoutSerializable, CborTagSerializable {
  final NonEmptyFrontier<OrchardMerkleHash>? finalOrchardTree;
  final NonEmptyFrontier<SaplingNode>? finalSaplingTree;

  final NonEmptyFrontier<OrchardMerkleHash>? finalIronwoodTree;
  final int blockHeight;
  final List<int> blockHash;
  const ChainState({
    required this.blockHash,
    required this.blockHeight,
    required this.finalOrchardTree,
    required this.finalSaplingTree,
    this.finalIronwoodTree,
  });
  factory ChainState.deserialize({List<int>? bytes, CborObject? object}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.chainState,
      cborBytes: bytes,
      cborObject: object,
    );
    return ChainState(
      finalOrchardTree: values
          .maybeObjectAt<NonEmptyFrontier<OrchardMerkleHash>, CborTagValue>(
            0,
            (e) => NonEmptyFrontier.deserialize(
              object: e,
              fromBytes: OrchardMerkleHash.fromBytes,
            ),
          ),
      finalSaplingTree: values
          .maybeObjectAt<NonEmptyFrontier<SaplingNode>, CborTagValue>(
            1,
            (e) => NonEmptyFrontier.deserialize(
              object: e,
              fromBytes: SaplingNode.fromBytes,
            ),
          ),
      blockHeight: values.rawValueAt(2),
      blockHash: values.rawValueAt(3),
      finalIronwoodTree: switch (values.objectAt<CborObject?>(4)) {
        null => null,
        final o => NonEmptyFrontier.deserialize(
          object: o,
          fromBytes: OrchardMerkleHash.fromBytes,
        ),
      },
    );
  }

  factory ChainState.deserializeJson({required Map<String, dynamic> json}) {
    return ChainState(
      blockHash: json.valueAsBytes("block_hash"),
      blockHeight: json.valueAsInt("block_height"),
      finalOrchardTree: json
          .valueTo<NonEmptyFrontier<OrchardMerkleHash>?, Map<String, dynamic>>(
            key: "final_orchard_tree",
            parse:
                (e) => NonEmptyFrontier<OrchardMerkleHash>.deserializeJson(
                  json: json,
                  fromBytes: (bytes) => OrchardMerkleHash.fromBytes(bytes),
                ),
          ),

      finalSaplingTree: json
          .valueTo<NonEmptyFrontier<SaplingNode>?, Map<String, dynamic>>(
            key: "final_sapling_tree",
            parse:
                (e) => NonEmptyFrontier<SaplingNode>.deserializeJson(
                  json: json,
                  fromBytes: (bytes) => SaplingNode.fromBytes(bytes),
                ),
          ),
      finalIronwoodTree: json
          .valueTo<NonEmptyFrontier<OrchardMerkleHash>?, Map<String, dynamic>>(
            key: "final_ironwood_tree",
            parse:
                (e) => NonEmptyFrontier<OrchardMerkleHash>.deserializeJson(
                  json: e,
                  fromBytes: (bytes) => OrchardMerkleHash.fromBytes(bytes),
                ),
          ),
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "block_hash"),
      LayoutConst.lebU32(property: "block_height"),
      LayoutConst.optional(
        NonEmptyFrontier.layout(),
        property: "final_orchard_tree",
      ),
      LayoutConst.optional(
        NonEmptyFrontier.layout(),
        property: "final_sapling_tree",
      ),
      LayoutConst.optional(
        NonEmptyFrontier.layout(),
        property: "final_ironwood_tree",
      ),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "block_hash": blockHash,
      "block_height": blockHeight,
      "final_orchard_tree": finalOrchardTree?.toSerializeJson(),
      "final_sapling_tree": finalSaplingTree?.toSerializeJson(),
      "final_ironwood_tree": finalIronwoodTree?.toSerializeJson(),
    };
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.chainState;

  @override
  List<CborObject?> get serializationItems => [
    finalOrchardTree?.toCbor(),
    finalSaplingTree?.toCbor(),
    blockHeight.toCbor(),
    CborBytesValue(blockHash),
    finalIronwoodTree?.toCbor(),
  ];
}

abstract class ScannedOutputWithNullifier<
  OUTPUT extends ScannedOutput,
  NULLIFIER extends Nullifier
>
    with LayoutSerializable, PartialEquality {
  final OUTPUT output;
  final NULLIFIER nullifier;
  final ZcashTxId txId;
  final int blockHeight;
  final int blocktime;
  final List<int>? memo;
  const ScannedOutputWithNullifier({
    required this.output,
    required this.nullifier,
    required this.txId,
    required this.blockHeight,
    required this.blocktime,
    required this.memo,
  });
  ScannedOutputWithNullifier<OUTPUT, NULLIFIER> withoutMemo();

  factory ScannedOutputWithNullifier.deserialize(List<int> bytes) {
    final decode = LayoutSerializable.deserialize(
      bytes: bytes,
      layout: ScannedOutputWithNullifier.layout(),
    );
    return ScannedOutputWithNullifier.deserializeJson(decode);
  }
  factory ScannedOutputWithNullifier.deserializeJson(
    Map<String, dynamic> json,
  ) {
    final protocol = ZcashProtocol.fromValue(json.valueAsInt("protocol"));
    final ScannedOutputWithNullifier output = switch (protocol) {
      ZcashProtocol.sapling =>
        SaplingScannedOutputWithNullifier.deserializeJson(json),
      ZcashProtocol.orchard =>
        OrchardScannedOutputWithNullifier.deserializeJson(json),
      ZcashProtocol.transparent =>
        throw ZcashErrors.scannerFailed(
          "ScannedOutputWithNullifier",
          reason: "Invalid shield protocol.",
        ),
    };
    return output.cast();
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.u8(property: "protocol"),
      ScannedOutput.layout(property: "output"),
      LayoutConst.optional(Nullifier.layout(), property: "nullifier"),
      ZcashTxId.layout(property: "tx_id"),
      LayoutConst.lebU32(property: "block_height"),
      LayoutConst.lebU64(property: "block_time"),
      LayoutConst.optional(LayoutConst.bcsBytes(), property: "memo"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "protocol": output.protocol.value,
      "output": output.toSerializeJson(),
      "nullifier": nullifier.toSerializeJson(),
      "tx_id": txId.toSerializeJson(),
      "block_height": blockHeight,
      "block_time": blocktime.toBigInt,
      "memo": memo,
    };
  }

  @override
  List<dynamic> get parts => [nullifier];

  String get identifier => BytesUtils.toHexString(nullifier.toBytes());

  T cast<T extends ScannedOutputWithNullifier>() {
    if (this is! T) {
      throw BuError(
        DefaultErrorType.castFailed,
        "Failed to cast value",
        details: {"expected": "T", "value": runtimeType.toString()},
      );
    }
    return this as T;
  }
}

class SaplingScannedOutputWithNullifier
    extends ScannedOutputWithNullifier<SaplingScannedOutput, SaplingNullifier> {
  const SaplingScannedOutputWithNullifier({
    required super.output,
    required super.nullifier,
    required super.blockHeight,
    required super.txId,
    required super.blocktime,
    required super.memo,
  });
  factory SaplingScannedOutputWithNullifier.deserialize(List<int> bytes) {
    final decode = LayoutSerializable.deserialize(
      bytes: bytes,
      layout: ScannedOutputWithNullifier.layout(),
    );
    return SaplingScannedOutputWithNullifier.deserializeJson(decode);
  }
  factory SaplingScannedOutputWithNullifier.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return SaplingScannedOutputWithNullifier(
      output: SaplingScannedOutput.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("output"),
      ),
      nullifier: SaplingNullifier.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("nullifier"),
      ),
      blockHeight: json.valueAs("block_height"),
      txId: ZcashTxId.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("tx_id"),
      ),
      blocktime: json.valueAsInt("block_time"),
      memo: json.valueAsBytes("memo"),
    );
  }

  @override
  SaplingScannedOutputWithNullifier withoutMemo() {
    return SaplingScannedOutputWithNullifier(
      output: output,
      nullifier: nullifier,
      blockHeight: blockHeight,
      txId: txId,
      blocktime: blocktime,
      memo: null,
    );
  }
}

class OrchardScannedOutputWithNullifier
    extends ScannedOutputWithNullifier<OrchardScannedOutput, OrchardNullifier> {
  const OrchardScannedOutputWithNullifier({
    required super.output,
    required super.nullifier,
    required super.txId,
    required super.blockHeight,
    required super.blocktime,
    required super.memo,
  });
  factory OrchardScannedOutputWithNullifier.deserialize(List<int> bytes) {
    final decode = LayoutSerializable.deserialize(
      bytes: bytes,
      layout: ScannedOutputWithNullifier.layout(),
    );
    return OrchardScannedOutputWithNullifier.deserializeJson(decode);
  }
  factory OrchardScannedOutputWithNullifier.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return OrchardScannedOutputWithNullifier(
      output: OrchardScannedOutput.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("output"),
      ),
      nullifier: OrchardNullifier.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("nullifier"),
      ),
      blockHeight: json.valueAs("block_height"),
      txId: ZcashTxId.deserializeJson(
        json.valueEnsureAsMap<String, dynamic>("tx_id"),
      ),
      blocktime: json.valueAsInt("block_time"),
      memo: json.valueAsBytes("memo"),
    );
  }

  @override
  OrchardScannedOutputWithNullifier withoutMemo() {
    return OrchardScannedOutputWithNullifier(
      output: output,
      nullifier: nullifier,
      txId: txId,
      blockHeight: blockHeight,
      blocktime: blocktime,
      memo: null,
    );
  }
}

class FullScannedOutput {
  final IncomingViewingKey viewKey;
  final ScannedOutputWithNullifier output;
  final Bip44Changes changes;
  final DiversifierIndex index;
  const FullScannedOutput({
    required this.viewKey,
    required this.output,
    required this.changes,
    required this.index,
  });

  ZcashAddress? address({ZcashNetwork network = ZcashNetwork.mainnet}) {
    final addr = viewKey.addressAt(index);
    return ZcashUnifiedAddress.fromReceivers(
      receivers: [
        switch (viewKey.protocol) {
          ZcashProtocol.orchard => ReceiverOrchard(
            data: addr.toBytes(),
            mode: UnifiedReceiverMode.address,
          ),
          _ => ReceiverSapling(
            data: addr.toBytes(),
            mode: UnifiedReceiverMode.address,
          ),
        },
      ],
      network: network,
    ).toProtocolAddress(viewKey.protocol);
  }
}

class ScannedNullifiers with CborTagSerializable, Equality {
  final int blockId;
  final int timestamp;
  final String? blockhash;
  final List<ScannedBlockNullifier<OrchardNullifier>> orchardNullifiers;
  final List<ScannedBlockNullifier<SaplingNullifier>> saplingNullifiers;

  /// Ironwood-pool nullifiers (NU6.3 second pool, separate nullifier set).
  final List<ScannedBlockNullifier<OrchardNullifier>> ironwoodNullifiers;
  ScannedNullifiers({
    required this.blockId,
    required this.timestamp,
    required this.blockhash,
    List<ScannedBlockNullifier<OrchardNullifier>> orchardNullifiers = const [],
    List<ScannedBlockNullifier<SaplingNullifier>> saplingNullifiers = const [],
    List<ScannedBlockNullifier<OrchardNullifier>> ironwoodNullifiers = const [],
  }) : orchardNullifiers = orchardNullifiers.immutable,
       saplingNullifiers = saplingNullifiers.immutable,
       ironwoodNullifiers = ironwoodNullifiers.immutable;
  factory ScannedNullifiers.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.scanedBlockNullifiers,
      cborBytes: bytes,
      cborObject: object,
    );
    List<ScannedBlockNullifier<OrchardNullifier>> readIronwood() {
      try {
        return values
            .listAt<CborTagValue>(5)
            .map(
              (e) => ScannedBlockNullifier.deserialize(
                object: e,
                fromBytes: OrchardNullifier.fromBytes,
              ),
            )
            .toList();
      } catch (_) {
        // Scans stored before NU6.3 support have no sixth item.
        return [];
      }
    }

    return ScannedNullifiers(
      blockId: values.rawValueAt(0),
      timestamp: values.rawValueAt(1),
      blockhash: values.rawValueAt(2),
      orchardNullifiers:
          values
              .listAt<CborTagValue>(3)
              .map(
                (e) => ScannedBlockNullifier.deserialize(
                  object: e,
                  fromBytes: OrchardNullifier.fromBytes,
                ),
              )
              .toList(),
      saplingNullifiers:
          values
              .listAt<CborTagValue>(3)
              .map(
                (e) => ScannedBlockNullifier.deserialize(
                  object: e,
                  fromBytes: (bytes) => SaplingNullifier(bytes),
                ),
              )
              .toList(),
      ironwoodNullifiers: readIronwood(),
    );
  }

  List<Nullifier> get nullifiers => [
    ...orchardNullifiers.map((e) => e.nullifier),
    ...saplingNullifiers.map((e) => e.nullifier),
    ...ironwoodNullifiers.map((e) => e.nullifier),
  ];

  @override
  List<dynamic> get variables => [
    blockId,
    timestamp,
    blockhash,
    orchardNullifiers,
    saplingNullifiers,
    ironwoodNullifiers,
  ];

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.scanedBlockNullifiers;
  @override
  List<CborObject?> get serializationItems => [
    blockId.toCbor(),
    timestamp.toCbor(),
    blockhash?.toCbor(),
    CborTagSerializable.listFromDynamic(
      orchardNullifiers.map((e) => e.toCbor()).toList(),
    ),
    CborTagSerializable.listFromDynamic(
      saplingNullifiers.map((e) => e.toCbor()).toList(),
    ),
    CborTagSerializable.listFromDynamic(
      ironwoodNullifiers.map((e) => e.toCbor()).toList(),
    ),
  ];
}

class ScannedBlocksBundles with CborTagSerializable {
  final List<ScannedBlockBundles> bundles;
  final int startHeight;
  ScannedBlocksBundles({
    required List<ScannedBlockBundles> bundles,
    required int startHeight,
  }) : startHeight = startHeight.asU32,
       bundles =
           bundles
               .min(length: 1, operation: "ScannedBlocksBundles")
               .toImutableList;
  factory ScannedBlocksBundles.deserialize({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.scannedBlocksBundles,
      cborBytes: bytes,
      cborObject: object,
    );
    return ScannedBlocksBundles(
      bundles:
          values
              .listAt<CborTagValue>(0)
              .map((e) => ScannedBlockBundles.deserialize(object: e))
              .toList(),
      startHeight: values.rawValueAt(1),
    );
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.scannedBlocksBundles;

  @override
  List<CborObject?> get serializationItems => [
    CborTagSerializable.listFromDynamic(
      bundles.map((e) => e.toCbor()).toList(),
    ),
    startHeight.toCbor(),
  ];
}
