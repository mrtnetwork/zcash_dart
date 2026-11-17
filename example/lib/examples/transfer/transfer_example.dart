import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';
import 'context.dart';
import 'utils.dart';

/// Entry point for the full transfer example (local regtest via LWD_HOST / LWD_PORT).
/// - Initializes cryptographic context
/// - Creates a walletd provider client
/// - Executes a full Zcash transfer flow
void main() async {
  final host = Platform.environment['LWD_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9067');
  final context = await getContext(libraryPath: zcashRustLibrary());
  final provider = createGrpcClient(url: host, port: port);
  await fullTransferExample(context: context, provider: provider);
}

/// Demonstrates a full Zcash transaction flow:
/// - Collect transparent UTXOs
/// - Scan Sapling & Orchard notes
/// - Build Merkle anchors
/// - Create, prove, sign, and send a transaction
Future<void> fullTransferExample({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
}) async {
  /// Create three test accounts using hardened BIP32 indices
  final accounts = [
    ZcashTestAccount.fromSeed(
      context,
      accountIndex: Bip32KeyIndex.hardenIndex(102),
    ),
    ZcashTestAccount.fromSeed(
      context,
      accountIndex: Bip32KeyIndex.hardenIndex(103),
    ),
    ZcashTestAccount.fromSeed(
      context,
      accountIndex: Bip32KeyIndex.hardenIndex(101),
    ),
  ];

  /// Map transparent addresses to their owning account and BIP44 change path
  final Map<TransparentDerivedAddress, (ZcashTestAccount, Bip44Changes)>
  transparentAccounts = {
    accounts[0].uivk.defaultTransparentAddress(): (
      accounts[0],
      Bip44Changes.chainExt,
    ),
    accounts[1].uivk.defaultTransparentAddress(): (
      accounts[1],
      Bip44Changes.chainExt,
    ),
    accounts[2].uivk.defaultTransparentAddress(): (
      accounts[2],
      Bip44Changes.chainExt,
    ),
  };

  /// Fetch all transparent UTXOs for the known addresses
  final utxos = await getAccountsConfrimedUtxos(
    provider,
    transparentAccounts.keys.toList(),
  );

  /// Resolve the target block height for transaction anchoring
  final target = await getLatestBlockId(provider);

  /// Scan blockchain for Sapling and Orchard notes
  /// using full viewing keys (FVKs) and incoming viewing keys (IVKs)
  final saplingKeys =
      accounts
          .map(
            (e) => ZcashBlockProcessorScanKey(
              fvk: e.saplingFvk.fvk,
              viewKeys:
                  e.saplingIvks
                      .map((e) => IVKWithActivationHeight(ivk: e))
                      .toList(),
            ),
          )
          .toList();
  final orchardKeys =
      accounts
          .map(
            (e) => ZcashBlockProcessorScanKey(
              fvk: e.orchardFvk,
              viewKeys:
                  e.orchardIvks
                      .map((e) => IVKWithActivationHeight(ivk: e))
                      .toList(),
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
  final merkle = NativeMerkleController(context: context, provider: provider);
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
    // The network must match the chain: the consensus branch and the
    // transaction version are derived from (network, targetHeight). Without
    // it the builder defaults to mainnet and picks the wrong branch.
    network: ZcashNetwork.regtest,
  );

  /// Add all transparent UTXOs as transaction inputs
  for (final i in utxos) {
    await builder.addTransparentSpend(TransparentSigningInput(input: i));
  }

  /// Add Sapling spends with their corresponding Merkle paths
  if (outputs.saplingNotes.isNotEmpty) {
    for (final i in outputs.saplingNotes) {
      final noteIvk = mapOutputIvks[i.output]!;
      final fvk =
          accounts
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
      final fvk =
          accounts
              .firstWhere((e) => e.orchardIvks.contains(noteIvk))
              .orchardFvk;

      await builder.addOrchardSpend(
        fvk: fvk,
        note: i.output.note,
        merklePath: i.merklePath,
      );
    }
  }

  /// Ensure we actually have funds to spend
  final total = utxos.fold<BigInt>(
    BigInt.zero,
    (p, c) => p + c.utxo.amount.value,
  );
  assert(total != BigInt.zero);
  if (total == BigInt.zero) return;

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
  // ignore: unused_local_variable
  final fee = await builder.addChange(
    target: TransactionOutputTarget.transparent(
      address: accounts[0].uivkInternal.defaultAddress().address,
    ),
  );

  /// Generate proofs and signatures for Sapling spends.
  ///
  /// The proof generation covers spends *and* outputs, so it has to run even
  /// when there is nothing to spend: this transaction always creates a
  /// Sapling output, and an output without its Groth16 proof cannot be
  /// extracted.
  if (outputs.saplingNotes.isNotEmpty) {
    for (final i in outputs.saplingNotes.indexed) {
      final noteIvk = mapOutputIvks[i.$2.output]!;
      final account = accounts.firstWhere(
        (e) => e.saplingIvks.contains(noteIvk),
      );
      await builder.setSaplingProofGenerationKey(
        index: i.$1,
        expsk: account.saplingSk,
      );
    }
  }
  await builder.proofSapling();

  if (outputs.saplingNotes.isNotEmpty) {
    for (final i in outputs.saplingNotes.indexed) {
      final noteIvk = mapOutputIvks[i.$2.output]!;
      final account = accounts.firstWhere(
        (e) => e.saplingIvks.contains(noteIvk),
      );
      await builder.signSapling(index: i.$1, ask: account.saplingSk.ask);
    }
  }

  /// Generate proofs and signatures for Orchard spends.
  ///
  /// As with Sapling, the proof covers outputs too, so it always runs.
  if (outputs.orchardNotes.isNotEmpty) {
    for (final i in outputs.orchardNotes.indexed) {
      final noteIvk = mapOutputIvks[i.$2.output]!;
      final account = accounts.firstWhere(
        (e) => e.orchardIvks.contains(noteIvk),
      );
      await builder.signOrchard(
        index: i.$1,
        ask: RedPallasSpendPrivateKey.fromSpendingKey(account.orchardSk),
      );
    }
  }
  // Orchard circuit version is chosen by the caller (consensus):
  // 1 = fixed post-NU6.2, 2 = NU6.3 (needs matching disableCrossAddress).
  await builder.proofOrchard();

  /// Sign all transparent inputs
  for (final i in utxos.indexed) {
    final acc = transparentAccounts.entries.firstWhere(
      (e) => e.key.address == i.$2.ownerDetails.address.address,
    );

    final sk = acc.value.$1.transparentSk
        .childKey(Bip32KeyIndex(acc.value.$2.value))
        .childKey(acc.key.bip32Index);

    await builder.signTransparent(
      index: i.$1,
      sk: ZECPrivate.fromBip32(sk.privateKey),
    );
  }

  /// Finalize and broadcast the transaction
  final _ = await builder.extractAndSendTransaction(provider);
}
