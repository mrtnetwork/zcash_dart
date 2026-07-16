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
  orchard(3, 'ORCHARD');

  const ZWalletdPoolType(this.value, this.protoName);

  /// The original proto wire value for this enum constant.
  @override
  final int value;

  /// The original proto identifier, e.g. "VOTE_OPTION_UNSPECIFIED".
  @override
  final String protoName;

  /// Looks up a value by its proto wire int. Throws if not found.
  static ZWalletdPoolType fromValue(int? value) {
    return ZWalletdPoolType.values.firstWhere(
      (e) => e.value == value,
      orElse:
          () =>
              throw ItemNotFoundException(
                name: "ZWalletdPoolType",
                value: value,
              ),
    );
  }

  /// Looks up a value by wire int, Dart enum name, or original proto
  /// name (whichever [value] happens to be). Throws if not found.
  static ZWalletdPoolType from(Object? value) {
    return ZWalletdPoolType.values.firstWhere(
      (e) => e.value == value || e.name == value || e.protoName == value,
      orElse:
          () =>
              throw ItemNotFoundException(
                name: "ZWalletdPoolType",
                value: value,
              ),
    );
  }
}

/// orchard commitment tree state
enum ZWalletdShieldedProtocol implements ProtoEnumVariant {
  sapling(0, 'sapling'),
  orchard(1, 'orchard');

  const ZWalletdShieldedProtocol(this.value, this.protoName);

  /// The original proto wire value for this enum constant.
  @override
  final int value;

  /// The original proto identifier, e.g. "VOTE_OPTION_UNSPECIFIED".
  @override
  final String protoName;

  /// Looks up a value by its proto wire int. Throws if not found.
  static ZWalletdShieldedProtocol fromValue(int? value) {
    return ZWalletdShieldedProtocol.values.firstWhere(
      (e) => e.value == value,
      orElse:
          () =>
              throw ItemNotFoundException(
                name: "ZWalletdShieldedProtocol",
                value: value,
              ),
    );
  }

  /// Looks up a value by wire int, Dart enum name, or original proto
  /// name (whichever [value] happens to be). Throws if not found.
  static ZWalletdShieldedProtocol from(Object? value) {
    return ZWalletdShieldedProtocol.values.firstWhere(
      (e) => e.value == value || e.name == value || e.protoName == value,
      orElse:
          () =>
              throw ItemNotFoundException(
                name: "ZWalletdShieldedProtocol",
                value: value,
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
/// behavior of returning only data relevant to the shielded (Sapling and
/// Orchard) pools; otherwise, the server should prune `CompactBlock`s returned
/// to include only data relevant to the requested pool types. Clients MUST
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
/// for the `height` field. See https://github.com/zcash/librustzcash/issues/1484
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
  final int errorCode;

  final String? errorMessage;

  const ZWalletdSendResponse({this.errorCode = 0, this.errorMessage});

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

  factory ZWalletdSendResponse.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdSendResponse(
      errorCode: decode.getInt<int>(1),
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

  final bool taddrSupport;

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
    this.taddrSupport = false,
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

  factory ZWalletdLightdInfo.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdLightdInfo(
      version: decode.getString<String?>(1),
      vendor: decode.getString<String?>(2),
      taddrSupport: decode.getBool<bool>(3),
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
  /// relevant to the shielded (Sapling and Orchard) pools.
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
  final int time;

  /// Unix epoch time when the block was mined
  final String? saplingTree;

  /// sapling commitment tree state
  final String? orchardTree;

  const ZWalletdTreeState({
    this.network,
    this.height,
    this.hash,
    this.time = 0,
    this.saplingTree,
    this.orchardTree,
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
  ];

  factory ZWalletdTreeState.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdTreeState(
      network: decode.getString<String?>(1),
      height: decode.getBigInt<BigInt?>(2),
      hash: decode.getString<String?>(3),
      time: decode.getInt<int>(4),
      saplingTree: decode.getString<String?>(5),
      orchardTree: decode.getString<String?>(6),
    );
  }

  @override
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcTreeState;
}

class ZWalletdGetSubtreeRootsArg extends ZcashProtoMessage {
  final int startIndex;

  /// Index identifying where to start returning subtree roots
  final ZWalletdShieldedProtocol? shieldedProtocol;

  /// Shielded protocol to return subtree roots for
  final int maxEntries;

  const ZWalletdGetSubtreeRootsArg({
    this.startIndex = 0,
    this.shieldedProtocol,
    this.maxEntries = 0,
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

  factory ZWalletdGetSubtreeRootsArg.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetSubtreeRootsArg(
      startIndex: decode.getInt<int>(1),
      shieldedProtocol: decode.getEnum<ZWalletdShieldedProtocol?>(
        2,
        ZWalletdShieldedProtocol.values,
      ),
      maxEntries: decode.getInt<int>(3),
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

  final int maxEntries;

  const ZWalletdGetAddressUtxosArg({
    this.addresses = const [],
    this.startHeight,
    this.maxEntries = 0,
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

  factory ZWalletdGetAddressUtxosArg.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetAddressUtxosArg(
      addresses: decode.getListOrEmpty<String>(1),
      startHeight: decode.getBigInt<BigInt?>(2),
      maxEntries: decode.getInt<int>(3),
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

  final int index;

  final List<int>? script;

  final BigInt? valueZat;

  final BigInt? height;

  const ZWalletdGetAddressUtxosReply({
    this.address,
    this.txid,
    this.index = 0,
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

  factory ZWalletdGetAddressUtxosReply.deserialize(List<int> bytes) {
    final decode = ZcashProtoMessage.decode(bytes, protoConfigStatic());
    return ZWalletdGetAddressUtxosReply(
      address: decode.getString<String?>(6),
      txid: decode.getBytes<List<int>?>(1),
      index: decode.getInt<int>(2),
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
  /// defaults to returning only shielded (Sapling and Orchard) data. Clients
  /// that require only data for specific pools should use `GetBlockRange`
  /// with the appropriate `poolTypes` set.
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
  /// shielded pools (Sapling spend nullifiers and Orchard action nullifiers).
  /// Transparent transaction data, Sapling outputs, full Orchard action data,
  /// and commitment tree sizes are not included.
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
  /// If range.start <= range.end, blocks are returned increasing height order;
  /// otherwise blocks are returned in decreasing height order.
  final ZWalletdBlockRange? getBlockRange;

  const ZWalletdGetBlockRange({this.getBlockRange});

  @override
  ProtoMessageConfig protoConfig() =>
      getBlockRange?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getBlockRange?.protoValues ?? [];

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
  /// (Sapling spend nullifiers and Orchard action nullifiers). Transparent
  /// transaction data, Sapling outputs, full Orchard action data, and
  /// commitment tree sizes are not included. Implementations MUST ignore any
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
  /// for the specified shielded protocol (Sapling or Orchard).
  final ZWalletdGetSubtreeRootsArg? getSubtreeRoots;

  const ZWalletdGetSubtreeRoots({this.getSubtreeRoots});

  @override
  ProtoMessageConfig protoConfig() =>
      getSubtreeRoots?.protoConfig() ?? ProtoMessageConfig();

  @override
  List<Object?> get protoValues => getSubtreeRoots?.protoValues ?? [];

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
  DefaultZcashProtoTypeUrl get declarationId =>
      DefaultZcashProtoTypeUrl.cashZWalletSdkRpcPing;
  @override
  ZWalletdPingResponse onQueryResponse(List<int> bytes) {
    return ZWalletdPingResponse.deserialize(bytes);
  }
}
