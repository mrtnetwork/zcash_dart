import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/zcash.dart';

// import 'package:http/http.dart' as http;
// import 'package:zcash_dart/zcash.dart';
// import 'clinet/client.dart'
//     if (dart.library.io) 'clinet/grpc_provider_example.dart'
//     if (dart.library.js_interop) 'clinet/grpc_web_example.dart';

// ZCashWalletdProvider client({String url = "testnet.zec.rocks", int port = 443}) {
//   return getClient(port: port, url: url);
// }

Future<int> getLatestBlockId(ZcashWalletdProvider provider) async {
  final response = await provider.request(
    ZcashGrpcRequestMessage(request: ZWalletdGetLatestBlock()),
  );
  return response.height!.toIntOrThrow;
}

// Future<TransactionData?> getTransaction(
//   ZCashWalletdProvider provider,
//   ZCashTxId txId,
// ) async {
//   final result = await provider.request(
//     ZWalletdRequestGetTransaction(WalletdTxFilter(hash: txId.toSerializeBytes())),
//   );
//   final data = result.data;
//   if (data == null) return null;
//   return TransactionData.deserialize(data);
// }

// Future<List<TransparentUtxoWithOwner>> getAccountUtox(
//   ZCashWalletdProvider provider,
//   TransparentDerivedAddress address,
// ) async {
//   final pk = ZECPublic.fromBip32(address.publicKey);
//   return await provider.request(
//     ZWalletdRequestGetAddressUtxosWithAccountOwner([
//       TransparentUtxoOwner(
//         publicKey: pk,
//         address: ZCashTransparentAddress(address.address),
//         mode: address.pubKeyMode,
//       ),
//     ]),
//   );
// }

Future<List<TransparentUtxoWithOwner>> getAccountsConfrimedUtxos(
  ZcashWalletdProvider provider,
  List<TransparentDerivedAddress> addressses, {
  int? height,
}) async {
  final accounts = addressses.map((e) {
    final pk = ZECPublic.fromBip32(e.publicKey);
    return TransparentUtxoOwner(
      publicKey: pk,
      address: ZcashTransparentAddress(e.address),
    );
  }).toList();
  final utxos = await provider.request(
    WalletdRequestGetAddressUtxosWithAccountOwner(accounts),
  );
  List<TransparentUtxoWithOwner> confirmedUtxos = [];
  final latestBlockHeight = await getLatestBlockId(provider);
  const int coinBaseRequiredConfirmation = 100;
  for (final utxo in utxos) {
    final height = utxo.utxo.blockHeight;
    if (height == 0) continue;
    final isCoinbase = await detectCoinbase(utxo: utxo, provider: provider);
    if (!isCoinbase) {
      confirmedUtxos.add(utxo);
      continue;
    }
    final totalConfirmation = latestBlockHeight - height;
    if (totalConfirmation >= coinBaseRequiredConfirmation) {
      confirmedUtxos.add(utxo);
    }
  }

  return confirmedUtxos;
}

Future<bool> detectCoinbase({
  required TransparentUtxoWithOwner utxo,
  required ZcashWalletdProvider provider,
}) async {
  final tx = await provider.request(
    ZcashGrpcRequestMessage(
      request: ZWalletdGetTransaction(
        getTransaction: ZWalletdTxFilter(hash: utxo.utxo.txId.hash),
      ),
    ),
  );
  final zcashTx = tx.toTransaction();
  bool isCoinbase =
      zcashTx.transparentBundle?.vin.firstOrNull?.txId.isCoinbase() ?? false;
  return isCoinbase;
}
// // Future<DefaultZCashCryptoContext> getContext({
// //   bool setSaplingParams = true,
// //   ZKLibConfig? config,
// // }) async {
// //   final lib = await ZKLib.init(
// //     config ??
// //         ZKLibConfig(
// //           linuxLibraryUrl:
// //               "/home/mrhaydari/dev/packages/zcash_dart/zk/target/release/libzk.so",
// //           useIsolate: false,
// //           saplingParamsDownloader: SaplingParamDownloer(),
// //         ),
// //   );
// //   return DefaultZCashCryptoContext.sync(
// //     enableDartPlonk: false,
// //     orchardProver: lib,
// //     orchardVerifier: lib,
// //     saplingProver: lib,
// //     saplingVerifier: lib,
// //   );
// // }

// class SaplingParamDownloer implements ZCashDownloadService {
//   const SaplingParamDownloer();
//   @override
//   Future<List<int>> doRequest(Uri uri, ZCashSaplingParameter type) async {
//     final client = http.Client();
//     try {
//       final response = await client.get(uri);
//       assert(response.statusCode == 200);
//       return response.bodyBytes;
//     } finally {
//       client.close();
//     }
//   }
// }

Future<
  ({
    List<ScannedBlock> scannedBlocks,
    List<ScannedOutputWithIvk> outputs,
    List<Nullifier> spendedNullifiers,
  })
>
getNotes({
  required ZcashWalletdProvider provider,
  required ZcashCryptoContext context,
  required int startHeight,
  required int endHeight,
  ZcashNetwork network = ZcashNetwork.regtest,
  List<
        ZcashBlockProcessorScanKey<
          OrchardFullViewingKey,
          OrchardIncomingViewingKey
        >
      >
      orchard =
      const [],
  List<
        ZcashBlockProcessorScanKey<
          SaplingFullViewingKey,
          SaplingIncomingViewingKey
        >
      >
      sapling =
      const [],

  List<Nullifier> accountNullifiers = const [],
}) async {
  final scan = DefaultZcashBlockScanner(
    config: ZcashBlockProcessorConfig(
      network: network,
      context: context,
      orchardViewKeys: orchard,
      saplingViewKeys: sapling,
    ),
    provider: provider,
  );
  List<ScannedBlock> scannedBlocks = [];
  List<Nullifier> spendedNullifiers = [];
  Map<Nullifier, ScannedOutputWithIvk> scannedOutputs = {};
  await for (final block in scan.scanBlock(startHeight, endHeight)) {
    scannedBlocks.add(block);
    for (final tx in block.txes) {
      final accountOuts = tx.scannedOutputs();
      for (final output in accountOuts) {
        final nullifier = output.nullifier;
        assert(nullifier != null);
        scannedOutputs[nullifier!] = output;
      }
    }
    final nullifiers = block.nullifiers();
    for (final nullifier in nullifiers) {
      ScannedOutputWithIvk? remove = scannedOutputs.remove(nullifier);
      if (remove != null || accountNullifiers.contains(nullifier)) {
        spendedNullifiers.add(nullifier);
      }
    }
  }

  return (
    outputs: scannedOutputs.values.toList(),
    scannedBlocks: scannedBlocks,
    spendedNullifiers: spendedNullifiers,
  );
}

// // class TestAccountInfo {
// //   final SaplingExpandedSpendingKey saplingSk;
// //   final OrchardSpendingKey orchardSk;
// //   final List<SaplingIncomingViewingKey> saplingIvks;
// //   final List<OrchardIncomingViewingKey> orchardIvks;
// //   final SaplingDiversifiableFullViewingKey saplingFvk;
// //   final OrchardFullViewingKey orchardFvk;
// //   final Bip32Slip10Secp256k1 transparent;
// //   final Bip32Slip10Secp256k1 transparentSk;
// //   final UnifiedFullViewingKey ufvk;
// //   final UnifiedIncomingViewingKey uivk;
// //   final UnifiedIncomingViewingKey uivkInternal;
// //   const TestAccountInfo({
// //     required this.saplingSk,
// //     required this.orchardSk,
// //     required this.saplingIvks,
// //     required this.orchardIvks,
// //     required this.saplingFvk,
// //     required this.orchardFvk,
// //     required this.transparent,
// //     required this.transparentSk,
// //     required this.ufvk,
// //     required this.uivk,
// //     required this.uivkInternal,
// //   });
// // }

// // TestAccountInfo getTestAccount(
// //   ZCashCryptoContext context, {
// //   Bip32KeyIndex? accountIndex,
// // }) {
// //   final account = ZCashAccount.fromSeed(
// //     seedBytes: [
// //       203,
// //       99,
// //       69,
// //       153,
// //       125,
// //       60,
// //       250,
// //       137,
// //       83,
// //       77,
// //       188,
// //       253,
// //       16,
// //       75,
// //       252,
// //       106,
// //       166,
// //       189,
// //       17,
// //       108,
// //       14,
// //       88,
// //       26,
// //       221,
// //       10,
// //       69,
// //       206,
// //       33,
// //       141,
// //       250,
// //       166,
// //       83,
// //       35,
// //       120,
// //       16,
// //       10,
// //       186,
// //       81,
// //       152,
// //       209,
// //       38,
// //       40,
// //       128,
// //       136,
// //       98,
// //       65,
// //       121,
// //       95,
// //       45,
// //       64,
// //       222,
// //       160,
// //       90,
// //       211,
// //       219,
// //       219,
// //       121,
// //       74,
// //       217,
// //       81,
// //       96,
// //       239,
// //       131,
// //       127,
// //     ],
// //     config: ZCashAccountConfig(network: ZCashNetwork.testnet, transparent: true),
// //     context: context,
// //     accountIndex: accountIndex,
// //   );
// //   final sk = account.toUnifiedSpendKey();
// //   final ufvk = sk.toUnifiedFullViewingKey();
// //   final uivk = ufvk.toUnifiedIncomingViewingKey(context);
// //   final uivkInternal = ufvk.toUnifiedIncomingViewingKey(
// //     context,
// //     scope: Bip44Changes.chainInt,
// //   );

// //   final fvk = ufvk.getOrchard();

// //   final saplingFvk = ufvk.getSapling();
// //   final transparentFVK = ufvk.getTransparent();
// //   final saplingIVKs = [
// //     saplingFvk.toIvk(Bip44Changes.chainExt),
// //     saplingFvk.toIvk(Bip44Changes.chainInt),
// //   ];
// //   final orchardIvks = [
// //     fvk.toIvk(scope: Bip44Changes.chainExt, context: context),
// //     fvk.toIvk(scope: Bip44Changes.chainInt, context: context),
// //   ];
// //   return TestAccountInfo(
// //     saplingSk: sk.sapling.privateKey.sk,
// //     orchardSk: sk.orchard.privateKey.sk,
// //     saplingIvks: saplingIVKs,
// //     orchardIvks: orchardIvks,
// //     saplingFvk: saplingFvk,
// //     orchardFvk: fvk,
// //     transparent: transparentFVK,
// //     transparentSk: sk.transparent,
// //     ufvk: ufvk,
// //     uivk: uivk,
// //     uivkInternal: uivkInternal,
// //   );
// // }
