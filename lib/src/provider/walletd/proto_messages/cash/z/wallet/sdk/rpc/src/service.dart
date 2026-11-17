import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/provider/walletd/proto_messages/types.dart';
import 'package:zcash_dart/src/serialization/protobuf/protobuf.dart';
import "package:zcash_dart/src/provider/walletd/proto_messages/cash/z/wallet/sdk/rpc/src/compact_formats.dart"
    as cash_z_wallet_sdk_rpc_compact_formats;

/// Copyright (c) 2019-2020 The Zcash developers
/// Distributed under the MIT software license, see the accompanying
/// file COPYING or https://www.opensource.org/licenses/mit-license.php .
/// An identifier for a Zcash value pool.
enum ZWalletdPoolType implements ProtoEnumVariant {
  poolTypeInvalid(0, 'POOL_TYPE_INVALID'),
  transparent(1, 'TRANSPARENT'),
  sapling(2, 'SAPLING'),
  orchard(3, 'ORCHARD'),
  ironwood(4, 'IRONWOOD');

  const ZWalletdPoolType(this.value, this.protoName);

  /// The original proto wire value for this enum constant.
  @override
  final int value;

  /// The original proto identifier, e.g. "VOTE_OPTION_UNSPECIFIED".
  @override
  final String protoName;

  /// Looks up a value by its proto wire int. Throws if not found.
  static ZWalletdPoolType fromValue(int? value) {
    value ??= 0;
    return ZWalletdPoolType.values.firstWhere(
      (e) => e.value == value,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching ZWalletdPoolType found for the given value. $value",
                details: {
                  "name": "ZWalletdPoolType",
                  "value": value?.toString(),
                },
              ),
    );
  }

  /// Looks up a value by wire int, Dart enum name, or original proto
  /// name (whichever [value] happens to be). Throws if not found.
  static ZWalletdPoolType from(Object? value) {
    value ??= 0;
    return ZWalletdPoolType.values.firstWhere(
      (e) => e.value == value || e.name == value || e.protoName == value,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching ZWalletdPoolType found for the given value. $value",
                details: {
                  "name": "ZWalletdPoolType",
                  "value": value?.toString(),
                },
              ),
    );
  }
}

/// ironwood commitment tree state
enum ZWalletdShieldedProtocol implements ProtoEnumVariant {
  sapling(0, 'sapling'),
  orchard(1, 'orchard'),
  ironwood(2, 'ironwood');

  const ZWalletdShieldedProtocol(this.value, this.protoName);

  /// The original proto wire value for this enum constant.
  @override
  final int value;

  /// The original proto identifier, e.g. "VOTE_OPTION_UNSPECIFIED".
  @override
  final String protoName;

  /// Looks up a value by its proto wire int. Throws if not found.
  static ZWalletdShieldedProtocol fromValue(int? value) {
    value ??= 0;
    return ZWalletdShieldedProtocol.values.firstWhere(
      (e) => e.value == value,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching ZWalletdShieldedProtocol found for the given value. $value",
                details: {
                  "name": "ZWalletdShieldedProtocol",
                  "value": value?.toString(),
                },
              ),
    );
  }

  /// Looks up a value by wire int, Dart enum name, or original proto
  /// name (whichever [value] happens to be). Throws if not found.
  static ZWalletdShieldedProtocol from(Object? value) {
    value ??= 0;
    return ZWalletdShieldedProtocol.values.firstWhere(
      (e) => e.value == value || e.name == value || e.protoName == value,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching ZWalletdShieldedProtocol found for the given value. $value",
                details: {
                  "name": "ZWalletdShieldedProtocol",
                  "value": value?.toString(),
                },
              ),
    );
  }
}

/// A BlockID message contains identifiers to select a block: a height or a
/// hash. Support for specification by hash is not mandatory. (If `hash` is
/// non-empty, the rpc may return an error.) This field is present to support
/// a possible future upgrade.
class ZWalletdBlockID extends ZcashProtoMessage {
  final BigInt? height;

  final List<int>? hash;

  const ZWalletdBlockID({this.height, this.hash});

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
  List<Object?> get protoValues => [height, hash];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'height': config.encodeBigint(height),
      'hash': config.encodeBinary(hash),
    };
  }

  factory ZWalletdBlockID.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdBlockID(
      height: json.valueAsBigInt<BigInt?>(
        'height',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      hash: config.decodeBinary<List<int>?>(
        json.valueAs('hash', normalizeKeyLookup: config.normalizeKeys),
      ),
    );
  }

  factory ZWalletdBlockID.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdBlockID(
      height: decode.getBigInt<BigInt?>(1),
      hash: decode.getBytes<List<int>?>(2),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcBlockID;
}

/// BlockRange specifies a series of blocks from start to end inclusive.
/// Both BlockIDs must be heights; specification by hash is not yet supported.
///
/// If no pool types are specified, the server should default to the legacy
/// behavior of returning only data relevant to the shielded (Sapling, Orchard,
/// and Ironwood) pools; otherwise, the server should prune `CompactBlock`s
/// returned to include only data relevant to the requested pool types. Clients MUST
/// verify that the version of the server they are connected to are capable
/// of returning pruned and/or transparent data before setting `poolTypes`
/// to a non-empty value.
class ZWalletdBlockRange extends ZcashProtoMessage {
  final ZWalletdBlockID? start;

  final ZWalletdBlockID? end;

  final List<ZWalletdPoolType> poolTypes;

  const ZWalletdBlockRange({this.start, this.end, this.poolTypes = const []});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.message(2),
        ProtoFieldConfig.repeated(
          fieldNumber: 3,
          elementType: ProtoFieldType.enumType,
        ),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [start, end, poolTypes];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'start': config.encodeMessage(start),
      'end': config.encodeMessage(end),
      'poolTypes': poolTypes.map((e) => config.encodeEnum(e)).toList(),
    };
  }

  factory ZWalletdBlockRange.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdBlockRange(
      start: json.valueTo<ZWalletdBlockID?, Object>(
        key: 'start',
        parse:
            (v) =>
                ZWalletdBlockID.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
      end: json.valueTo<ZWalletdBlockID?, Object>(
        key: 'end',
        parse:
            (v) =>
                ZWalletdBlockID.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
      poolTypes:
          (json.valueEnsureAsList<dynamic>(
                'poolTypes',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdPoolType, Object>(
                  value: e,
                  parse: (v) => ZWalletdPoolType.from(v),
                ),
              )
              .toList(),
    );
  }

  factory ZWalletdBlockRange.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdBlockRange(
      start: decode.messageTo<ZWalletdBlockID?>(
        1,
        (b) => ZWalletdBlockID.deserialize(b),
      ),
      end: decode.messageTo<ZWalletdBlockID?>(
        2,
        (b) => ZWalletdBlockID.deserialize(b),
      ),
      poolTypes: decode.getReapeatedEnum<ZWalletdPoolType>(
        3,
        ZWalletdPoolType.values,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcBlockRange;
}

/// A TxFilter contains the information needed to identify a particular
/// transaction: either a block and an index, or a direct transaction hash.
/// Currently, only specification by hash is supported.
class ZWalletdTxFilter extends ZcashProtoMessage {
  final ZWalletdBlockID? block;

  /// block identifier, height or hash
  final BigInt? index;

  /// index within the block
  final List<int>? hash;

  const ZWalletdTxFilter({this.block, this.index, this.hash});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.bytes(3),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [block, index, hash];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'block': config.encodeMessage(block),
      'index': config.encodeBigint(index),
      'hash': config.encodeBinary(hash),
    };
  }

  factory ZWalletdTxFilter.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdTxFilter(
      block: json.valueTo<ZWalletdBlockID?, Object>(
        key: 'block',
        parse:
            (v) =>
                ZWalletdBlockID.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
      index: json.valueAsBigInt<BigInt?>(
        'index',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      hash: config.decodeBinary<List<int>?>(
        json.valueAs('hash', normalizeKeyLookup: config.normalizeKeys),
      ),
    );
  }

  factory ZWalletdTxFilter.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdTxFilter(
      block: decode.messageTo<ZWalletdBlockID?>(
        1,
        (b) => ZWalletdBlockID.deserialize(b),
      ),
      index: decode.getBigInt<BigInt?>(2),
      hash: decode.getBytes<List<int>?>(3),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcTxFilter;
}

/// transaction ID (hash, txid)
/// RawTransaction contains the complete transaction data. It also optionally includes
/// the block height in which the transaction was included, or, when returned
/// by GetMempoolStream(), the latest block height.
///
class ZWalletdRawTransaction extends ZcashProtoMessage {
  /// The serialized representation of the Zcash transaction.
  final List<int>? data;

  /// The height at which the transaction is mined, or a sentinel value.
  ///
  /// Due to an error in the original protobuf definition, it is necessary to
  /// reinterpret the result of the `getrawtransaction` RPC call. Zcashd will
  /// return the int64 value `-1` for the height of transactions that appear
  /// in the block index, but which are not mined in the main chain. Here, the
  /// height field of `RawTransaction` was erroneously created as a `uint64`,
  /// and as such we must map the response from the zcashd RPC API to be
  /// representable within this space. Additionally, the `height` field will
  /// be absent for transactions in the mempool, resulting in the default
  /// value of `0` being set. Therefore, the meanings of the `height` field of
  /// the `RawTransaction` type are as follows:
  ///
  /// * height 0: the transaction is in the mempool
  /// * height 0xffffffffffffffff: the transaction has been mined on a fork that
  /// is not currently the main chain
  /// * any other height: the transaction has been mined in the main chain at the
  /// given height
  final BigInt? height;

  const ZWalletdRawTransaction({this.data, this.height});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.bytes(1), ProtoFieldConfig.uint64(2)],
    );
  }

  @override
  List<Object?> get protoValues => [data, height];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'data': config.encodeBinary(data),
      'height': config.encodeBigint(height),
    };
  }

  factory ZWalletdRawTransaction.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdRawTransaction(
      data: config.decodeBinary<List<int>?>(
        json.valueAs('data', normalizeKeyLookup: config.normalizeKeys),
      ),
      height: json.valueAsBigInt<BigInt?>(
        'height',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdRawTransaction.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdRawTransaction(
      data: decode.getBytes<List<int>?>(1),
      height: decode.getBigInt<BigInt?>(2),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcRawTransaction;
}

/// A SendResponse encodes an error code and a string. It is currently used
/// only by SendTransaction(). If error code is zero, the operation was
/// successful; if non-zero, it and the message specify the failure.
class ZWalletdSendResponse extends ZcashProtoMessage {
  final int? errorCode;

  final String? errorMessage;

  const ZWalletdSendResponse({this.errorCode, this.errorMessage});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.int32(1), ProtoFieldConfig.string(2)],
    );
  }

  @override
  List<Object?> get protoValues => [errorCode, errorMessage];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'errorCode': errorCode, 'errorMessage': errorMessage};
  }

  factory ZWalletdSendResponse.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdSendResponse(
      errorCode: json.valueAsInt<int?>(
        'errorCode',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      errorMessage: json.valueAsString<String?>(
        'errorMessage',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdSendResponse.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdSendResponse(
      errorCode: decode.getInt<int?>(1),
      errorMessage: decode.getString<String?>(2),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcSendResponse;
}

/// Chainspec is a placeholder to allow specification of a particular chain fork.
class ZWalletdChainSpec extends ZcashProtoMessage {
  const ZWalletdChainSpec();

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [],
    );
  }

  @override
  List<Object?> get protoValues => [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {};
  }

  factory ZWalletdChainSpec.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdChainSpec();
  }

  factory ZWalletdChainSpec.deserialize(List<int> bytes) {
    return ZWalletdChainSpec();
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcChainSpec;
}

/// Empty is for gRPCs that take no arguments, currently only GetLightdInfo.
class ZWalletdEmpty extends ZcashProtoMessage {
  const ZWalletdEmpty();

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [],
    );
  }

  @override
  List<Object?> get protoValues => [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {};
  }

  factory ZWalletdEmpty.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdEmpty();
  }

  factory ZWalletdEmpty.deserialize(List<int> bytes) {
    return ZWalletdEmpty();
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcEmpty;
}

/// LightdInfo returns various information about this lightwalletd instance
/// and the state of the blockchain.
class ZWalletdLightdInfo extends ZcashProtoMessage {
  final String? version;

  final String? vendor;

  final bool? taddrSupport;

  /// true
  final String? chainName;

  /// either "main" or "test"
  final BigInt? saplingActivationHeight;

  /// depends on mainnet or testnet
  final String? consensusBranchId;

  /// protocol identifier, see consensus/upgrades.cpp
  final BigInt? blockHeight;

  /// latest block on the best chain
  final String? gitCommit;

  final String? branch;

  final String? buildDate;

  final String? buildUser;

  final BigInt? estimatedHeight;

  /// less than tip height if zcashd is syncing
  final String? zcashdBuild;

  /// example: "v4.1.1-877212414"
  final String? zcashdSubversion;

  /// example: "/MagicBean:4.1.1/"
  final String? donationAddress;

  /// Zcash donation UA address
  final String? upgradeName;

  /// name of next pending network upgrade, empty if none scheduled
  final BigInt? upgradeHeight;

  /// height of next pending upgrade, zero if none is scheduled
  final String? lightwalletProtocolVersion;

  const ZWalletdLightdInfo({
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
    this.upgradeName,
    this.upgradeHeight,
    this.lightwalletProtocolVersion,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
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
        ProtoFieldConfig.string(16),
        ProtoFieldConfig.uint64(17),
        ProtoFieldConfig.string(18),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [
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
    upgradeName,
    upgradeHeight,
    lightwalletProtocolVersion,
  ];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'version': version,
      'vendor': vendor,
      'taddrSupport': taddrSupport,
      'chainName': chainName,
      'saplingActivationHeight': config.encodeBigint(saplingActivationHeight),
      'consensusBranchId': consensusBranchId,
      'blockHeight': config.encodeBigint(blockHeight),
      'gitCommit': gitCommit,
      'branch': branch,
      'buildDate': buildDate,
      'buildUser': buildUser,
      'estimatedHeight': config.encodeBigint(estimatedHeight),
      'zcashdBuild': zcashdBuild,
      'zcashdSubversion': zcashdSubversion,
      'donationAddress': donationAddress,
      'upgradeName': upgradeName,
      'upgradeHeight': config.encodeBigint(upgradeHeight),
      'lightwalletProtocolVersion': lightwalletProtocolVersion,
    };
  }

  factory ZWalletdLightdInfo.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdLightdInfo(
      version: json.valueAsString<String?>(
        'version',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      vendor: json.valueAsString<String?>(
        'vendor',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      taddrSupport: json.valueAsBool<bool?>(
        'taddrSupport',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      chainName: json.valueAsString<String?>(
        'chainName',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      saplingActivationHeight: json.valueAsBigInt<BigInt?>(
        'saplingActivationHeight',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      consensusBranchId: json.valueAsString<String?>(
        'consensusBranchId',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      blockHeight: json.valueAsBigInt<BigInt?>(
        'blockHeight',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      gitCommit: json.valueAsString<String?>(
        'gitCommit',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      branch: json.valueAsString<String?>(
        'branch',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      buildDate: json.valueAsString<String?>(
        'buildDate',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      buildUser: json.valueAsString<String?>(
        'buildUser',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      estimatedHeight: json.valueAsBigInt<BigInt?>(
        'estimatedHeight',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      zcashdBuild: json.valueAsString<String?>(
        'zcashdBuild',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      zcashdSubversion: json.valueAsString<String?>(
        'zcashdSubversion',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      donationAddress: json.valueAsString<String?>(
        'donationAddress',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      upgradeName: json.valueAsString<String?>(
        'upgradeName',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      upgradeHeight: json.valueAsBigInt<BigInt?>(
        'upgradeHeight',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      lightwalletProtocolVersion: json.valueAsString<String?>(
        'lightwalletProtocolVersion',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdLightdInfo.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdLightdInfo(
      version: decode.getString<String?>(1),
      vendor: decode.getString<String?>(2),
      taddrSupport: decode.getBool<bool?>(3),
      chainName: decode.getString<String?>(4),
      saplingActivationHeight: decode.getBigInt<BigInt?>(5),
      consensusBranchId: decode.getString<String?>(6),
      blockHeight: decode.getBigInt<BigInt?>(7),
      gitCommit: decode.getString<String?>(8),
      branch: decode.getString<String?>(9),
      buildDate: decode.getString<String?>(10),
      buildUser: decode.getString<String?>(11),
      estimatedHeight: decode.getBigInt<BigInt?>(12),
      zcashdBuild: decode.getString<String?>(13),
      zcashdSubversion: decode.getString<String?>(14),
      donationAddress: decode.getString<String?>(15),
      upgradeName: decode.getString<String?>(16),
      upgradeHeight: decode.getBigInt<BigInt?>(17),
      lightwalletProtocolVersion: decode.getString<String?>(18),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcLightdInfo;
}

/// version of https://github.com/zcash/lightwallet-protocol served by this server
/// TransparentAddressBlockFilter restricts the results of the GRPC methods that
/// use it to the transactions that involve the given address and were mined in
/// the specified block range. Non-default values for both the address and the
/// block range must be specified. Mempool transactions are not included.
///
/// The `poolTypes` field of the `range` argument should be ignored.
/// Implementations MAY consider it an error if any pool types are specified.
class ZWalletdTransparentAddressBlockFilter extends ZcashProtoMessage {
  final String? address;

  /// t-address
  final ZWalletdBlockRange? range;

  const ZWalletdTransparentAddressBlockFilter({this.address, this.range});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.string(1), ProtoFieldConfig.message(2)],
    );
  }

  @override
  List<Object?> get protoValues => [address, range];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'address': address, 'range': config.encodeMessage(range)};
  }

  factory ZWalletdTransparentAddressBlockFilter.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdTransparentAddressBlockFilter(
      address: json.valueAsString<String?>(
        'address',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      range: json.valueTo<ZWalletdBlockRange?, Object>(
        key: 'range',
        parse:
            (v) => ZWalletdBlockRange.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdTransparentAddressBlockFilter.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdTransparentAddressBlockFilter(
      address: decode.getString<String?>(1),
      range: decode.messageTo<ZWalletdBlockRange?>(
        2,
        (b) => ZWalletdBlockRange.deserialize(b),
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcTransparentAddressBlockFilter;
}

/// start, end heights only
/// Duration is currently used only for testing, so that the Ping rpc
/// can simulate a delay, to create many simultaneous connections. Units
/// are microseconds.
class ZWalletdDuration extends ZcashProtoMessage {
  final BigInt? intervalUs;

  const ZWalletdDuration({this.intervalUs});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.int64(1)],
    );
  }

  @override
  List<Object?> get protoValues => [intervalUs];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'intervalUs': config.encodeBigint(intervalUs)};
  }

  factory ZWalletdDuration.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdDuration(
      intervalUs: json.valueAsBigInt<BigInt?>(
        'intervalUs',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdDuration.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdDuration(intervalUs: decode.getBigInt<BigInt?>(1));
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcDuration;
}

/// PingResponse is used to indicate concurrency, how many Ping rpcs
/// are executing upon entry and upon exit (after the delay).
/// This rpc is used for testing only.
class ZWalletdPingResponse extends ZcashProtoMessage {
  final BigInt? entry;

  final BigInt? exit;

  const ZWalletdPingResponse({this.entry, this.exit});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.int64(1), ProtoFieldConfig.int64(2)],
    );
  }

  @override
  List<Object?> get protoValues => [entry, exit];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'entry': config.encodeBigint(entry),
      'exit': config.encodeBigint(exit),
    };
  }

  factory ZWalletdPingResponse.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdPingResponse(
      entry: json.valueAsBigInt<BigInt?>(
        'entry',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      exit: json.valueAsBigInt<BigInt?>(
        'exit',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdPingResponse.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdPingResponse(
      entry: decode.getBigInt<BigInt?>(1),
      exit: decode.getBigInt<BigInt?>(2),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcPingResponse;
}

class ZWalletdAddress extends ZcashProtoMessage {
  final String? address;

  const ZWalletdAddress({this.address});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.string(1)],
    );
  }

  @override
  List<Object?> get protoValues => [address];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'address': address};
  }

  factory ZWalletdAddress.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdAddress(
      address: json.valueAsString<String?>(
        'address',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdAddress.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdAddress(address: decode.getString<String?>(1));
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcAddress;
}

class ZWalletdAddressList extends ZcashProtoMessage {
  final List<String> addresses;

  const ZWalletdAddressList({this.addresses = const []});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.repeated(
          fieldNumber: 1,
          elementType: ProtoFieldType.string,
        ),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [addresses];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'addresses': addresses.map((e) => e).toList()};
  }

  factory ZWalletdAddressList.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdAddressList(
      addresses:
          (json.valueEnsureAsList<dynamic>(
            'addresses',
            normalizeKeyLookup: config.normalizeKeys,
            onMissing: () => [],
          )).map((e) => JsonParser.valueAsString<String>(e)).toList(),
    );
  }

  factory ZWalletdAddressList.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdAddressList(addresses: decode.getListOrEmpty<String>(1));
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcAddressList;
}

class ZWalletdBalance extends ZcashProtoMessage {
  final BigInt? valueZat;

  const ZWalletdBalance({this.valueZat});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [ProtoFieldConfig.int64(1)],
    );
  }

  @override
  List<Object?> get protoValues => [valueZat];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'valueZat': config.encodeBigint(valueZat)};
  }

  factory ZWalletdBalance.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdBalance(
      valueZat: json.valueAsBigInt<BigInt?>(
        'valueZat',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdBalance.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdBalance(valueZat: decode.getBigInt<BigInt?>(1));
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcBalance;
}

/// Request parameters for the `GetMempoolTx` RPC.
class ZWalletdGetMempoolTxRequest extends ZcashProtoMessage {
  /// A list of transaction ID byte string suffixes that should be excluded
  /// from the response. These suffixes may be produced either directly from
  /// the underlying txid bytes, or, if the source values are encoded txid
  /// strings, by truncating the hexadecimal representation of each
  /// transaction ID to an even number of characters, and then hex-decoding
  /// and then byte-reversing this value to obtain the byte representation.
  final List<List<int>> excludeTxidSuffixes;

  /// We reserve field number 2 for a potential future `exclude_txid_prefixes`
  /// field.
  /// The server must prune `CompactTx`s returned to include only data
  /// relevant to the requested pool types. If no pool types are specified,
  /// the server should default to the legacy behavior of returning only data
  /// relevant to the shielded (Sapling, Orchard, and Ironwood) pools.
  final List<ZWalletdPoolType> poolTypes;

  const ZWalletdGetMempoolTxRequest({
    this.excludeTxidSuffixes = const [],
    this.poolTypes = const [],
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.repeated(
          fieldNumber: 1,
          elementType: ProtoFieldType.bytes,
        ),
        ProtoFieldConfig.repeated(
          fieldNumber: 3,
          elementType: ProtoFieldType.enumType,
        ),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [excludeTxidSuffixes, poolTypes];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'exclude_txid_suffixes':
          excludeTxidSuffixes.map((e) => config.encodeBinary(e)).toList(),
      'poolTypes': poolTypes.map((e) => config.encodeEnum(e)).toList(),
    };
  }

  factory ZWalletdGetMempoolTxRequest.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetMempoolTxRequest(
      excludeTxidSuffixes:
          (json.valueEnsureAsList<dynamic>(
            'exclude_txid_suffixes',
            normalizeKeyLookup: config.normalizeKeys,
            onMissing: () => [],
          )).map((e) => config.decodeBinary<List<int>>(e)).toList(),
      poolTypes:
          (json.valueEnsureAsList<dynamic>(
                'poolTypes',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdPoolType, Object>(
                  value: e,
                  parse: (v) => ZWalletdPoolType.from(v),
                ),
              )
              .toList(),
    );
  }

  factory ZWalletdGetMempoolTxRequest.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetMempoolTxRequest(
      excludeTxidSuffixes: decode.getListOfBytes(1),
      poolTypes: decode.getReapeatedEnum<ZWalletdPoolType>(
        3,
        ZWalletdPoolType.values,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetMempoolTxRequest;
}

/// The TreeState is derived from the Zcash z_gettreestate rpc.
class ZWalletdTreeState extends ZcashProtoMessage {
  final String? network;

  /// "main" or "test"
  final BigInt? height;

  /// block height
  final String? hash;

  /// block id
  final int? time;

  /// Unix epoch time when the block was mined
  final String? saplingTree;

  /// sapling commitment tree state
  final String? orchardTree;

  /// orchard commitment tree state
  final String? ironwoodTree;

  const ZWalletdTreeState({
    this.network,
    this.height,
    this.hash,
    this.time,
    this.saplingTree,
    this.orchardTree,
    this.ironwoodTree,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.string(1),
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.string(3),
        ProtoFieldConfig.uint32(4),
        ProtoFieldConfig.string(5),
        ProtoFieldConfig.string(6),
        ProtoFieldConfig.string(7),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [
    network,
    height,
    hash,
    time,
    saplingTree,
    orchardTree,
    ironwoodTree,
  ];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'network': network,
      'height': config.encodeBigint(height),
      'hash': hash,
      'time': time,
      'saplingTree': saplingTree,
      'orchardTree': orchardTree,
      'ironwoodTree': ironwoodTree,
    };
  }

  factory ZWalletdTreeState.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdTreeState(
      network: json.valueAsString<String?>(
        'network',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      height: json.valueAsBigInt<BigInt?>(
        'height',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      hash: json.valueAsString<String?>(
        'hash',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      time: json.valueAsInt<int?>(
        'time',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      saplingTree: json.valueAsString<String?>(
        'saplingTree',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      orchardTree: json.valueAsString<String?>(
        'orchardTree',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      ironwoodTree: json.valueAsString<String?>(
        'ironwoodTree',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdTreeState.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdTreeState(
      network: decode.getString<String?>(1),
      height: decode.getBigInt<BigInt?>(2),
      hash: decode.getString<String?>(3),
      time: decode.getInt<int?>(4),
      saplingTree: decode.getString<String?>(5),
      orchardTree: decode.getString<String?>(6),
      ironwoodTree: decode.getString<String?>(7),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcTreeState;
}

class ZWalletdGetSubtreeRootsArg extends ZcashProtoMessage {
  final int? startIndex;

  /// Index identifying where to start returning subtree roots
  final ZWalletdShieldedProtocol? shieldedProtocol;

  /// Shielded protocol to return subtree roots for
  final int? maxEntries;

  const ZWalletdGetSubtreeRootsArg({
    this.startIndex,
    this.shieldedProtocol,
    this.maxEntries,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.uint32(1),
        ProtoFieldConfig.enumType(2),
        ProtoFieldConfig.uint32(3),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [startIndex, shieldedProtocol, maxEntries];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'startIndex': startIndex,
      'shieldedProtocol': config.encodeEnum(shieldedProtocol),
      'maxEntries': maxEntries,
    };
  }

  factory ZWalletdGetSubtreeRootsArg.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetSubtreeRootsArg(
      startIndex: json.valueAsInt<int?>(
        'startIndex',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      shieldedProtocol: json.valueTo<ZWalletdShieldedProtocol?, Object?>(
        key: 'shieldedProtocol',
        parse: (v) => ZWalletdShieldedProtocol.from(v),
      ),
      maxEntries: json.valueAsInt<int?>(
        'maxEntries',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdGetSubtreeRootsArg.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetSubtreeRootsArg(
      startIndex: decode.getInt<int?>(1),
      shieldedProtocol: decode.getEnum<ZWalletdShieldedProtocol?>(
        2,
        ZWalletdShieldedProtocol.values,
      ),
      maxEntries: decode.getInt<int?>(3),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetSubtreeRootsArg;
}

/// Maximum number of entries to return, or 0 for all entries.
class ZWalletdSubtreeRoot extends ZcashProtoMessage {
  final List<int>? rootHash;

  /// The 32-byte Merkle root of the subtree.
  final List<int>? completingBlockHash;

  /// The hash of the block that completed this subtree.
  final BigInt? completingBlockHeight;

  const ZWalletdSubtreeRoot({
    this.rootHash,
    this.completingBlockHash,
    this.completingBlockHeight,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.bytes(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.uint64(4),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [
    rootHash,
    completingBlockHash,
    completingBlockHeight,
  ];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'rootHash': config.encodeBinary(rootHash),
      'completingBlockHash': config.encodeBinary(completingBlockHash),
      'completingBlockHeight': config.encodeBigint(completingBlockHeight),
    };
  }

  factory ZWalletdSubtreeRoot.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdSubtreeRoot(
      rootHash: config.decodeBinary<List<int>?>(
        json.valueAs('rootHash', normalizeKeyLookup: config.normalizeKeys),
      ),
      completingBlockHash: config.decodeBinary<List<int>?>(
        json.valueAs(
          'completingBlockHash',
          normalizeKeyLookup: config.normalizeKeys,
        ),
      ),
      completingBlockHeight: json.valueAsBigInt<BigInt?>(
        'completingBlockHeight',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdSubtreeRoot.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdSubtreeRoot(
      rootHash: decode.getBytes<List<int>?>(2),
      completingBlockHash: decode.getBytes<List<int>?>(3),
      completingBlockHeight: decode.getBigInt<BigInt?>(4),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcSubtreeRoot;
}

/// The height of the block that completed this subtree in the main chain.
/// Results are sorted by height, which makes it easy to issue another
/// request that picks up from where the previous left off.
class ZWalletdGetAddressUtxosArg extends ZcashProtoMessage {
  final List<String> addresses;

  final BigInt? startHeight;

  final int? maxEntries;

  const ZWalletdGetAddressUtxosArg({
    this.addresses = const [],
    this.startHeight,
    this.maxEntries,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.repeated(
          fieldNumber: 1,
          elementType: ProtoFieldType.string,
        ),
        ProtoFieldConfig.uint64(2),
        ProtoFieldConfig.uint32(3),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [addresses, startHeight, maxEntries];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'addresses': addresses.map((e) => e).toList(),
      'startHeight': config.encodeBigint(startHeight),
      'maxEntries': maxEntries,
    };
  }

  factory ZWalletdGetAddressUtxosArg.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetAddressUtxosArg(
      addresses:
          (json.valueEnsureAsList<dynamic>(
            'addresses',
            normalizeKeyLookup: config.normalizeKeys,
            onMissing: () => [],
          )).map((e) => JsonParser.valueAsString<String>(e)).toList(),
      startHeight: json.valueAsBigInt<BigInt?>(
        'startHeight',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      maxEntries: json.valueAsInt<int?>(
        'maxEntries',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdGetAddressUtxosArg.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetAddressUtxosArg(
      addresses: decode.getListOrEmpty<String>(1),
      startHeight: decode.getBigInt<BigInt?>(2),
      maxEntries: decode.getInt<int?>(3),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetAddressUtxosArg;
}

/// zero means unlimited
class ZWalletdGetAddressUtxosReply extends ZcashProtoMessage {
  final String? address;

  final List<int>? txid;

  final int? index;

  final List<int>? script;

  final BigInt? valueZat;

  final BigInt? height;

  const ZWalletdGetAddressUtxosReply({
    this.address,
    this.txid,
    this.index,
    this.script,
    this.valueZat,
    this.height,
  });

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.string(6),
        ProtoFieldConfig.bytes(1),
        ProtoFieldConfig.int32(2),
        ProtoFieldConfig.bytes(3),
        ProtoFieldConfig.int64(4),
        ProtoFieldConfig.uint64(5),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [
    address,
    txid,
    index,
    script,
    valueZat,
    height,
  ];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'address': address,
      'txid': config.encodeBinary(txid),
      'index': index,
      'script': config.encodeBinary(script),
      'valueZat': config.encodeBigint(valueZat),
      'height': config.encodeBigint(height),
    };
  }

  factory ZWalletdGetAddressUtxosReply.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetAddressUtxosReply(
      address: json.valueAsString<String?>(
        'address',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      txid: config.decodeBinary<List<int>?>(
        json.valueAs('txid', normalizeKeyLookup: config.normalizeKeys),
      ),
      index: json.valueAsInt<int?>(
        'index',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      script: config.decodeBinary<List<int>?>(
        json.valueAs('script', normalizeKeyLookup: config.normalizeKeys),
      ),
      valueZat: json.valueAsBigInt<BigInt?>(
        'valueZat',
        normalizeKeyLookup: config.normalizeKeys,
      ),
      height: json.valueAsBigInt<BigInt?>(
        'height',
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  factory ZWalletdGetAddressUtxosReply.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetAddressUtxosReply(
      address: decode.getString<String?>(6),
      txid: decode.getBytes<List<int>?>(1),
      index: decode.getInt<int?>(2),
      script: decode.getBytes<List<int>?>(3),
      valueZat: decode.getBigInt<BigInt?>(4),
      height: decode.getBigInt<BigInt?>(5),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetAddressUtxosReply;
}

class ZWalletdGetAddressUtxosReplyList extends ZcashProtoMessage {
  final List<ZWalletdGetAddressUtxosReply> addressUtxos;

  const ZWalletdGetAddressUtxosReplyList({this.addressUtxos = const []});

  @override
  ProtoMessageConfig protoConfig() => protoConfigStatic();

  static ProtoMessageConfig protoConfigStatic() {
    return ProtoMessageConfig(
      syntax: ProtoSyntax.v3,
      options: const [],
      fields: [
        ProtoFieldConfig.repeated(
          fieldNumber: 1,
          elementType: ProtoFieldType.message,
        ),
      ],
    );
  }

  @override
  List<Object?> get protoValues => [addressUtxos];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'addressUtxos': addressUtxos.map((e) => config.encodeMessage(e)).toList(),
    };
  }

  factory ZWalletdGetAddressUtxosReplyList.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetAddressUtxosReplyList(
      addressUtxos:
          (json.valueEnsureAsList<dynamic>(
                'addressUtxos',
                normalizeKeyLookup: config.normalizeKeys,
                onMissing: () => [],
              ))
              .map(
                (e) => JsonParser.valueTo<ZWalletdGetAddressUtxosReply, Object>(
                  value: e,
                  parse:
                      (v) => ZWalletdGetAddressUtxosReply.fromJson(
                        JsonParser.valueAs(v),
                        config: config,
                      ),
                ),
              )
              .toList(),
    );
  }

  factory ZWalletdGetAddressUtxosReplyList.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetAddressUtxosReplyList(
      addressUtxos:
          decode
              .getListOfBytes(1)
              .map((b) => ZWalletdGetAddressUtxosReply.deserialize(b))
              .toList(),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetAddressUtxosReplyList;
}

class ZWalletdGetLatestBlock extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdBlockID> {
  /// Return the BlockID of the block at the tip of the best chain
  final ZWalletdChainSpec? getLatestBlock;

  const ZWalletdGetLatestBlock({this.getLatestBlock});

  @override
  ProtoMessageConfig protoConfig() =>
      getLatestBlock?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getLatestBlock?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetLatestBlock': config.encodeMessage(getLatestBlock)};
  }

  factory ZWalletdGetLatestBlock.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetLatestBlock(
      getLatestBlock: json.valueTo<ZWalletdChainSpec?, Object>(
        key: 'GetLatestBlock',
        parse:
            (v) => ZWalletdChainSpec.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetLatestBlock;
  @override
  ZWalletdBlockID onQueryResponse(List<int> bytes) {
    return ZWalletdBlockID.deserialize(bytes);
  }
}

class ZWalletdGetBlock extends ZcashProtoMessage
    with
        IZcashProtoQueryMessage<
          cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock
        > {
  /// Return the compact block corresponding to the given block identifier.
  ///
  /// The returned `CompactBlock` includes transaction data for all value
  /// pools, including transparent inputs (`vin`) and outputs (`vout`). This
  /// differs from `GetBlockRange`, which supports filtering by pool type and
  /// defaults to returning only shielded (Sapling, Orchard, and Ironwood)
  /// data. Clients that require only data for specific pools should use
  /// `GetBlockRange` with the appropriate `poolTypes` set.
  ///
  /// Note: the single null-outpoint input for coinbase transactions is
  /// omitted from the `vin` field of the corresponding `CompactTx`. See the
  /// documentation of the `CompactTx` message for details.
  final ZWalletdBlockID? getBlock;

  const ZWalletdGetBlock({this.getBlock});

  @override
  ProtoMessageConfig protoConfig() =>
      getBlock?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getBlock?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetBlock': config.encodeMessage(getBlock)};
  }

  factory ZWalletdGetBlock.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetBlock(
      getBlock: json.valueTo<ZWalletdBlockID?, Object>(
        key: 'GetBlock',
        parse:
            (v) =>
                ZWalletdBlockID.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetBlock;
  @override
  cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock onQueryResponse(
    List<int> bytes,
  ) {
    return cash_z_wallet_sdk_rpc_compact_formats
        .ZWalletdCompactBlock.deserialize(bytes);
  }
}

class ZWalletdGetBlockNullifiers extends ZcashProtoMessage
    with
        IZcashProtoQueryMessage<
          cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock
        > {
  /// Return a compact block containing only nullifier information for the
  /// shielded pools (Sapling spend nullifiers, Orchard action nullifiers, and
  /// Ironwood action nullifiers). Transparent transaction data, Sapling
  /// outputs, full Orchard/Ironwood action data, and commitment tree sizes are
  /// not included.
  ///
  /// Note: this method is deprecated; use `GetBlockRange` with the
  /// appropriate `poolTypes` instead.
  final ZWalletdBlockID? getBlockNullifiers;

  const ZWalletdGetBlockNullifiers({this.getBlockNullifiers});

  @override
  ProtoMessageConfig protoConfig() =>
      getBlockNullifiers?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getBlockNullifiers?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetBlockNullifiers': config.encodeMessage(getBlockNullifiers)};
  }

  factory ZWalletdGetBlockNullifiers.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetBlockNullifiers(
      getBlockNullifiers: json.valueTo<ZWalletdBlockID?, Object>(
        key: 'GetBlockNullifiers',
        parse:
            (v) =>
                ZWalletdBlockID.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetBlockNullifiers;
  @override
  cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock onQueryResponse(
    List<int> bytes,
  ) {
    return cash_z_wallet_sdk_rpc_compact_formats
        .ZWalletdCompactBlock.deserialize(bytes);
  }
}

class ZWalletdGetBlockRange extends ZcashProtoMessage
    with
        IZcashProtoQueryMessage<
          cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock
        > {
  /// Return a list of consecutive compact blocks in the specified range,
  /// which is inclusive of `range.end`.
  ///
  /// If range.start &lt;= range.end, blocks are returned increasing height order;
  /// otherwise blocks are returned in decreasing height order.
  final ZWalletdBlockRange? getBlockRange;

  const ZWalletdGetBlockRange({this.getBlockRange});

  @override
  ProtoMessageConfig protoConfig() =>
      getBlockRange?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getBlockRange?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetBlockRange': config.encodeMessage(getBlockRange)};
  }

  factory ZWalletdGetBlockRange.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetBlockRange(
      getBlockRange: json.valueTo<ZWalletdBlockRange?, Object>(
        key: 'GetBlockRange',
        parse:
            (v) => ZWalletdBlockRange.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetBlockRange;
  @override
  cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock onQueryResponse(
    List<int> bytes,
  ) {
    return cash_z_wallet_sdk_rpc_compact_formats
        .ZWalletdCompactBlock.deserialize(bytes);
  }
}

class ZWalletdGetBlockRangeNullifiers extends ZcashProtoMessage
    with
        IZcashProtoQueryMessage<
          cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock
        > {
  /// Return a stream of compact blocks for the specified range, where each
  /// block contains only nullifier information for the shielded pools
  /// (Sapling spend nullifiers, Orchard action nullifiers, and Ironwood action
  /// nullifiers). Transparent transaction data, Sapling outputs, full
  /// Orchard/Ironwood action data, and commitment tree sizes are not included.
  /// Implementations MUST ignore any
  /// `PoolType::TRANSPARENT` member of the `poolTypes` field of the request.
  ///
  /// Note: this method is deprecated; use `GetBlockRange` with the
  /// appropriate `poolTypes` instead.
  final ZWalletdBlockRange? getBlockRangeNullifiers;

  const ZWalletdGetBlockRangeNullifiers({this.getBlockRangeNullifiers});

  @override
  ProtoMessageConfig protoConfig() =>
      getBlockRangeNullifiers?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getBlockRangeNullifiers?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'GetBlockRangeNullifiers': config.encodeMessage(getBlockRangeNullifiers),
    };
  }

  factory ZWalletdGetBlockRangeNullifiers.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetBlockRangeNullifiers(
      getBlockRangeNullifiers: json.valueTo<ZWalletdBlockRange?, Object>(
        key: 'GetBlockRangeNullifiers',
        parse:
            (v) => ZWalletdBlockRange.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetBlockRangeNullifiers;
  @override
  cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactBlock onQueryResponse(
    List<int> bytes,
  ) {
    return cash_z_wallet_sdk_rpc_compact_formats
        .ZWalletdCompactBlock.deserialize(bytes);
  }
}

class ZWalletdGetTransaction extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdRawTransaction> {
  /// Return the requested full (not compact) transaction (as from zcashd)
  final ZWalletdTxFilter? getTransaction;

  const ZWalletdGetTransaction({this.getTransaction});

  @override
  ProtoMessageConfig protoConfig() =>
      getTransaction?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getTransaction?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetTransaction': config.encodeMessage(getTransaction)};
  }

  factory ZWalletdGetTransaction.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetTransaction(
      getTransaction: json.valueTo<ZWalletdTxFilter?, Object>(
        key: 'GetTransaction',
        parse:
            (v) => ZWalletdTxFilter.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetTransaction;
  @override
  ZWalletdRawTransaction onQueryResponse(List<int> bytes) {
    return ZWalletdRawTransaction.deserialize(bytes);
  }
}

class ZWalletdSendTransaction extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdSendResponse> {
  /// Submit the given transaction to the Zcash network
  final ZWalletdRawTransaction? sendTransaction;

  const ZWalletdSendTransaction({this.sendTransaction});

  @override
  ProtoMessageConfig protoConfig() =>
      sendTransaction?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => sendTransaction?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'SendTransaction': config.encodeMessage(sendTransaction)};
  }

  factory ZWalletdSendTransaction.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdSendTransaction(
      sendTransaction: json.valueTo<ZWalletdRawTransaction?, Object>(
        key: 'SendTransaction',
        parse:
            (v) => ZWalletdRawTransaction.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcSendTransaction;
  @override
  ZWalletdSendResponse onQueryResponse(List<int> bytes) {
    return ZWalletdSendResponse.deserialize(bytes);
  }
}

class ZWalletdGetTaddressTxids extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdRawTransaction> {
  /// Return RawTransactions that match the given transparent address filter.
  ///
  /// Note: This function is misnamed, it returns complete `RawTransaction` values, not TxIds.
  /// NOTE: this method is deprecated, please use GetTaddressTransactions instead.
  final ZWalletdTransparentAddressBlockFilter? getTaddressTxids;

  const ZWalletdGetTaddressTxids({this.getTaddressTxids});

  @override
  ProtoMessageConfig protoConfig() =>
      getTaddressTxids?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getTaddressTxids?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetTaddressTxids': config.encodeMessage(getTaddressTxids)};
  }

  factory ZWalletdGetTaddressTxids.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetTaddressTxids(
      getTaddressTxids: json
          .valueTo<ZWalletdTransparentAddressBlockFilter?, Object>(
            key: 'GetTaddressTxids',
            parse:
                (v) => ZWalletdTransparentAddressBlockFilter.fromJson(
                  JsonParser.valueAs(v),
                  config: config,
                ),
            normalizeKeyLookup: config.normalizeKeys,
          ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetTaddressTxids;
  @override
  ZWalletdRawTransaction onQueryResponse(List<int> bytes) {
    return ZWalletdRawTransaction.deserialize(bytes);
  }
}

class ZWalletdGetTaddressTransactions extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdRawTransaction> {
  /// Return the transactions corresponding to the given t-address within the given block range.
  /// Mempool transactions are not included in the results.
  final ZWalletdTransparentAddressBlockFilter? getTaddressTransactions;

  const ZWalletdGetTaddressTransactions({this.getTaddressTransactions});

  @override
  ProtoMessageConfig protoConfig() =>
      getTaddressTransactions?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getTaddressTransactions?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'GetTaddressTransactions': config.encodeMessage(getTaddressTransactions),
    };
  }

  factory ZWalletdGetTaddressTransactions.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetTaddressTransactions(
      getTaddressTransactions: json
          .valueTo<ZWalletdTransparentAddressBlockFilter?, Object>(
            key: 'GetTaddressTransactions',
            parse:
                (v) => ZWalletdTransparentAddressBlockFilter.fromJson(
                  JsonParser.valueAs(v),
                  config: config,
                ),
            normalizeKeyLookup: config.normalizeKeys,
          ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetTaddressTransactions;
  @override
  ZWalletdRawTransaction onQueryResponse(List<int> bytes) {
    return ZWalletdRawTransaction.deserialize(bytes);
  }
}

class ZWalletdGetTaddressBalance extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdBalance> {
  final ZWalletdAddressList? getTaddressBalance;

  const ZWalletdGetTaddressBalance({this.getTaddressBalance});

  @override
  ProtoMessageConfig protoConfig() =>
      getTaddressBalance?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getTaddressBalance?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetTaddressBalance': config.encodeMessage(getTaddressBalance)};
  }

  factory ZWalletdGetTaddressBalance.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetTaddressBalance(
      getTaddressBalance: json.valueTo<ZWalletdAddressList?, Object>(
        key: 'GetTaddressBalance',
        parse:
            (v) => ZWalletdAddressList.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetTaddressBalance;
  @override
  ZWalletdBalance onQueryResponse(List<int> bytes) {
    return ZWalletdBalance.deserialize(bytes);
  }
}

class ZWalletdGetTaddressBalanceStream extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdBalance> {
  final ZWalletdAddress? getTaddressBalanceStream;

  const ZWalletdGetTaddressBalanceStream({this.getTaddressBalanceStream});

  @override
  ProtoMessageConfig protoConfig() =>
      getTaddressBalanceStream?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getTaddressBalanceStream?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'GetTaddressBalanceStream': config.encodeMessage(
        getTaddressBalanceStream,
      ),
    };
  }

  factory ZWalletdGetTaddressBalanceStream.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetTaddressBalanceStream(
      getTaddressBalanceStream: json.valueTo<ZWalletdAddress?, Object>(
        key: 'GetTaddressBalanceStream',
        parse:
            (v) =>
                ZWalletdAddress.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetTaddressBalanceStream;
  @override
  ZWalletdBalance onQueryResponse(List<int> bytes) {
    return ZWalletdBalance.deserialize(bytes);
  }
}

class ZWalletdGetMempoolTx extends ZcashProtoMessage
    with
        IZcashProtoQueryMessage<
          cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactTx
        > {
  /// Returns a stream of the compact transaction representation for transactions
  /// currently in the mempool. The results of this operation may be a few
  /// seconds out of date. If the `exclude_txid_suffixes` list is empty,
  /// return all transactions; otherwise return all *except* those in the
  /// `exclude_txid_suffixes` list (if any); this allows the client to avoid
  /// receiving transactions that it already has (from an earlier call to this
  /// RPC). The transaction IDs in the `exclude_txid_suffixes` list can be
  /// shortened to any number of bytes to make the request more
  /// bandwidth-efficient; if two or more transactions in the mempool match a
  /// txid suffix, none of the matching transactions are excluded. Txid
  /// suffixes in the exclude list that don't match any transactions in the
  /// mempool are ignored.
  final ZWalletdGetMempoolTxRequest? getMempoolTx;

  const ZWalletdGetMempoolTx({this.getMempoolTx});

  @override
  ProtoMessageConfig protoConfig() =>
      getMempoolTx?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getMempoolTx?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetMempoolTx': config.encodeMessage(getMempoolTx)};
  }

  factory ZWalletdGetMempoolTx.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetMempoolTx(
      getMempoolTx: json.valueTo<ZWalletdGetMempoolTxRequest?, Object>(
        key: 'GetMempoolTx',
        parse:
            (v) => ZWalletdGetMempoolTxRequest.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetMempoolTx;
  @override
  cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactTx onQueryResponse(
    List<int> bytes,
  ) {
    return cash_z_wallet_sdk_rpc_compact_formats.ZWalletdCompactTx.deserialize(
      bytes,
    );
  }
}

class ZWalletdGetMempoolStream extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdRawTransaction> {
  /// Return a stream of current Mempool transactions. This will keep the output stream open while
  /// there are mempool transactions. It will close the returned stream when a new block is mined.
  final ZWalletdEmpty? getMempoolStream;

  const ZWalletdGetMempoolStream({this.getMempoolStream});

  @override
  ProtoMessageConfig protoConfig() =>
      getMempoolStream?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getMempoolStream?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetMempoolStream': config.encodeMessage(getMempoolStream)};
  }

  factory ZWalletdGetMempoolStream.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetMempoolStream(
      getMempoolStream: json.valueTo<ZWalletdEmpty?, Object>(
        key: 'GetMempoolStream',
        parse:
            (v) =>
                ZWalletdEmpty.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetMempoolStream;
  @override
  ZWalletdRawTransaction onQueryResponse(List<int> bytes) {
    return ZWalletdRawTransaction.deserialize(bytes);
  }
}

class ZWalletdGetTreeState extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdTreeState> {
  /// GetTreeState returns the note commitment tree state corresponding to the given block.
  /// See section 3.7 of the Zcash protocol specification. It returns several other useful
  /// values also (even though they can be obtained using GetBlock).
  /// The block can be specified by either height or hash.
  final ZWalletdBlockID? getTreeState;

  const ZWalletdGetTreeState({this.getTreeState});

  @override
  ProtoMessageConfig protoConfig() =>
      getTreeState?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getTreeState?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetTreeState': config.encodeMessage(getTreeState)};
  }

  factory ZWalletdGetTreeState.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetTreeState(
      getTreeState: json.valueTo<ZWalletdBlockID?, Object>(
        key: 'GetTreeState',
        parse:
            (v) =>
                ZWalletdBlockID.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetTreeState;
  @override
  ZWalletdTreeState onQueryResponse(List<int> bytes) {
    return ZWalletdTreeState.deserialize(bytes);
  }
}

class ZWalletdGetLatestTreeState extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdTreeState> {
  final ZWalletdEmpty? getLatestTreeState;

  const ZWalletdGetLatestTreeState({this.getLatestTreeState});

  @override
  ProtoMessageConfig protoConfig() =>
      getLatestTreeState?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getLatestTreeState?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetLatestTreeState': config.encodeMessage(getLatestTreeState)};
  }

  factory ZWalletdGetLatestTreeState.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetLatestTreeState(
      getLatestTreeState: json.valueTo<ZWalletdEmpty?, Object>(
        key: 'GetLatestTreeState',
        parse:
            (v) =>
                ZWalletdEmpty.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetLatestTreeState;
  @override
  ZWalletdTreeState onQueryResponse(List<int> bytes) {
    return ZWalletdTreeState.deserialize(bytes);
  }
}

class ZWalletdGetSubtreeRoots extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdSubtreeRoot> {
  /// Returns a stream of information about roots of subtrees of the note commitment tree
  /// for the specified shielded protocol (Sapling, Orchard, or Ironwood).
  final ZWalletdGetSubtreeRootsArg? getSubtreeRoots;

  const ZWalletdGetSubtreeRoots({this.getSubtreeRoots});

  @override
  ProtoMessageConfig protoConfig() =>
      getSubtreeRoots?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getSubtreeRoots?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetSubtreeRoots': config.encodeMessage(getSubtreeRoots)};
  }

  factory ZWalletdGetSubtreeRoots.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetSubtreeRoots(
      getSubtreeRoots: json.valueTo<ZWalletdGetSubtreeRootsArg?, Object>(
        key: 'GetSubtreeRoots',
        parse:
            (v) => ZWalletdGetSubtreeRootsArg.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetSubtreeRoots;
  @override
  ZWalletdSubtreeRoot onQueryResponse(List<int> bytes) {
    return ZWalletdSubtreeRoot.deserialize(bytes);
  }
}

class ZWalletdGetAddressUtxos extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdGetAddressUtxosReplyList> {
  final ZWalletdGetAddressUtxosArg? getAddressUtxos;

  const ZWalletdGetAddressUtxos({this.getAddressUtxos});

  @override
  ProtoMessageConfig protoConfig() =>
      getAddressUtxos?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getAddressUtxos?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetAddressUtxos': config.encodeMessage(getAddressUtxos)};
  }

  factory ZWalletdGetAddressUtxos.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetAddressUtxos(
      getAddressUtxos: json.valueTo<ZWalletdGetAddressUtxosArg?, Object>(
        key: 'GetAddressUtxos',
        parse:
            (v) => ZWalletdGetAddressUtxosArg.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetAddressUtxos;
  @override
  ZWalletdGetAddressUtxosReplyList onQueryResponse(List<int> bytes) {
    return ZWalletdGetAddressUtxosReplyList.deserialize(bytes);
  }
}

class ZWalletdGetAddressUtxosStream extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdGetAddressUtxosReply> {
  final ZWalletdGetAddressUtxosArg? getAddressUtxosStream;

  const ZWalletdGetAddressUtxosStream({this.getAddressUtxosStream});

  @override
  ProtoMessageConfig protoConfig() =>
      getAddressUtxosStream?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getAddressUtxosStream?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {
      'GetAddressUtxosStream': config.encodeMessage(getAddressUtxosStream),
    };
  }

  factory ZWalletdGetAddressUtxosStream.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetAddressUtxosStream(
      getAddressUtxosStream: json.valueTo<ZWalletdGetAddressUtxosArg?, Object>(
        key: 'GetAddressUtxosStream',
        parse:
            (v) => ZWalletdGetAddressUtxosArg.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetAddressUtxosStream;
  @override
  ZWalletdGetAddressUtxosReply onQueryResponse(List<int> bytes) {
    return ZWalletdGetAddressUtxosReply.deserialize(bytes);
  }
}

class ZWalletdGetLightdInfo extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdLightdInfo> {
  /// Return information about this lightwalletd instance and the blockchain
  final ZWalletdEmpty? getLightdInfo;

  const ZWalletdGetLightdInfo({this.getLightdInfo});

  @override
  ProtoMessageConfig protoConfig() =>
      getLightdInfo?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getLightdInfo?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'GetLightdInfo': config.encodeMessage(getLightdInfo)};
  }

  factory ZWalletdGetLightdInfo.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdGetLightdInfo(
      getLightdInfo: json.valueTo<ZWalletdEmpty?, Object>(
        key: 'GetLightdInfo',
        parse:
            (v) =>
                ZWalletdEmpty.fromJson(JsonParser.valueAs(v), config: config),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcGetLightdInfo;
  @override
  ZWalletdLightdInfo onQueryResponse(List<int> bytes) {
    return ZWalletdLightdInfo.deserialize(bytes);
  }
}

class ZWalletdPing extends ZcashProtoMessage
    with IZcashProtoQueryMessage<ZWalletdPingResponse> {
  /// Testing-only, requires lightwalletd --ping-very-insecure (do not enable in production)
  final ZWalletdDuration? ping;

  const ZWalletdPing({this.ping});

  @override
  ProtoMessageConfig protoConfig() =>
      ping?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => ping?.protoValues ?? [];

  @override
  Map<String, dynamic> toJson({
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return {'Ping': config.encodeMessage(ping)};
  }

  factory ZWalletdPing.fromJson(
    Map<String, dynamic> json, {
    ProtoJsonConfig config = DefaultProtoJsonConfig.defaultConfig,
  }) {
    return ZWalletdPing(
      ping: json.valueTo<ZWalletdDuration?, Object>(
        key: 'Ping',
        parse:
            (v) => ZWalletdDuration.fromJson(
              JsonParser.valueAs(v),
              config: config,
            ),
        normalizeKeyLookup: config.normalizeKeys,
      ),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcPing;
  @override
  ZWalletdPingResponse onQueryResponse(List<int> bytes) {
    return ZWalletdPingResponse.deserialize(bytes);
  }
}
