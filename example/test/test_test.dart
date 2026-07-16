// ignore_for_file: avoid_print

import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:example/main_.dart';
import 'package:zcash_dart/zcash.dart';

/// Entry point for the full transfer example.
/// - Initializes cryptographic context
/// - Creates a walletd provider client
/// - Executes a full Zcash transfer flow
void main() async {
  final zklib = await ZKLib.init(
    ZKLibConfig(
      libUri: "libzk.so",

      /// sapling params downloader
      saplingParamsDownloader: SaplingLocalParamDownloer(),
      saplingSpendParamsFileUri: "path_to_sapling_spend_params",
      saplingOutputParamsFileUri: "path_to_sapling_output_params",
    ),
  );
  final context = await getContext(lib: zklib);

  final provider = createGrpcClient(url: "localhost", port: 9067);
  await fullTransferExample(lib: zklib, context: context, provider: provider);
}

/// Demonstrates a full Zcash transaction flow:
/// - Collect transparent UTXOs
/// - Scan Sapling & Orchard notes
/// - Build Merkle anchors
/// - Create, prove, sign, and send a transaction
Future<void> fullTransferExample({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZKLib lib,
}) async {
  /// Create three test accounts using hardened BIP32 indices
  final accounts = [
    ZcashTestAccount.fromSeed(context, accountIndex: Bip32KeyIndex.hardenIndex(102)),
    ZcashTestAccount.fromSeed(context, accountIndex: Bip32KeyIndex.hardenIndex(103)),
    ZcashTestAccount.fromSeed(context, accountIndex: Bip32KeyIndex.hardenIndex(101)),
  ];

  /// Map transparent addresses to their owning account and BIP44 change path
  final Map<TransparentDerivedAddress, (ZcashTestAccount, Bip44Changes)>
  transparentAccounts = {
    accounts[0].uivk.defaultTransparentAddress(): (accounts[0], Bip44Changes.chainExt),
    accounts[1].uivk.defaultTransparentAddress(): (accounts[1], Bip44Changes.chainExt),
    accounts[2].uivk.defaultAddress().transparent!: (accounts[2], Bip44Changes.chainExt),
  };

  /// Fetch all transparent UTXOs for the known addresses
  final utxos = await getAccountsConfrimedUtxos(
    provider,
    transparentAccounts.keys.toList(),
  );
  // print("utxos ${utxos.length}");
  // return;

  /// Resolve the target block height for transaction anchoring
  final target = await getLatestBlockId(provider);

  /// Scan blockchain for Sapling and Orchard notes
  /// using full viewing keys (FVKs) and incoming viewing keys (IVKs)
  final saplingKeys = accounts
      .map(
        (e) => ZcashBlockProcessorScanKey(
          fvk: e.saplingFvk.fvk,
          viewKeys: e.saplingIvks.map((e) => IVKWithActivationHeight(ivk: e)).toList(),
        ),
      )
      .toList();
  final orchardKeys = accounts
      .map(
        (e) => ZcashBlockProcessorScanKey(
          fvk: e.orchardFvk,
          viewKeys: e.orchardIvks.map((e) => IVKWithActivationHeight(ivk: e)).toList(),
        ),
      )
      .toList();
  final myNotes = await getNotes(
    provider: provider,
    context: context,
    startHeight: 1,
    sapling: saplingKeys,
    orchard: orchardKeys,
    endHeight: target,
  );
  final Map<ScannedOutput, IncomingViewingKey> mapOutputIvks = {};

  for (final output in myNotes.outputs) {
    mapOutputIvks[output.output] = output.ivk;
  }
  List<ScannedOutput<Note>> scannedOutput = mapOutputIvks.keys.toList();

  /// Extract all Orchard and Sapling outputs from scanned transactions
  final orchards = scannedOutput.whereType<OrchardScannedOutput>().toList();
  final saplings = scannedOutput.whereType<SaplingScannedOutput>().toList();

  /// Build Merkle trees and anchors for Sapling and Orchard
  final merkle = NativeMerkleController(
    context: context,
    provider: provider,
    liberary: lib,
  );
  await merkle.updateState(myNotes.scannedBlocks);

  final outputs = await merkle.buildMerkle(
    orchardOutputs: orchards,
    saplingOutputs: saplings,
    targetHeight: target,
  );

  /// Initialize transaction builder with Sapling and Orchard anchors
  final builder = TransactionBuilder(
    targetHeight: target,
    config: TransactionBuildConfigStandard(
      orchard: outputs.orchardAnchor,
      sapling: outputs.saplingAnchor,
    ),
    context: context,
  );

  /// Add all transparent UTXOs as transaction inputs
  for (final i in utxos) {
    await builder.addTransparentSpend(TransparentSigningInput(input: i));
  }

  /// Add Sapling spends with their corresponding Merkle paths
  if (outputs.saplingNotes.isNotEmpty) {
    for (final i in outputs.saplingNotes) {
      final noteIvk = mapOutputIvks[i.output]!;
      final fvk = accounts
          .firstWhere((e) => e.saplingIvks.contains(noteIvk))
          .saplingFvk
          .fvk;

      await builder.addSaplingSpend(
        fvk: fvk,
        note: i.output.note,
        merklePath: i.merklePath,
      );
    }
  }

  /// Add Orchard spends with their corresponding Merkle paths
  if (outputs.orchardNotes.isNotEmpty) {
    for (final i in outputs.orchardNotes) {
      final noteIvk = mapOutputIvks[i.output]!;
      final fvk = accounts.firstWhere((e) => e.orchardIvks.contains(noteIvk)).orchardFvk;

      await builder.addOrchardSpend(
        fvk: fvk,
        note: i.output.note,
        merklePath: i.merklePath,
      );
    }
  }

  /// Ensure we actually have funds to spend
  final total = utxos.fold<BigInt>(BigInt.zero, (p, c) => p + c.utxo.amount.value);
  assert(total != BigInt.zero);
  if (total == BigInt.zero) return;
  print("total utxos amount: $total");

  /// Add three transparent outputs
  await builder.addOutput(
    target: TransactionOutputTarget.transparent(
      address: accounts[0].uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    target: TransactionOutputTarget.orchard(
      address: accounts[1].uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    target: TransactionOutputTarget.sapling(
      address: accounts[2].uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );

  /// Add transparent change output (fee is calculated internally)
  final fee = await builder.addChange(
    target: TransactionOutputTarget.transparent(
      address: accounts[0].uivkInternal.defaultAddress().address,
    ),
  );
  print("transaction fee $fee");

  /// Generate proofs and signatures for Sapling spends
  if (outputs.saplingNotes.isNotEmpty) {
    for (final i in outputs.saplingNotes.indexed) {
      final noteIvk = mapOutputIvks[i.$2.output]!;
      final account = accounts.firstWhere((e) => e.saplingIvks.contains(noteIvk));
      await builder.setSaplingProofGenerationKey(index: i.$1, expsk: account.saplingSk);
    }
  }
  await builder.proofSapling();

  for (final i in outputs.saplingNotes.indexed) {
    final noteIvk = mapOutputIvks[i.$2.output]!;
    final account = accounts.firstWhere((e) => e.saplingIvks.contains(noteIvk));
    await builder.signSapling(index: i.$1, ask: account.saplingSk.ask);
  }

  /// Generate proofs and signatures for Orchard spends
  if (outputs.orchardNotes.isNotEmpty) {
    for (final i in outputs.orchardNotes.indexed) {
      final noteIvk = mapOutputIvks[i.$2.output]!;
      final account = accounts.firstWhere((e) => e.orchardIvks.contains(noteIvk));
      await builder.signOrchard(
        index: i.$1,
        ask: OrchardSpendAuthorizingKey.fromSpendingKey(account.orchardSk),
      );
    }
  }
  await builder.proofOrchard();

  /// Sign all transparent inputs
  for (final i in utxos.indexed) {
    final acc = transparentAccounts.entries.firstWhere(
      (e) => e.key.address == i.$2.ownerDetails.address.address,
    );

    final sk = acc.value.$1.transparentSk
        .childKey(Bip32KeyIndex(acc.value.$2.value))
        .childKey(acc.key.bip32Index);

    await builder.signTransparent(index: i.$1, sk: ZECPrivate.fromBip32(sk.privateKey));
  }

  /// Finalize and broadcast the transaction
  final txId = await builder.extractAndSendTransaction(provider);
  print("tx $txId");
}
