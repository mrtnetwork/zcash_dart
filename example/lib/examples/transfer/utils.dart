import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/zcash.dart';

Future<int> getLatestBlockId(ZcashWalletdProvider provider) async {
  final response = await provider.request(
    ZcashGrpcRequestMessage(request: ZWalletdGetLatestBlock()),
  );
  return response.height!.asSafeInt;
}

Future<List<TransparentUtxoWithOwner>> getAccountsConfrimedUtxos(
  ZcashWalletdProvider provider,
  List<TransparentDerivedAddress> addressses, {
  int? height,
}) async {
  final accounts =
      addressses.map((e) {
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
    if (height > latestBlockHeight) continue;
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
