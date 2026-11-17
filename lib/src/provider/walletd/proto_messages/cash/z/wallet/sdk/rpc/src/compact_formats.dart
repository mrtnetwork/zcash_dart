import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/provider/walletd/proto_messages/types.dart';
import 'package:zcash_dart/src/serialization/protobuf/protobuf.dart';

/// Copyright (c) 2019-2021 The Zcash developers
/// Distributed under the MIT software license, see the accompanying
/// file COPYING or https://www.opensource.org/licenses/mit-license.php .
/// REMINDER: proto3 fields are all optional. A field that is not present will be set to its zero/false/empty
/// value.
/// Information about the state of the chain as of a given block.
class ZWalletdChainMetadata extends ZcashProtoMessage with ChainMetadata {
  @override
  final int? saplingCommitmentTreeSize;

  /// the size of the Sapling note commitment tree as of the end of this block
  @override
  final int? orchardCommitmentTreeSize;

  /// the size of the Orchard note commitment tree as of the end of this block
  @override
  final int? ironwoodCommitmentTreeSize;

  const ZWalletdChainMetadata({
    this.saplingCommitmentTreeSize,
    this.orchardCommitmentTreeSize,
    this.ironwoodCommitmentTreeSize,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.uint32(1),
        ProtoFieldConfig.uint32(2),
        ProtoFieldConfig.uint32(3),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [
    saplingCommitmentTreeSize,
    orchardCommitmentTreeSize,
    ironwoodCommitmentTreeSize,
  ];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'saplingCommitmentTreeSize': saplingCommitmentTreeSize,
      'orchardCommitmentTreeSize': orchardCommitmentTreeSize,
      'ironwoodCommitmentTreeSize': ironwoodCommitmentTreeSize,
    };
  }

  factory ZWalletdChainMetadata.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdChainMetadata(
      saplingCommitmentTreeSize: json.valueAsInt<int?>(
        'saplingCommitmentTreeSize',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      orchardCommitmentTreeSize: json.valueAsInt<int?>(
        'orchardCommitmentTreeSize',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      ironwoodCommitmentTreeSize: json.valueAsInt<int?>(
        'ironwoodCommitmentTreeSize',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdChainMetadata.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdChainMetadata(
      saplingCommitmentTreeSize: decode.getInt<int?>(1),
      orchardCommitmentTreeSize: decode.getInt<int?>(2),
      ironwoodCommitmentTreeSize: decode.getInt<int?>(3),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcChainMetadata;
}

/// the size of the Ironwood note commitment tree as of the end of this block
/// A compact representation of a Zcash block.
///
/// CompactBlock is a packaging of ONLY the data from a block that's needed to:
/// 1. Detect a payment to your Shielded address
/// 2. Detect a spend of your Shielded notes
/// 3. Update your witnesses to generate new spend proofs.
/// 4. Spend UTXOs associated to t-addresses of your wallet.
///
/// Currently, the `header` field should always be unset (empty). In the future,
/// the presence or absence of header data may be made dependent on request
/// parameters, although it is likely that such flexibility will only be provided via
/// newly-added service methods, not via existing APIs.
class ZWalletdCompactBlock extends ZcashProtoMessage with CompactBlock {
  /// Field 1 (`protoVersion`) was removed; see
  /// https://github.com/zcash/lightwallet-protocol/issues/25
  @override
  final BigInt? height;

  /// the height of this block
  @override
  final List<int>? hash;

  /// if present, the ID (hash) of this block
  final List<int>? prevHash;

  /// if present, the ID (hash) of this block's predecessor
  @override
  final int? time;

  /// if non-zero, Unix epoch time when the block was mined
  final List<int>? header;

  /// if present, full header (as returned by the getblock RPC)
  @override
  final List<ZWalletdCompactTx> vtx;

  /// zero or more compact transactions from this block
  @override
  final ZWalletdChainMetadata? chainMetadata;

  const ZWalletdCompactBlock({
    this.height,
    this.hash,
    this.prevHash,
    this.time,
    this.header,
    this.vtx = const [],
    this.chainMetadata,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.bytes(4),
        ProtoFieldConfig.uint32(5),
        ProtoFieldConfig.bytes(6),
        ProtoFieldConfig.repeated(
          fieldNumber: 7,
          elementType: ProtoFieldType.message,
        ),
        ProtoFieldConfig.message(8),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [
    height,
    hash,
    prevHash,
    time,
    header,
    vtx,
    chainMetadata,
  ];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'height': config.encodeBigint(height),
      'hash': config.encodeBinary(hash),
      'prevHash': config.encodeBinary(prevHash),
      'time': time,
      'header': config.encodeBinary(header),
      'vtx': vtx.map((e) => config.encodeMessage(e)).toList(),
      'chainMetadata': config.encodeMessage(chainMetadata),
    };
  }

  factory ZWalletdCompactBlock.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdCompactBlock(
      height: json.valueAsBigInt<BigInt?>(
        'height',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      hash: config.decodeBinary<List<int>?>(
        json.valueAs('hash', normalizeKeyLookup: config.normalizeKeys),
      ),
      prevHash: config.decodeBinary<List<int>?>(
        json.valueAs('prevHash', normalizeKeyLookup: config.normalizeKeys),
      ),
      time: json.valueAsInt<int?>(
        'time',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      header: config.decodeBinary<List<int>?>(
        json.valueAs('header', normalizeKeyLookup: config.normalizeKeys),
      ),
      vtx:
          (json.valueEnsureAsList<dynamic>(
                'vtx',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdCompactTx, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdCompactTx.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
      chainMetadata: json.valueTo<ZWalletdChainMetadata?, Object>(
        key: 'chainMetadata',
        parse:
            (v) => ZWalletdChainMetadata.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdCompactBlock.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdCompactBlock(
      height: decode.getBigInt<BigInt?>(2),
      hash: decode.getBytes<List<int>?>(3),
      prevHash: decode.getBytes<List<int>?>(4),
      time: decode.getInt<int?>(5),
      header: decode.getBytes<List<int>?>(6),
      vtx:
          decode
              .getListOfBytes(7)
              .map((b) => ZWalletdCompactTx.deserialize(b))
              .toList(),
      chainMetadata: decode.messageTo<ZWalletdChainMetadata?>(
        8,
        (b) => ZWalletdChainMetadata.deserialize(b),
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcCompactBlock;
}

/// information about the state of the chain as of this block
/// A compact representation of a Zcash transaction.
///
/// CompactTx contains the minimum information for a wallet to know if this transaction
/// is relevant to it (either pays to it or spends from it) via shielded elements. Additionally,
/// it can optionally include the minimum necessary data to detect payments to transparent addresses
/// related to your wallet.
class ZWalletdCompactTx extends ZcashProtoMessage with CompactTx {
  /// The index of the transaction within the block.
  @override
  final BigInt? index;

  /// The id of the transaction as defined in
  /// [§ 7.1.1 ‘Transaction Identifiers’](https://zips.z.cash/protocol/protocol.pdf#txnidentifiers)
  /// This byte array MUST be in protocol order and MUST NOT be reversed
  /// or hex-encoded; the byte-reversed and hex-encoded representation is
  /// exclusively a textual representation of a txid.
  @override
  final List<int>? txid;

  /// The transaction fee: present if server can provide. In the case of a
  /// stateless server and a transaction with transparent inputs, this will be
  /// unset because the calculation requires reference to prior transactions.
  /// If there are no transparent inputs, the fee will be calculable as:
  /// valueBalanceSapling + valueBalanceOrchard + valueBalanceIronwood
  /// + sum(vPubNew) - sum(vPubOld) - sum(tOut)
  final int? fee;

  @override
  final List<ZWalletdCompactSaplingSpend> spends;

  @override
  final List<ZWalletdCompactSaplingOutput> outputs;

  @override
  final List<ZWalletdCompactOrchardAction> actions;

  @override
  final List<ZWalletdCompactOrchardAction> ironwoodActions;

  /// `CompactTxIn` values corresponding to the `vin` entries of the full transaction.
  ///
  /// Note: the single null-outpoint input for coinbase transactions is omitted. Light
  /// clients can test `CompactTx.index == 0` to determine whether a `CompactTx`
  /// represents a coinbase transaction, as the coinbase transaction is always the
  /// first transaction in any block.
  final List<ZWalletdCompactTxIn> vin;

  /// A sequence of transparent outputs being created by the transaction.
  final List<ZWalletdTxOut> vout;

  const ZWalletdCompactTx({
    this.index,
    this.txid,
    this.fee,
    this.spends = const [],
    this.outputs = const [],
    this.actions = const [],
    this.ironwoodActions = const [],
    this.vin = const [],
    this.vout = const [],
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.uint64(1),
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.uint32(3),
        ProtoFieldConfig.repeated(
          fieldNumber: 4,
          elementType: ProtoFieldType.message,
        ),
        ProtoFieldConfig.repeated(
          fieldNumber: 5,
          elementType: ProtoFieldType.message,
        ),
        ProtoFieldConfig.repeated(
          fieldNumber: 6,
          elementType: ProtoFieldType.message,
        ),
        ProtoFieldConfig.repeated(
          fieldNumber: 9,
          elementType: ProtoFieldType.message,
        ),
        ProtoFieldConfig.repeated(
          fieldNumber: 7,
          elementType: ProtoFieldType.message,
        ),
        ProtoFieldConfig.repeated(
          fieldNumber: 8,
          elementType: ProtoFieldType.message,
        ),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [
    index,
    txid,
    fee,
    spends,
    outputs,
    actions,
    ironwoodActions,
    vin,
    vout,
  ];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'index': config.encodeBigint(index),
      'txid': config.encodeBinary(txid),
      'fee': fee,
      'spends': spends.map((e) => config.encodeMessage(e)).toList(),
      'outputs': outputs.map((e) => config.encodeMessage(e)).toList(),
      'actions': actions.map((e) => config.encodeMessage(e)).toList(),
      'ironwoodActions':
          ironwoodActions.map((e) => config.encodeMessage(e)).toList(),
      'vin': vin.map((e) => config.encodeMessage(e)).toList(),
      'vout': vout.map((e) => config.encodeMessage(e)).toList(),
    };
  }

  factory ZWalletdCompactTx.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdCompactTx(
      index: json.valueAsBigInt<BigInt?>(
        'index',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      txid: config.decodeBinary<List<int>?>(
        json.valueAs('txid', normalizeKeyLookup: config.normalizeKeys),
      ),
      fee: json.valueAsInt<int?>(
        'fee',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      spends:
          (json.valueEnsureAsList<dynamic>(
                'spends',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdCompactSaplingSpend, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdCompactSaplingSpend.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
      outputs:
          (json.valueEnsureAsList<dynamic>(
                'outputs',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdCompactSaplingOutput, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdCompactSaplingOutput.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
      actions:
          (json.valueEnsureAsList<dynamic>(
                'actions',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdCompactOrchardAction, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdCompactOrchardAction.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
      ironwoodActions:
          (json.valueEnsureAsList<dynamic>(
                'ironwoodActions',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdCompactOrchardAction, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdCompactOrchardAction.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
      vin:
          (json.valueEnsureAsList<dynamic>(
                'vin',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdCompactTxIn, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdCompactTxIn.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
      vout:
          (json.valueEnsureAsList<dynamic>(
                'vout',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdTxOut, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdTxOut.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
    );
  }

  factory ZWalletdCompactTx.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdCompactTx(
      index: decode.getBigInt<BigInt?>(1),
      txid: decode.getBytes<List<int>?>(2),
      fee: decode.getInt<int?>(3),
      spends:
          decode
              .getListOfBytes(4)
              .map((b) => ZWalletdCompactSaplingSpend.deserialize(b))
              .toList(),
      outputs:
          decode
              .getListOfBytes(5)
              .map((b) => ZWalletdCompactSaplingOutput.deserialize(b))
              .toList(),
      actions:
          decode
              .getListOfBytes(6)
              .map((b) => ZWalletdCompactOrchardAction.deserialize(b))
              .toList(),
      ironwoodActions:
          decode
              .getListOfBytes(9)
              .map((b) => ZWalletdCompactOrchardAction.deserialize(b))
              .toList(),
      vin:
          decode
              .getListOfBytes(7)
              .map((b) => ZWalletdCompactTxIn.deserialize(b))
              .toList(),
      vout:
          decode
              .getListOfBytes(8)
              .map((b) => ZWalletdTxOut.deserialize(b))
              .toList(),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcCompactTx;
}

/// A compact representation of a transparent transaction input.
class ZWalletdCompactTxIn extends ZcashProtoMessage {
  /// The id of the transaction that generated the output being spent. This
  /// byte array must be in protocol order and MUST NOT be reversed or
  /// hex-encoded.
  final List<int>? prevoutTxid;

  /// The index of the output being spent in the `vout` array of the
  /// transaction referred to by `prevoutTxid`.
  final int? prevoutIndex;

  const ZWalletdCompactTxIn({this.prevoutTxid, this.prevoutIndex});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.bytes(1), ProtoFieldConfig.uint32(2)],
    );
  }

  @override
  List<Object?> get protoValues => [prevoutTxid, prevoutIndex];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'prevoutTxid': config.encodeBinary(prevoutTxid),
      'prevoutIndex': prevoutIndex,
    };
  }

  factory ZWalletdCompactTxIn.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdCompactTxIn(
      prevoutTxid: config.decodeBinary<List<int>?>(
        json.valueAs('prevoutTxid', normalizeKeyLookup: config.normalizeKeys),
      ),
      prevoutIndex: json.valueAsInt<int?>(
        'prevoutIndex',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdCompactTxIn.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdCompactTxIn(
      prevoutTxid: decode.getBytes<List<int>?>(1),
      prevoutIndex: decode.getInt<int?>(2),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcCompactTxIn;
}

/// A transparent output being created by the transaction.
///
/// This contains identical data to the `TxOut` type in the transaction itself, and
/// thus it is not "compact".
class ZWalletdTxOut extends ZcashProtoMessage {
  /// The value of the output, in Zatoshis.
  final BigInt? value;

  /// The script pubkey that must be satisfied in order to spend this output.
  final List<int>? scriptPubKey;

  const ZWalletdTxOut({this.value, this.scriptPubKey});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.uint64(1), ProtoFieldConfig.bytes(2)],
    );
  }

  @override
  List<Object?> get protoValues => [value, scriptPubKey];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'value': config.encodeBigint(value),
      'scriptPubKey': config.encodeBinary(scriptPubKey),
    };
  }

  factory ZWalletdTxOut.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdTxOut(
      value: json.valueAsBigInt<BigInt?>(
        'value',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      scriptPubKey: config.decodeBinary<List<int>?>(
        json.valueAs('scriptPubKey', normalizeKeyLookup: config.normalizeKeys),
      ),
    );
  }

  factory ZWalletdTxOut.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdTxOut(
      value: decode.getBigInt<BigInt?>(1),
      scriptPubKey: decode.getBytes<List<int>?>(2),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcTxOut;
}

/// A compact representation of a [Sapling Spend](https://zips.z.cash/protocol/protocol.pdf#spendencodingandconsensus).
///
/// CompactSaplingSpend is a Sapling Spend Description as described in 7.3 of the Zcash
/// protocol specification.
class ZWalletdCompactSaplingSpend extends ZcashProtoMessage
    with CompactSaplingSpend {
  @override
  final List<int>? nf;

  const ZWalletdCompactSaplingSpend({this.nf});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.bytes(1)],
    );
  }

  @override
  List<Object?> get protoValues => [nf];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'nf': config.encodeBinary(nf)};
  }

  factory ZWalletdCompactSaplingSpend.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdCompactSaplingSpend(
      nf: config.decodeBinary<List<int>?>(
        json.valueAs('nf', normalizeKeyLookup: config.normalizeKeys),
      ),
    );
  }

  factory ZWalletdCompactSaplingSpend.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdCompactSaplingSpend(nf: decode.getBytes<List<int>?>(1));
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcCompactSaplingSpend;
}

/// Nullifier (see the Zcash protocol specification)
/// A compact representation of a [Sapling Output](https://zips.z.cash/protocol/protocol.pdf#outputencodingandconsensus).
///
/// It encodes the `cmu` field, `ephemeralKey` field, and a 52-byte prefix of the
/// `encCiphertext` field of a Sapling Output Description. Total size is 116 bytes.
class ZWalletdCompactSaplingOutput extends ZcashProtoMessage
    with CompactSaplingOutput {
  @override
  final List<int>? cmu;

  /// Note commitment u-coordinate.
  @override
  final List<int>? ephemeralKey;

  /// Ephemeral public key.
  @override
  final List<int>? ciphertext;

  const ZWalletdCompactSaplingOutput({
    this.cmu,
    this.ephemeralKey,
    this.ciphertext,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.bytes(1),
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.bytes(3),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [cmu, ephemeralKey, ciphertext];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'cmu': config.encodeBinary(cmu),
      'ephemeralKey': config.encodeBinary(ephemeralKey),
      'ciphertext': config.encodeBinary(ciphertext),
    };
  }

  factory ZWalletdCompactSaplingOutput.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdCompactSaplingOutput(
      cmu: config.decodeBinary<List<int>?>(
        json.valueAs('cmu', normalizeKeyLookup: config.normalizeKeys),
      ),
      ephemeralKey: config.decodeBinary<List<int>?>(
        json.valueAs('ephemeralKey', normalizeKeyLookup: config.normalizeKeys),
      ),
      ciphertext: config.decodeBinary<List<int>?>(
        json.valueAs('ciphertext', normalizeKeyLookup: config.normalizeKeys),
      ),
    );
  }

  factory ZWalletdCompactSaplingOutput.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdCompactSaplingOutput(
      cmu: decode.getBytes<List<int>?>(1),
      ephemeralKey: decode.getBytes<List<int>?>(2),
      ciphertext: decode.getBytes<List<int>?>(3),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcCompactSaplingOutput;
}

/// First 52 bytes of ciphertext.
/// A compact representation of an [Orchard Action](https://zips.z.cash/protocol/protocol.pdf#actionencodingandconsensus).
class ZWalletdCompactOrchardAction extends ZcashProtoMessage
    with CompactOrchardAction {
  @override
  final List<int>? nullifier;

  /// [32] The nullifier of the input note
  @override
  final List<int>? cmx;

  /// [32] The x-coordinate of the note commitment for the output note
  @override
  final List<int>? ephemeralKey;

  /// [32] An encoding of an ephemeral Pallas public key
  @override
  final List<int>? ciphertext;

  const ZWalletdCompactOrchardAction({
    this.nullifier,
    this.cmx,
    this.ephemeralKey,
    this.ciphertext,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.bytes(1),
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.bytes(4),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [nullifier, cmx, ephemeralKey, ciphertext];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'nullifier': config.encodeBinary(nullifier),
      'cmx': config.encodeBinary(cmx),
      'ephemeralKey': config.encodeBinary(ephemeralKey),
      'ciphertext': config.encodeBinary(ciphertext),
    };
  }

  factory ZWalletdCompactOrchardAction.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdCompactOrchardAction(
      nullifier: config.decodeBinary<List<int>?>(
        json.valueAs('nullifier', normalizeKeyLookup: config.normalizeKeys),
      ),
      cmx: config.decodeBinary<List<int>?>(
        json.valueAs('cmx', normalizeKeyLookup: config.normalizeKeys),
      ),
      ephemeralKey: config.decodeBinary<List<int>?>(
        json.valueAs('ephemeralKey', normalizeKeyLookup: config.normalizeKeys),
      ),
      ciphertext: config.decodeBinary<List<int>?>(
        json.valueAs('ciphertext', normalizeKeyLookup: config.normalizeKeys),
      ),
    );
  }

  factory ZWalletdCompactOrchardAction.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdCompactOrchardAction(
      nullifier: decode.getBytes<List<int>?>(1),
      cmx: decode.getBytes<List<int>?>(2),
      ephemeralKey: decode.getBytes<List<int>?>(3),
      ciphertext: decode.getBytes<List<int>?>(4),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcCompactOrchardAction;
}
