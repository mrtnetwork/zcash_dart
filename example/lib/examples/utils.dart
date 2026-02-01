import 'package:http/http.dart' as http;
import 'package:zcash_dart/zcash.dart';
import 'clinet/client.dart'
    if (dart.library.io) 'clinet/grpc_provider_example.dart'
    if (dart.library.js_interop) 'clinet/grpc_web_example.dart';

ZCashWalletdProvider client({
  String url = "testnet.zec.rocks",
  int port = 443,
}) {
  return getClient(port: port, url: url);
}

Future<int> getLatestBlockId(ZCashWalletdProvider provider) async {
  final response = await provider.request(ZWalletdRequestGetLatestBlock());
  assert(response.height != null, "unexpected height response.");
  return response.height!;
}

Future<TransactionData?> getTransaction(
  ZCashWalletdProvider provider,
  ZCashTxId txId,
) async {
  final result = await provider.request(
    ZWalletdRequestGetTransaction(
      WalletdTxFilter(hash: txId.toSerializeBytes()),
    ),
  );
  final data = result.data;
  if (data == null) return null;
  return TransactionData.deserialize(data);
}

Future<List<TransparentUtxoWithOwner>> getAccountUtox(
  ZCashWalletdProvider provider,
  TransparentDerivedAddress address,
) async {
  final pk = ZECPublic.fromBip32(address.publicKey);
  return await provider.request(
    ZWalletdRequestGetAddressUtxosWithAccountOwner([
      TransparentUtxoOwner(
        publicKey: pk,
        address: ZCashTransparentAddress(address.address),
        mode: address.pubKeyMode,
      ),
    ]),
  );
}

Future<List<TransparentUtxoWithOwner>> getAccountsUtxos(
  ZCashWalletdProvider provider,
  List<TransparentDerivedAddress> addressses, {
  int? height,
}) async {
  final accounts = addressses.map((e) {
    final pk = ZECPublic.fromBip32(e.publicKey);
    return TransparentUtxoOwner(
      publicKey: pk,
      address: ZCashTransparentAddress(e.address),
    );
  }).toList();
  return await provider.request(
    ZWalletdRequestGetAddressUtxosWithAccountOwner(accounts),
  );
}

Future<DefaultZCashCryptoContext> getContext({
  bool setSaplingParams = true,
  ZKLibConfig? config,
}) async {
  final lib = await ZKLib.init(
    config ??
        ZKLibConfig(
          linuxLibraryUrl:
              "/home/mrhaydari/dev/packages/zcash_dart/zk/target/release/libzk.so",
          useIsolate: false,
          saplingParamsDownloader: SaplingParamDownloer(),
        ),
  );
  return DefaultZCashCryptoContext.sync(
    enableDartPlonk: false,
    orchardProver: lib,
    orchardVerifier: lib,
    saplingProver: lib,
    saplingVerifier: lib,
  );
}

class SaplingParamDownloer implements ZCashDownloadService {
  const SaplingParamDownloer();
  @override
  Future<List<int>> doRequest(Uri uri, ZCashSaplingParameter type) async {
    final client = http.Client();
    try {
      final response = await client.get(uri);
      assert(response.statusCode == 200);
      return response.bodyBytes;
    } finally {
      client.close();
    }
  }
}

Future<List<ScannedBlock>> getNotes({
  required ZCashWalletdProvider provider,
  required DefaultZCashCryptoContext context,
  required int startHeight,
  required int endHeight,
  bool allEntries = true,
  List<
        ZCashBlockProcessorScanKey<
          OrchardFullViewingKey,
          OrchardIncomingViewingKey
        >
      >
      orchard =
      const [],
  List<
        ZCashBlockProcessorScanKey<
          SaplingFullViewingKey,
          SaplingIncomingViewingKey
        >
      >
      sapling =
      const [],
}) async {
  final scan = DefaultZCashBlockScanner(
    config: ZCashBlockProcessorConfig(
      network: ZCashNetwork.mainnet,
      context: context,
      orchardViewKeys: orchard,
      saplingViewKeys: sapling,
    ),
    provider: provider,
  );
  List<ScannedBlock> scannedBlocks = [];
  List<Nullifier> spendedNullifiers = [];
  await for (final i in scan.scanBlock(startHeight, endHeight)) {
    if (i.txes.any(
      (e) => e.orchardOutputs.isNotEmpty || e.saplingOutputs.isNotEmpty,
    )) {
      if (!allEntries) scannedBlocks.add(i);
    }
    if (allEntries) scannedBlocks.add(i);
    spendedNullifiers.addAll(i.txes.expand((e) => e.orchardSpends));
    spendedNullifiers.addAll(i.txes.expand((e) => e.saplingSpends));
  }
  List<ScannedBlock> blocks = scannedBlocks
      .map(
        (e) => e.copyWith(
          txes: e.txes
              .map(
                (e) => e.copyWith(
                  orchardOutputs: e.orchardOutputs
                      .where((e) => !spendedNullifiers.contains(e.nullifier))
                      .toList(),
                  saplingOutputs: e.saplingOutputs
                      .where((e) => !spendedNullifiers.contains(e.nullifier))
                      .toList(),
                ),
              )
              .where(
                (e) =>
                    e.orchardOutputs.isNotEmpty || e.saplingOutputs.isNotEmpty,
              )
              .toList(),
        ),
      )
      .toList();
  if (!allEntries) {
    blocks = blocks.where((e) => e.txes.isNotEmpty).toList();
  }
  return blocks;
}

class TestAccountInfo {
  final SaplingExpandedSpendingKey saplingSk;
  final OrchardSpendingKey orchardSk;
  final List<SaplingIncomingViewingKey> saplingIvks;
  final List<OrchardIncomingViewingKey> orchardIvks;
  final SaplingDiversifiableFullViewingKey saplingFvk;
  final OrchardFullViewingKey orchardFvk;
  final Bip32Slip10Secp256k1 transparent;
  final Bip32Slip10Secp256k1 transparentSk;
  final UnifiedFullViewingKey ufvk;
  final UnifiedIncomingViewingKey uivk;
  final UnifiedIncomingViewingKey uivkInternal;
  const TestAccountInfo({
    required this.saplingSk,
    required this.orchardSk,
    required this.saplingIvks,
    required this.orchardIvks,
    required this.saplingFvk,
    required this.orchardFvk,
    required this.transparent,
    required this.transparentSk,
    required this.ufvk,
    required this.uivk,
    required this.uivkInternal,
  });
}

TestAccountInfo getTestAccount(
  ZCashCryptoContext context, {
  Bip32KeyIndex? accountIndex,
}) {
  final account = ZCashAccount.fromSeed(
    seedBytes: [
      203,
      99,
      69,
      153,
      125,
      60,
      250,
      137,
      83,
      77,
      188,
      253,
      16,
      75,
      252,
      106,
      166,
      189,
      17,
      108,
      14,
      88,
      26,
      221,
      10,
      69,
      206,
      33,
      141,
      250,
      166,
      83,
      35,
      120,
      16,
      10,
      186,
      81,
      152,
      209,
      38,
      40,
      128,
      136,
      98,
      65,
      121,
      95,
      45,
      64,
      222,
      160,
      90,
      211,
      219,
      219,
      121,
      74,
      217,
      81,
      96,
      239,
      131,
      127,
    ],
    config: ZCashAccountConfig(
      network: ZCashNetwork.testnet,
      transparent: true,
    ),
    context: context,
    accountIndex: accountIndex,
  );
  final sk = account.toUnifiedSpendKey();
  final ufvk = sk.toUnifiedFullViewingKey();
  final uivk = ufvk.toUnifiedIncomingViewingKey(context);
  final uivkInternal = ufvk.toUnifiedIncomingViewingKey(
    context,
    scope: Bip44Changes.chainInt,
  );

  final fvk = ufvk.getOrchard();

  final saplingFvk = ufvk.getSapling();
  final transparentFVK = ufvk.getTransparent();
  final saplingIVKs = [
    saplingFvk.toIvk(Bip44Changes.chainExt),
    saplingFvk.toIvk(Bip44Changes.chainInt),
  ];
  final orchardIvks = [
    fvk.toIvk(scope: Bip44Changes.chainExt, context: context),
    fvk.toIvk(scope: Bip44Changes.chainInt, context: context),
  ];
  return TestAccountInfo(
    saplingSk: sk.sapling.privateKey.sk,
    orchardSk: sk.orchard.privateKey.sk,
    saplingIvks: saplingIVKs,
    orchardIvks: orchardIvks,
    saplingFvk: saplingFvk,
    orchardFvk: fvk,
    transparent: transparentFVK,
    transparentSk: sk.transparent,
    ufvk: ufvk,
    uivk: uivk,
    uivkInternal: uivkInternal,
  );
}
