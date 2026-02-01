import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/provider/walletd/exception/exception.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transparent/transparent.dart';

class WalletdChainMetadata with ProtobufEncodableMessage {
  final int? saplingCommitmentTreeSize;
  final int? orchardCommitmentTreeSize;
  const WalletdChainMetadata(
      {this.saplingCommitmentTreeSize, this.orchardCommitmentTreeSize});
  factory WalletdChainMetadata.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdChainMetadata(
        saplingCommitmentTreeSize: decode.getInt(1),
        orchardCommitmentTreeSize: decode.getInt(2));
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.uint32(1),
        ProtoFieldConfig.uint32(2),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues =>
      [saplingCommitmentTreeSize, orchardCommitmentTreeSize];
}

class WalletdCompactOrchardAction
    with ProtobufEncodableMessage, CompactOrchardAction, Equality {
  @override
  final List<int>? nullifier;
  @override
  final List<int>? cmx;
  @override
  final List<int>? ephemeralKey;
  @override
  final List<int>? ciphertext;
  const WalletdCompactOrchardAction(
      {this.nullifier, this.cmx, this.ephemeralKey, this.ciphertext});
  factory WalletdCompactOrchardAction.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdCompactOrchardAction(
        nullifier: decode.getBytes(1),
        cmx: decode.getBytes(2),
        ephemeralKey: decode.getBytes(3),
        ciphertext: decode.getBytes(4));
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.bytes(1),
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.bytes(4),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [nullifier, cmx, ephemeralKey, ciphertext];

  @override
  List<dynamic> get variables => [nullifier, cmx, ephemeralKey, ciphertext];
}

class WalletdCompactSaplingOutput
    with ProtobufEncodableMessage, CompactSaplingOutput, Equality {
  @override
  final List<int>? cmu;
  @override
  final List<int>? ephemeralKey;
  @override
  final List<int>? ciphertext;
  const WalletdCompactSaplingOutput(
      {this.cmu, this.ephemeralKey, this.ciphertext});
  factory WalletdCompactSaplingOutput.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdCompactSaplingOutput(
        cmu: decode.getBytes(1),
        ephemeralKey: decode.getBytes(2),
        ciphertext: decode.getBytes(3));
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.bytes(1),
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.bytes(3)
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [cmu, ephemeralKey, ciphertext];

  @override
  List<dynamic> get variables => [cmu, ephemeralKey, ciphertext];
}

class WalletdCompactSaplingSpend
    with ProtobufEncodableMessage, CompactSaplingSpend, Equality {
  @override
  final List<int>? nf;
  const WalletdCompactSaplingSpend({this.nf});
  factory WalletdCompactSaplingSpend.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdCompactSaplingSpend(nf: decode.getBytes(1));
  }
  static List<ProtoFieldConfig> get fields => [ProtoFieldConfig.bytes(1)];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [nf];

  @override
  List<dynamic> get variables => [nf];
}

class WalletdCompactTx with ProtobufEncodableMessage, CompactTx {
  @override
  final int index;
  @override
  final List<int>? hash;
  final int? fee;
  @override
  final List<WalletdCompactSaplingSpend>? spends;
  @override
  final List<WalletdCompactSaplingOutput>? outputs;
  @override
  final List<WalletdCompactOrchardAction>? actions;
  const WalletdCompactTx(
      {required this.index,
      this.hash,
      this.fee,
      this.spends,
      this.actions,
      this.outputs});
  factory WalletdCompactTx.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdCompactTx(
      index:
          decode.getBigInt<BigInt>(1, defaultValue: BigInt.zero).toIntOrThrow,
      hash: decode.getBytes(2),
      fee: decode.getInt(3),
      spends: decode
          .getListOrNull<List<int>>(4)
          ?.map((e) => WalletdCompactSaplingSpend.deserialize(e))
          .toList(),
      outputs: decode
          .getListOrNull<List<int>>(5)
          ?.map((e) => WalletdCompactSaplingOutput.deserialize(e))
          .toList(),
      actions: decode
          .getListOrNull<List<int>>(6)
          ?.map((e) => WalletdCompactOrchardAction.deserialize(e))
          .toList(),
    );
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.uint64(1),
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.uint32(3),
        ProtoFieldConfig.repeated(
            fieldNumber: 4,
            elementType: ProtoFieldType.message,
            encoding: ProtoRepeatedEncoding.unpacked),
        ProtoFieldConfig.repeated(
            fieldNumber: 5,
            elementType: ProtoFieldType.message,
            encoding: ProtoRepeatedEncoding.unpacked),
        ProtoFieldConfig.repeated(
            fieldNumber: 6,
            elementType: ProtoFieldType.message,
            encoding: ProtoRepeatedEncoding.unpacked),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues =>
      [index, hash, fee, spends, outputs, actions];
}

class WalletdCompactBlock with ProtobufEncodableMessage, CompactBlock {
  final int? protoVersion;
  @override
  final int height;
  @override
  final List<int>? hash;
  final List<int>? prevHash;
  @override
  final int? time;
  final List<int>? header;
  @override
  final List<WalletdCompactTx>? vtx;
  final WalletdChainMetadata? chainMetadata;
  const WalletdCompactBlock({
    required this.height,
    this.protoVersion,
    this.hash,
    this.prevHash,
    this.time,
    this.header,
    this.vtx,
    this.chainMetadata,
  });
  factory WalletdCompactBlock.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdCompactBlock(
      protoVersion: decode.getInt(1),
      height: decode.getInt(2, defaultValue: 0),
      hash: decode.getBytes(3),
      prevHash: decode.getBytes(4),
      time: decode.getInt(5),
      header: decode.getBytes(6),
      vtx: decode
          .getListOrNull<List<int>>(7)
          ?.map((e) => WalletdCompactTx.deserialize(e))
          .toList(),
      chainMetadata: JsonParser.valueTo<WalletdChainMetadata?, List<int>>(
        value: decode.getBytes<List<int>?>(8),
        parse: (v) => WalletdChainMetadata.deserialize(v),
      ),
    );
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.uint32(1),
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.bytes(4),
        ProtoFieldConfig.uint32(5),
        ProtoFieldConfig.bytes(6),
        ProtoFieldConfig.repeated(
            fieldNumber: 7,
            elementType: ProtoFieldType.message,
            encoding: ProtoRepeatedEncoding.unpacked),
        ProtoFieldConfig.message(8)
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues =>
      [protoVersion, height, hash, prevHash, time, header, vtx, chainMetadata];

  @override
  int? get orchardCommitmentTreeSize =>
      chainMetadata?.orchardCommitmentTreeSize;

  @override
  int? get saplingCommitmentTreeSize =>
      chainMetadata?.saplingCommitmentTreeSize;
}

class WalletdBlockId with ProtobufEncodableMessage {
  final int? height;
  final List<int>? hash;
  const WalletdBlockId({this.height, this.hash});
  factory WalletdBlockId.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdBlockId(height: decode.getInt(1), hash: decode.getBytes(2));
  }
  factory WalletdBlockId.height(int height) {
    return WalletdBlockId(height: height);
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.uint64(1),
        ProtoFieldConfig.bytes(2),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [height, hash];
}

class WalletdBlockRange with ProtobufEncodableMessage {
  final WalletdBlockId? start;
  final WalletdBlockId? end;
  const WalletdBlockRange({this.start, this.end});
  factory WalletdBlockRange.range(int start, int end) {
    assert(start <= end);
    return WalletdBlockRange(
        start: WalletdBlockId(height: start), end: WalletdBlockId(height: end));
  }
  factory WalletdBlockRange.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdBlockRange(
        start: JsonParser.valueTo<WalletdBlockId?, List<int>>(
          value: decode.getBytes<List<int>?>(1),
          parse: (v) => WalletdBlockId.deserialize(v),
        ),
        end: JsonParser.valueTo<WalletdBlockId?, List<int>>(
          value: decode.getBytes<List<int>?>(2),
          parse: (v) => WalletdBlockId.deserialize(v),
        ));
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.message(2),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [start, end];
}

class WalletdTxFilter with ProtobufEncodableMessage {
  final WalletdBlockId? block;
  final BigInt? index;
  final List<int>? hash;
  const WalletdTxFilter({this.block, this.index, this.hash});
  factory WalletdTxFilter.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdTxFilter(
      block: JsonParser.valueTo<WalletdBlockId?, List<int>>(
        value: decode.getBytes<List<int>?>(1),
        parse: (v) => WalletdBlockId.deserialize(v),
      ),
      index: decode.getBigInt(2),
      hash: decode.getBytes(3),
    );
  }
  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.bytes(3),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [block, index, hash];
}

class WalletdRawTransaction with ProtobufEncodableMessage {
  final List<int>? data;
  final int? height;
  const WalletdRawTransaction({this.data, this.height});
  factory WalletdRawTransaction.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdRawTransaction(
      data: decode.getBytes(1),
      height: decode.getInt(2),
    );
  }
  static List<ProtoFieldConfig> get fields =>
      [ProtoFieldConfig.bytes(1), ProtoFieldConfig.uint64(2)];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [data, height];
}

class WalletdSendResponse with ProtobufEncodableMessage {
  final int errorCode;
  final String? message;
  const WalletdSendResponse({this.errorCode = 0, this.message});
  factory WalletdSendResponse.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdSendResponse(
      errorCode: decode.getInt<int>(1, defaultValue: 0),
      message: decode.getString(2),
    );
  }
  static List<ProtoFieldConfig> get fields =>
      [ProtoFieldConfig.int32(1), ProtoFieldConfig.string(2)];
  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [errorCode, message];
  @override
  String toString() {
    return "code: $errorCode message: $message";
  }
}

class LightdInfo with ProtobufEncodableMessage {
  final String? version;
  final String? vendor;
  final bool? taddrSupport;
  final String? chainName;
  final BigInt? saplingActivationHeight;
  final String? consensusBranchId;
  final BigInt? blockHeight;
  final String? gitCommit;
  final String? branch;
  final String? buildDate;
  final String? buildUser;
  final BigInt? estimatedHeight;
  final String? zcashdBuild;
  final String? zcashdSubversion;
  final String? donationAddress;

  const LightdInfo({
    this.version,
    this.vendor,
    this.taddrSupport,
    this.chainName,
    this.saplingActivationHeight,
    this.consensusBranchId,
    this.blockHeight,
    this.gitCommit,
    this.branch,
    this.buildDate,
    this.buildUser,
    this.estimatedHeight,
    this.zcashdBuild,
    this.zcashdSubversion,
    this.donationAddress,
  });

  factory LightdInfo.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return LightdInfo(
      version: decode.getString(1),
      vendor: decode.getString(2),
      taddrSupport: decode.getBool(3),
      chainName: decode.getString(4),
      saplingActivationHeight: decode.getBigInt(5),
      consensusBranchId: decode.getString(6),
      blockHeight: decode.getBigInt(7),
      gitCommit: decode.getString(8),
      branch: decode.getString(9),
      buildDate: decode.getString(10),
      buildUser: decode.getString(11),
      estimatedHeight: decode.getBigInt(12),
      zcashdBuild: decode.getString(13),
      zcashdSubversion: decode.getString(14),
      donationAddress: decode.getString(15),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.string(1),
        ProtoFieldConfig.string(2),
        ProtoFieldConfig.bool(3),
        ProtoFieldConfig.string(4),
        ProtoFieldConfig.uint64(5),
        ProtoFieldConfig.string(6),
        ProtoFieldConfig.uint64(7),
        ProtoFieldConfig.string(8),
        ProtoFieldConfig.string(9),
        ProtoFieldConfig.string(10),
        ProtoFieldConfig.string(11),
        ProtoFieldConfig.uint64(12),
        ProtoFieldConfig.string(13),
        ProtoFieldConfig.string(14),
        ProtoFieldConfig.string(15),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        version,
        vendor,
        taddrSupport,
        chainName,
        saplingActivationHeight,
        consensusBranchId,
        blockHeight,
        gitCommit,
        branch,
        buildDate,
        buildUser,
        estimatedHeight,
        zcashdBuild,
        zcashdSubversion,
        donationAddress,
      ];
}

class TransparentAddressBlockFilter with ProtobufEncodableMessage {
  final String? address;
  final WalletdBlockRange? range;

  const TransparentAddressBlockFilter({
    this.address,
    this.range,
  });

  factory TransparentAddressBlockFilter.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return TransparentAddressBlockFilter(
      address: decode.getString(1),
      range: JsonParser.valueTo<WalletdBlockRange?, List<int>>(
        value: decode.getBytes<List<int>?>(2),
        parse: (v) => WalletdBlockRange.deserialize(v),
      ),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.string(1),
        ProtoFieldConfig.message(2),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        address,
        range,
      ];
}

class WalletdPingDuration with ProtobufEncodableMessage {
  final BigInt? intervalUs;

  const WalletdPingDuration({
    this.intervalUs,
  });

  factory WalletdPingDuration.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdPingDuration(
      intervalUs: decode.getBigInt(1),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.int64(1),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        intervalUs,
      ];
}

class WalletdPingResponse with ProtobufEncodableMessage {
  final BigInt? entry;
  final BigInt? exit;

  const WalletdPingResponse({
    this.entry,
    this.exit,
  });

  factory WalletdPingResponse.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdPingResponse(
      entry: decode.getBigInt(1),
      exit: decode.getBigInt(2),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.int64(1),
        ProtoFieldConfig.int64(2),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        entry,
        exit,
      ];
}

class WalletdTAddress with ProtobufEncodableMessage {
  final String? address;

  const WalletdTAddress({
    this.address,
  });

  factory WalletdTAddress.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdTAddress(
      address: decode.getString(1),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.string(1),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        address,
      ];
}

class WalletdTAddressList with ProtobufEncodableMessage {
  final List<String>? addresses;

  const WalletdTAddressList({
    this.addresses,
  });

  factory WalletdTAddressList.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdTAddressList(
      addresses: decode.getListOrNull<String>(1),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.repeated(
          fieldNumber: 1,
          elementType: ProtoFieldType.string,
          encoding: ProtoRepeatedEncoding.unpacked,
        ),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        addresses,
      ];
}

class WalletdTAddressBalance with ProtobufEncodableMessage {
  final BigInt? valueZat;

  const WalletdTAddressBalance({
    this.valueZat,
  });

  factory WalletdTAddressBalance.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdTAddressBalance(
      valueZat: decode.getBigInt(1),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.int64(1),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [valueZat];
}

class WalletdTxExclude with ProtobufEncodableMessage {
  final List<List<int>>? txid;
  const WalletdTxExclude({this.txid});
  factory WalletdTxExclude.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdTxExclude(txid: decode.getListOrNull<List<int>>(1));
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.repeated(
            fieldNumber: 1,
            elementType: ProtoFieldType.bytes,
            encoding: ProtoRepeatedEncoding.unpacked),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        txid,
      ];
}

class WalletdTreeState with ProtobufEncodableMessage {
  final String? network;
  final int? height;
  final String? hash;
  final int? time;
  final String? saplingTree;
  final String? orchardTree;
  const WalletdTreeState(
      {this.network,
      this.height,
      this.hash,
      this.time,
      this.saplingTree,
      this.orchardTree});

  factory WalletdTreeState.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdTreeState(
      network: decode.getString(1),
      height: decode.getInt<int?>(2),
      hash: decode.getString(3),
      time: decode.getInt(4),
      saplingTree: decode.getString(5),
      orchardTree: decode.getString(6),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.string(1),
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.string(3),
        ProtoFieldConfig.uint32(4),
        ProtoFieldConfig.string(5),
        ProtoFieldConfig.string(6),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues =>
      [network, height, hash, time, saplingTree, orchardTree];

  ChainState toChainState() {
    final blockHash = hash;
    if (blockHash == null) {
      throw WalletdException.failed("toChainState",
          reason: "Missing block hash");
    }
    final height = this.height;
    if (height == null) {
      throw WalletdException.failed("toChainState",
          reason: "Missing block height");
    }
    final orchardTree = this.orchardTree;
    final saplingTree = this.saplingTree;
    return ChainState(
        blockHash: BytesUtils.fromHexString(blockHash).reversed.toList(),
        blockHeight: height,
        finalOrchardTree: orchardTree == null
            ? Frontier()
            : OrchardCommitmentTree.deserialize(
                    BytesUtils.fromHexString(orchardTree))
                .toFrontier(),
        finalSaplingTree: saplingTree == null
            ? Frontier()
            : SaplingCommitmentTree.deserialize(
                    BytesUtils.fromHexString(saplingTree))
                .toFrontier());
  }
}

class WalletdSubtreeRoot with ProtobufEncodableMessage {
  /// 32-byte Merkle root of the subtree
  final List<int>? rootHash;

  /// Hash of the block that completed the subtree
  final List<int>? completingBlockHash;

  /// Height of the completing block in the main chain
  final int? completingBlockHeight;

  const WalletdSubtreeRoot({
    this.rootHash,
    this.completingBlockHash,
    this.completingBlockHeight,
  });

  factory WalletdSubtreeRoot.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdSubtreeRoot(
      rootHash: decode.getBytes(2),
      completingBlockHash: decode.getBytes(3),
      completingBlockHeight: decode.getBigInt<BigInt?>(4)?.toIntOrThrow,
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.uint64(4)
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues =>
      [rootHash, completingBlockHash, completingBlockHeight];
}

class WalletdGetAddressUtxosReply with ProtobufEncodableMessage {
  final String? address;
  final List<int>? txid;
  final int index;
  final List<int>? script;
  final BigInt valueZat;
  final int? height;

  const WalletdGetAddressUtxosReply(
      {this.address,
      this.txid,
      required this.index,
      this.script,
      required this.valueZat,
      this.height});

  factory WalletdGetAddressUtxosReply.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdGetAddressUtxosReply(
      address: decode.getString(6),
      txid: decode.getBytes(1),
      index: decode.getInt<int>(2, defaultValue: 0),
      script: decode.getBytes(3),
      valueZat: decode.getBigInt<BigInt>(4, defaultValue: BigInt.zero),
      height: decode.getInt(5),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.bytes(1),
        ProtoFieldConfig.int32(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.int64(4),
        ProtoFieldConfig.uint64(5),
        ProtoFieldConfig.string(6),
      ];

  TransparentUtxo toUtxo() {
    final txid = this.txid;
    if (txid == null) {
      throw WalletdException.failed("toUtxo",
          reason: "Missing utxo transaction id.");
    }
    return TransparentUtxo(
        txHash: txid, value: valueZat, vout: index, blockHeight: height);
  }

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues =>
      [txid, index, script, valueZat, height, address];
}

class WalletdGetAddressUtxosReplyList with ProtobufEncodableMessage {
  final List<WalletdGetAddressUtxosReply> addressUtxos;
  const WalletdGetAddressUtxosReplyList(this.addressUtxos);

  factory WalletdGetAddressUtxosReplyList.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdGetAddressUtxosReplyList(
      decode
              .getListOrNull<List<int>>(1)
              ?.map((e) => WalletdGetAddressUtxosReply.deserialize(e))
              .toList() ??
          [],
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.repeated(
            fieldNumber: 1,
            elementType: ProtoFieldType.message,
            encoding: ProtoRepeatedEncoding.unpacked)
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [addressUtxos];
}

enum ShieldedProtocol implements ProtobufEnumVariant {
  sapling(0),
  orchard(1);

  @override
  final int protoValue;
  const ShieldedProtocol(this.protoValue);

  static ShieldedProtocol? fromValue(int? value) {
    if (value == null) return null;
    return ShieldedProtocol.values.firstWhere((e) => e.protoValue == value,
        orElse: () => throw ItemNotFoundException(value: value));
  }
}

class GetSubtreeRootsArg with ProtobufEncodableMessage {
  final int? startIndex;
  final ShieldedProtocol? shieldedProtocol;
  final int? maxEntries;
  const GetSubtreeRootsArg(
      {this.startIndex, this.shieldedProtocol, this.maxEntries});
  factory GetSubtreeRootsArg.defaultConfig(ShieldedProtocol protocol) {
    return GetSubtreeRootsArg(shieldedProtocol: protocol);
  }
  factory GetSubtreeRootsArg.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return GetSubtreeRootsArg(
        startIndex: decode.getInt(1),
        shieldedProtocol: decode.getInt(2),
        maxEntries: decode.getInt(3));
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.uint32(1),
        ProtoFieldConfig.enumType(2),
        ProtoFieldConfig.uint32(3)
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        startIndex,
        shieldedProtocol?.protoValue,
        maxEntries,
      ];
}

class WalletdGetAddressUtxosArg with ProtobufEncodableMessage {
  final List<String>? addresses;
  final int? startHeight;
  final int? maxEntries;

  const WalletdGetAddressUtxosArg({
    this.addresses,
    this.startHeight,
    this.maxEntries,
  });

  factory WalletdGetAddressUtxosArg.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, fields);
    return WalletdGetAddressUtxosArg(
      addresses: decode.getListOrNull<String>(1),
      startHeight: decode.getBigInt<BigInt?>(2)?.toIntOrThrow,
      maxEntries: decode.getInt(3),
    );
  }

  static List<ProtoFieldConfig> get fields => [
        ProtoFieldConfig.repeated(
          fieldNumber: 1,
          elementType: ProtoFieldType.string,
          encoding: ProtoRepeatedEncoding.unpacked,
        ),
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.uint32(3),
      ];

  @override
  List<ProtoFieldConfig> get bufferFields => fields;

  @override
  List<Object?> get bufferValues => [
        addresses,
        startHeight,
        maxEntries,
      ];
}
