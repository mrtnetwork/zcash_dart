// Shared plumbing for the Zcash regtest examples.
//
// Everything runs against a local Zebra regtest node:
//
//   RPC        http://127.0.0.1:18235   (regtest `generatetoaddress` faucet)
//   lightwalletd 127.0.0.1:9073         (wallet gRPC, plaintext)
//
//
// The chain activates NU6.3/Ironwood at height 1000 and NU7 at 1500 (see the
// local zebrad.toml), which matters in three places:
//
//   * transactions must carry the branch id of the current era, so the builder
//     is always given a `LightwalletdBranchActivationProvider` built from the
//     branch lightwalletd reports (the static regtest defaults resolve to the
//     wrong branch);
//   * the Orchard pool no longer permits cross-address transfers, so new funds
//     arrive through the Ironwood pool (Orchard-shaped notes, note version v3);
//   * the branch is re-read after mining, because a run that starts below an
//     activation height and mines past it would otherwise sign for the old era.
//
// Proving runs in Rust through `blockchain_utils`; [ZcashRegtest.connect] loads
// the native library and builds the crypto context. Without it Sapling/Orchard
// proving throws `UnimplementedError`.

import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:grpc/grpc.dart';
import 'package:http/http.dart' as http;
import 'package:zcash_dart/zcash.dart';

/// Zebra JSON-RPC endpoint.
const String zcashZebraRpc = 'http://127.0.0.1:18235';

/// lightwalletd gRPC endpoint (plaintext).
const String zcashLightwalletdHost = '127.0.0.1';
const int zcashLightwalletdPort = 9073;

/// Native library that provides the ZK provers.
///
/// Set `ZCASH_RUST_LIBRARY` (runtime) or `--define=ZCASH_RUST_LIBRARY=...`
/// (compile time); there is no default.
String zcashRustLibrary() {
  const defineLib = String.fromEnvironment('ZCASH_RUST_LIBRARY');
  final envLib = Platform.environment['ZCASH_RUST_LIBRARY'];
  if (envLib != null && envLib.isNotEmpty) return envLib;
  if (defineLib.isNotEmpty) return defineLib;
  throw StateError(
    'Set ZCASH_RUST_LIBRARY to the blockchain_utils native library.',
  );
}

/// Throwaway transparent address for coinbase the examples never spend.
const String throwawayMinerAddress = 'tmRPgoiy6J8gfBJDwbv6xo2twpXhBV3vA7g';

/// Coinbase outputs need this many confirmations before they can be spent.
const int zcashCoinbaseMaturity = 100;

/// Blocks mined to a fresh account before it is considered funded.
const int zcashFundingBlocks = 101;

/// Change outputs need this many confirmations.
const int zcashSpendableAge = 10;

/// Calls a Zebra JSON-RPC method.
Future<dynamic> zcashRpc(
  String method, [
  List<Object?> params = const [],
]) async {
  final response = await http.post(
    Uri.parse(zcashZebraRpc),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': 0,
      'method': method,
      'params': params,
    }),
  );
  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final error = decoded['error'];
  if (error != null) {
    throw StateError('zebra $method failed: $error');
  }
  return decoded['result'];
}

/// A live connection to the regtest node plus the helpers the examples use.
class ZcashRegtest {
  ZcashRegtest._(this.context, this.provider, this._channel, this._client);

  /// Crypto context backed by the Rust provers.
  final ZcashCryptoContext context;

  /// lightwalletd client (Horizon-equivalent for Zcash: notes, utxos, send).
  final ZcashWalletdProvider provider;

  final ClientChannel _channel;
  final http.Client _client;

  /// Consensus branch the node reports, as a protocol.
  ZcashNetworkProtocol _branch = ZcashNetworkProtocol.nu6_3;

  ZcashNetworkProtocol get branch => _branch;

  static Future<ZcashRegtest> connect({
    String libraryPath = '',
    String host = zcashLightwalletdHost,
    int port = zcashLightwalletdPort,
  }) async {
    final path = libraryPath.isEmpty ? zcashRustLibrary() : libraryPath;
    blockchainUtils.setRustApi(libraryPath: path);
    final context = DefaultZcashCryptoContext.sync(
      paramsDownloader: CachedSaplingParams(saplingParamsDir()),
    );
    final client = http.Client();
    final channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    final regtest = ZcashRegtest._(
      context,
      ZcashWalletdProvider(_WalletdClient(channel)),
      channel,
      client,
    );
    await regtest.checkNode();
    return regtest;
  }

  void close() {
    _channel.shutdown();
    _client.close();
  }

  /// Fails early with a readable message when the endpoints are not usable.
  Future<void> checkNode() async {
    final info = await provider.request(
      ZcashGrpcRequestMessage(request: ZWalletdGetLightdInfo()),
    );
    final branch = LightwalletdBranchActivationProvider.tryParseBranchId(
      info.consensusBranchId,
    );
    if (branch == null) {
      throw StateError(
        'lightwalletd reported an unknown consensus branch '
        '"${info.consensusBranchId}"',
      );
    }
    _branch = branch;
  }

  /// Re-reads the consensus branch.
  ///
  /// Mining can move the chain across an activation height (this chain
  /// activates NU6.3 at 1000 and NU7 at 1500), so the branch has to be
  /// refreshed before building: a transaction that carries the branch of the
  /// previous era is rejected with "incorrect consensus branch id".
  Future<ZcashNetworkProtocol> syncBranch() async {
    await checkNode();
    return _branch;
  }

  Future<int> height() async {
    final latest = await provider.request(
      ZcashGrpcRequestMessage(request: ZWalletdGetLatestBlock()),
    );
    return latest.getHeight();
  }

  /// Mines [blocks] coinbase to [address] (regtest `generatetoaddress`).
  Future<void> mine(String address, {int blocks = 1}) async {
    await zcashRpc('generatetoaddress', [blocks, address]);
  }

  /// Mines to the throwaway miner address, growing the chain.
  Future<void> mineEmpty({int blocks = 1}) async {
    final info = await zcashRpc('getblockchaininfo') as Map<String, dynamic>;
    final tip = info['blocks'] as int;
    await zcashRpc('generatetoaddress', [blocks, _throwawayFor(tip)]);
  }

  /// Builds, proves, signs and submits [builder], then mines [confirmations]
  /// blocks so the result is spendable.
  Future<ZcashTxId> send(
    TransactionBuilder builder, {
    int confirmations = zcashSpendableAge + 2,
  }) async {
    await syncBranch();
    final txid = await builder.extractAndSendTransaction(provider);
    await mine(_throwawayFor(await height()), blocks: confirmations);
    return txid;
  }
}

/// Deterministic account for [index].
class ZcashExampleAccount {
  const ZcashExampleAccount._({
    required this.usk,
    required this.uivk,
    required this.uivkInternal,
    required this.ufvk,
    required this.saplingFvk,
    required this.orchardFvk,
    required this.saplingSk,
    required this.orchardSk,
    required this.transparentSk,
    required this.transparent,
  });

  /// Account at ZIP-32 index `0 | change`.
  final UnifiedIncomingViewingKey uivk;
  final UnifiedIncomingViewingKey uivkInternal;
  final UnifiedFullViewingKey ufvk;
  final UnifiedSpendingKey usk;
  final SaplingDiversifiableFullViewingKey saplingFvk;
  final OrchardFullViewingKey orchardFvk;
  final SaplingExpandedSpendingKey saplingSk;
  final OrchardSpendingKey orchardSk;

  /// Transparent (secp256k1) account key at the external change level.
  final Bip32Slip10Secp256k1 transparent;
  final Bip32Slip10Secp256k1 transparentSk;

  /// Full viewing key used by the scanner (the diversifiable wrapper carries
  /// the same key material plus the diversifier index).
  SaplingFullViewingKey get saplingFvkFull => saplingFvk.fvk;

  List<SaplingIncomingViewingKey> get saplingIvks => [
    saplingFvk.toIvk(Bip44Changes.chainExt, context: _context!),
    saplingFvk.toIvk(Bip44Changes.chainInt, context: _context!),
  ];

  List<OrchardIncomingViewingKey> get orchardIvks => [
    orchardFvk.toIvk(Bip44Changes.chainExt, context: _context!),
    orchardFvk.toIvk(Bip44Changes.chainInt, context: _context!),
  ];

  static ZcashCryptoContext? _context;

  /// Transparent address of the external chain (`m/44'/133'/<account>'/0`).
  TransparentDerivedAddress get transparentAddress =>
      uivk.defaultTransparentAddress();

  /// Transparent change address (`m/44'/133'/<account>'/1`).
  TransparentDerivedAddress get transparentChangeAddress =>
      uivkInternal.defaultTransparentAddress();

  /// Sapling-only unified address (a `uregtest1…` address with just Sapling).
  String get saplingAddress =>
      ZcashUnifiedAddress.fromReceivers(
        receivers: [uivk.defaultAddress().sapling!],
        network: ZcashNetwork.regtest,
      ).address;

  /// Orchard-only unified address.
  String get orchardAddress =>
      ZcashUnifiedAddress.fromReceivers(
        receivers: [uivk.defaultAddress().orchard!],
        network: ZcashNetwork.regtest,
      ).address;

  /// Full unified address (all receivers the key can produce).
  String get unifiedAddress => uivk.defaultAddress().address;

  factory ZcashExampleAccount.fromSeed(
    ZcashCryptoContext context, {
    required int index,
    List<int>? seed,
  }) {
    _context = context;
    final account = ZcashAccount.fromSeed(
      seedBytes: seed ?? _seedFor(index),
      config: ZcashAccountConfig(
        network: ZcashNetwork.regtest,
        transparent: true,
      ),
      context: context,
      accountIndex: Bip32KeyIndex.hardenIndex(index),
    );
    final usk = account.toUnifiedSpendKey();
    final ufvk = usk.toUnifiedFullViewingKey();
    return ZcashExampleAccount._(
      usk: usk,
      ufvk: ufvk,
      uivk: ufvk.toUnifiedIncomingViewingKey(context),
      uivkInternal: ufvk.toUnifiedIncomingViewingKey(
        context,
        scope: Bip44Changes.chainInt,
      ),
      saplingFvk: ufvk.getSapling(),
      orchardFvk: ufvk.getOrchard(),
      saplingSk: usk.sapling.privateKey.sk,
      orchardSk: usk.orchard.privateKey.sk,
      transparent: ufvk.getTransparent(),
      transparentSk: usk.transparent,
    );
  }

  /// `sha256("zcash_dart/example", index)` — the same index always gives the
  /// same account, so reruns inherit state.
  static List<int> _seedFor(int index) {
    return QuickCrypto.sha256Hash([
      ...'zcash_dart/example'.codeUnits,
      ...utf8.encode(':$index'),
    ]);
  }
}

/// Makes sure [account] holds at least [minZec] in confirmed transparent
/// funds, mining coinbase when it does not.
///
/// Mining always pays a fresh coinbase output, so this works whether the
/// account is empty or only holds an immature (or dusty) one. Only mines when
/// the balance is short, which keeps repeated runs from piling up coinbase.
Future<void> ensureTransparent(
  ZcashRegtest net,
  ZcashExampleAccount account, {
  double minZec = 0.01,
}) async {
  final address = account.transparentAddress;
  final utxos = await confirmedUtxos(net, [address]);
  final total = utxos.fold<BigInt>(
    BigInt.zero,
    (p, c) => p + c.utxo.amount.value,
  );
  final wanted = BigInt.from((minZec * 1e8).round());
  if (total >= wanted) return;
  await net.mine(address.address, blocks: zcashFundingBlocks);
}

/// Picks the fewest, largest utxos that cover [minZec].
///
/// Spending every available utxo would make the fee grow with the number of
/// inputs, which matters when the account holds a lot of small change.
List<TransparentUtxoWithOwner> selectUtxos(
  List<TransparentUtxoWithOwner> utxos, {
  required double minZec,
}) {
  final sorted = [...utxos]
    ..sort((a, b) => b.utxo.amount.value.compareTo(a.utxo.amount.value));
  final wanted = BigInt.from((minZec * 1e8).round());
  final selected = <TransparentUtxoWithOwner>[];
  var total = BigInt.zero;
  for (final utxo in sorted) {
    selected.add(utxo);
    total += utxo.utxo.amount.value;
    if (total >= wanted) break;
  }
  return selected;
}

/// All spendable transparent utxos of [addresses], with coinbase maturity and
/// spendable age applied.
Future<List<TransparentUtxoWithOwner>> confirmedUtxos(
  ZcashRegtest net,
  List<TransparentDerivedAddress> addresses, {
  int requiredConfirmations = zcashSpendableAge,
}) async {
  final owners =
      addresses
          .map(
            (e) => TransparentUtxoOwner(
              publicKey: ZECPublic.fromBip32(e.publicKey),
              address: ZcashTransparentAddress(e.address),
            ),
          )
          .toList();
  final utxos = await net.provider.request(
    WalletdRequestGetAddressUtxosWithAccountOwner(owners),
  );
  final tip = await net.height();
  final result = <TransparentUtxoWithOwner>[];
  for (final utxo in utxos) {
    final height = utxo.utxo.blockHeight;
    if (height <= 0 || height > tip) continue;
    final confirmations = tip - height;
    final coinbase = await isCoinbase(net, utxo);
    final needed = coinbase ? zcashCoinbaseMaturity : requiredConfirmations;
    if (confirmations >= needed) result.add(utxo);
  }
  return result;
}

/// Whether [utxo] is a coinbase output.
Future<bool> isCoinbase(ZcashRegtest net, TransparentUtxoWithOwner utxo) async {
  final tx = await net.provider.request(
    ZcashGrpcRequestMessage(
      request: ZWalletdGetTransaction(
        getTransaction: ZWalletdTxFilter(hash: utxo.utxo.txId.hash),
      ),
    ),
  );
  final decoded = tx.toTransaction();
  return decoded.transparentBundle?.vin.firstOrNull?.txId.isCoinbase() ?? false;
}

/// What [scanNotes] found.
class ZcashNotes {
  const ZcashNotes({
    required this.blocks,
    required this.outputs,
    required this.spendable,
    required this.spent,
  });

  /// Every scanned block, in order — what the Merkle builder consumes.
  final List<ScannedBlock> blocks;

  /// Every note this wallet can see, both pools.
  final List<ScannedOutputWithIvk> outputs;

  /// Notes whose nullifier never appears on the chain — the spendable set.
  final List<ScannedOutputWithIvk> spendable;

  /// Nullifiers seen on the chain that belong to this wallet.
  final List<Nullifier> spent;

  List<SaplingScannedOutput> get sapling =>
      spendable.map((e) => e.output).whereType<SaplingScannedOutput>().toList();

  List<OrchardScannedOutput> get orchard =>
      spendable.map((e) => e.output).whereType<OrchardScannedOutput>().toList();

  /// Shielded value per pool, in zatoshi.
  BigInt get saplingTotal =>
      sapling.fold<BigInt>(BigInt.zero, (p, c) => p + c.note.value.value);

  BigInt get orchardTotal =>
      orchard.fold<BigInt>(BigInt.zero, (p, c) => p + c.note.value.value);

  BigInt total() => spendable.fold<BigInt>(
    BigInt.zero,
    (p, c) => p + c.output.note.value.value,
  );
}

/// Scans the chain for [account]'s notes.
///
/// This is the wallet's "getNotes": trial-decryption with the account's
/// incoming viewing keys over every block from [startHeight] to the tip.
Future<ZcashNotes> scanNotes(
  ZcashRegtest net,
  ZcashExampleAccount account, {
  int startHeight = 1,
  int? endHeight,
}) async {
  final tip = endHeight ?? await net.height();
  final scanner = DefaultZcashBlockScanner(
    config: ZcashBlockProcessorConfig(
      network: ZcashNetwork.regtest,
      context: net.context,
      activationProvider: LightwalletdBranchActivationProvider(net.branch),
      saplingViewKeys: [
        ZcashBlockProcessorScanKey(
          fvk: account.saplingFvkFull,
          viewKeys:
              account.saplingIvks
                  .map((e) => IVKWithActivationHeight(ivk: e))
                  .toList(),
        ),
      ],
      orchardViewKeys: [
        ZcashBlockProcessorScanKey(
          fvk: account.orchardFvk,
          viewKeys:
              account.orchardIvks
                  .map((e) => IVKWithActivationHeight(ivk: e))
                  .toList(),
        ),
      ],
    ),
    provider: net.provider,
  );
  final blocks = <ScannedBlock>[];
  final outputs = <ScannedOutputWithIvk>[];
  final spentNullifiers = <Nullifier>{};
  await for (final block in scanner.scanBlock(startHeight, tip)) {
    blocks.add(block);
    for (final tx in block.txes) {
      outputs.addAll(tx.scannedOutputs());
    }
    spentNullifiers.addAll(block.nullifiers());
  }

  /// A note whose nullifier was published has been spent; drop it so callers
  /// only see what the wallet actually controls.
  final spent = <Nullifier>[];
  final spendable = <ScannedOutputWithIvk>[];
  for (final output in outputs) {
    final nullifier = output.nullifier;
    if (nullifier == null) {
      spendable.add(output);
      continue;
    }
    if (spentNullifiers.contains(nullifier)) {
      spent.add(nullifier);
    } else {
      spendable.add(output);
    }
  }

  return ZcashNotes(
    blocks: blocks,
    outputs: outputs,
    spendable: spendable,
    spent: spent,
  );
}

/// Builds the Merkle state for [notes] with the native (Rust) builder.
///
/// [NativeMerkleController] keeps no Dart shard trees: the Rust backend owns
/// the note-commitment tree, and the controller persists its own state. The
/// witnesses it returns are what a shielded spend needs.
Future<NativeMerkleController> merkleState(ZcashRegtest net) {
  return Future.value(
    NativeMerkleController(context: net.context, provider: net.provider),
  );
}

/// Feeds [notes] into [merkle] and returns the anchors and witnesses.
///
/// Only the requested pools are witnessed: an Orchard-pool witness and an
/// Ironwood-pool witness for the same note are different trees, so asking for
/// both at once would fail the anchor check.
Future<BuildMerleOutput> buildMerkle(
  NativeMerkleController merkle,
  ZcashNotes notes, {
  required int targetHeight,
  bool sapling = false,
  bool orchard = false,
  bool ironwood = false,
}) async {
  await merkle.updateState(notes.blocks);
  return merkle.buildMerkle(
    saplingOutputs: sapling ? notes.sapling : const [],
    orchardOutputs: orchard ? notes.orchard : const [],
    ironwoodOutputs: ironwood ? notes.orchard : const [],
    targetHeight: targetHeight,
  );
}

/// Formats a zatoshi amount as a ZEC string.
String formatZec(BigInt zatoshi) {
  final negative = zatoshi.isNegative;
  final value = negative ? -zatoshi : zatoshi;
  final whole = value ~/ BigInt.from(100000000);
  final fraction = (value % BigInt.from(100000000)).toString().padLeft(8, '0');
  return '${negative ? '-' : ''}$whole.$fraction';
}

/// Formats a [ZAmount].
String formatAmount(ZAmount amount) => formatZec(amount.value);

/// Prints a two-column `name : value` line.
String field(String name, String value) {
  return '  ${name.padRight(22)} $value';
}

/// Thrown when the node or the wallet endpoint is unusable.
class ZcashRegtestError extends Error {
  ZcashRegtestError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Throwaway transparent address used as the coinbase target when a helper
/// needs to mine without a wallet address at hand. Same address as
/// `zebrad.toml`'s `miner_address`.
String _throwawayFor(int height) {
  return _throwawayCache ??= _deriveThrowaway();
}

String? _throwawayCache;

String _deriveThrowaway() => throwawayMinerAddress;

/// Minimal gRPC client: routes raw bytes by method name.
class _WalletdClient extends Client with ZcashWalletdServiceProvider {
  _WalletdClient(super.channel);

  static ClientMethod<ZcashWalletdRequestDetails, List<int>> _method(
    ZcashWalletdRequestDetails params,
  ) {
    return ClientMethod<ZcashWalletdRequestDetails, List<int>>(
      params.method(),
      (value) => value.toBuffer(),
      (value) => value,
    );
  }

  @override
  Future<List<int>> doGrpcRequest(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  }) async {
    return $createUnaryCall(_method(params), params);
  }

  @override
  Stream<List<int>> doGrpcRequestStream(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  }) {
    return $createStreamingCall(_method(params), () async* {
      yield params;
    }());
  }

  @override
  Future<Stream<List<int>>> doGrpcRequestStreamAsync(
    ZcashWalletdRequestDetails params, {
    Duration? timeout,
  }) async {
    return doGrpcRequestStream(params);
  }
}

/// Directory the Sapling proving parameters are cached in.
///
/// Defaults to `.dart_tool/sapling_params` inside the example package
/// (gitignored). Override with the `ZCASH_PARAMS_DIR` environment variable
/// (runtime) or `--define=ZCASH_PARAMS_DIR=...` (compile time).
String saplingParamsDir() {
  const defineDir = String.fromEnvironment(
    'ZCASH_PARAMS_DIR',
    defaultValue: '',
  );
  return Platform.environment['ZCASH_PARAMS_DIR'] ??
      (defineDir.isNotEmpty ? defineDir : '.dart_tool/sapling_params');
}

/// Downloads the Sapling proving parameters once, then serves them from disk.
///
/// The proving parameters are large (`sapling-spend.params` is 47.9 MB,
/// `sapling-output.params` 3.5 MB) and `SaplingParamFetcher` has no cache of
/// its own: without this the library re-downloads both on every process start,
/// and once per proving call inside a process. The file name is the last path
/// segment of the download URL, so the cache matches what the fetcher asks for.
class CachedSaplingParams with ZcashDownloadService {
  const CachedSaplingParams(this.directory);

  /// Where the parameters are kept.
  final String directory;

  @override
  Future<List<int>> doRequest(Uri uri, ZcashSaplingParameter type) async {
    final file = File('$directory/${uri.pathSegments.last}');
    if (await file.exists()) {
      final cached = await file.readAsBytes();
      if (cached.isNotEmpty) return cached;
    }
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw StateError('failed to download $uri: ${response.statusCode}');
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes);
    return response.bodyBytes;
  }
}

/// Downloads the Sapling proving parameters into the cache up front.
///
/// A shielded example calls this before its first proof so the one-time
/// download does not happen in the middle of building a transaction. Later
/// calls are served from the cache and cost nothing.
///
/// [spend] adds `sapling-spend.params` (47.9 MB), which only a Sapling spend
/// needs; Ironwood proving does not use it.
Future<void> warmSaplingParams({bool spend = true}) async {
  final downloader = CachedSaplingParams(saplingParamsDir());
  final types =
      spend ? ZcashSaplingParameter.values : [ZcashSaplingParameter.output];
  for (final type in types) {
    await SaplingParamFetcher.getAndValidate(
      type: type,
      downloadService: downloader,
    );
  }
}
