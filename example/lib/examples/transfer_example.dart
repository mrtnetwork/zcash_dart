// ignore_for_file: unused_local_variable

import 'package:zcash_dart/zcash.dart';
import 'utils.dart';

/// Entry point for the full transfer example.
/// - Initializes cryptographic context
/// - Creates a walletd provider client
/// - Executes a full Zcash transfer flow
void main() async {
  final context = await getContext();
  final provider = client(url: "...", port: 443);
  await fullTransferExample(context, provider);
}

/// Demonstrates a full Zcash transaction flow:
/// - Collect transparent UTXOs
/// - Scan Sapling & Orchard notes
/// - Build Merkle anchors
/// - Create, prove, sign, and send a transaction
Future<void> fullTransferExample(
  DefaultZCashCryptoContext context,
  ZCashWalletdProvider provider,
) async {
  /// Create three test accounts using hardened BIP32 indices
  final accounts = [
    getTestAccount(context, accountIndex: Bip32KeyIndex.hardenIndex(102)),
    getTestAccount(context, accountIndex: Bip32KeyIndex.hardenIndex(103)),
    getTestAccount(context, accountIndex: Bip32KeyIndex.hardenIndex(101)),
  ];

  /// Map transparent addresses to their owning account and BIP44 change path
  final Map<TransparentDerivedAddress, (TestAccountInfo, Bip44Changes)>
  transparentAccounts = {
    accounts[0].uivk.defaultTransparentAddress(): (
      accounts[0],
      Bip44Changes.chainExt,
    ),
    accounts[1].uivk.defaultTransparentAddress(): (
      accounts[1],
      Bip44Changes.chainExt,
    ),
    accounts[2].uivk.defaultAddress().transparent!: (
      accounts[2],
      Bip44Changes.chainExt,
    ),
  };

  /// Fetch all transparent UTXOs for the known addresses
  final utxos = await getAccountsUtxos(
    provider,
    transparentAccounts.keys.toList(),
  );

  /// Resolve the target block height for transaction anchoring
  final target = await getLatestBlockId(provider);

  /// Scan blockchain for Sapling and Orchard notes
  /// using full viewing keys (FVKs) and incoming viewing keys (IVKs)
  final myNotes = await getNotes(
    provider: provider,
    context: context,
    startHeight: 3806348,
    sapling: accounts
        .map(
          (e) => ZCashBlockProcessorScanKey(
            fvk: e.saplingFvk.fvk,
            viewKeys: e.saplingIvks,
          ),
        )
        .toList(),
    orchard: accounts
        .map(
          (e) => ZCashBlockProcessorScanKey(
            fvk: e.orchardFvk,
            viewKeys: e.orchardIvks,
          ),
        )
        .toList(),
    endHeight: target,
  );

  /// Extract all Orchard and Sapling outputs from scanned transactions
  final orchards = myNotes
      .expand((e) => e.txes.expand((e) => e.orchardOutputs))
      .toList();
  final saplings = myNotes
      .expand((e) => e.txes.expand((e) => e.saplingOutputs))
      .toList();

  /// Build Merkle trees and anchors for Sapling and Orchard
  final merkle = DefaultMerkleBuilder(context: context, provider: provider);
  await merkle.updateState(myNotes);

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
    await builder.addTransparentSpend(i);
  }

  /// Add Sapling spends with their corresponding Merkle paths
  if (outputs.saplingNotes.isNotEmpty) {
    for (final i in outputs.saplingNotes) {
      final fvk = accounts
          .firstWhere((e) => e.saplingIvks.contains(i.output.account))
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
      final fvk = accounts
          .firstWhere((e) => e.orchardIvks.contains(i.output.account))
          .orchardFvk;

      await builder.addOrchardSpend(
        fvk: fvk,
        note: i.output.note,
        merklePath: i.merklePath,
      );
    }
  }

  /// Ensure we actually have funds to spend
  final total = utxos.fold<BigInt>(BigInt.zero, (p, c) => p + c.utxo.value);
  assert(total != BigInt.zero);
  if (total == BigInt.zero) return;

  /// Add three transparent outputs
  await builder.addOutput(
    traget: TransactionOutputTarget.transparent(
      address: accounts[0].uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    traget: TransactionOutputTarget.orchard(
      address: accounts[1].uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    traget: TransactionOutputTarget.sapling(
      address: accounts[2].uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );

  /// Add transparent change output (fee is calculated internally)
  final fee = await builder.addChange(
    traget: TransactionOutputTarget.transparent(
      address: accounts[0].uivkInternal.defaultAddress().address,
    ),
  );

  /// Generate proofs and signatures for Sapling spends
  if (outputs.saplingNotes.isNotEmpty) {
    for (final i in outputs.saplingNotes.indexed) {
      final account = accounts.firstWhere(
        (e) => e.saplingIvks.contains(i.$2.output.account),
      );
      await builder.setSaplingProofGenerationKey(
        index: i.$1,
        expsk: account.saplingSk,
      );
    }
    await builder.proofSapling();

    for (final i in outputs.saplingNotes.indexed) {
      final account = accounts.firstWhere(
        (e) => e.saplingIvks.contains(i.$2.output.account),
      );
      await builder.signSapling(index: i.$1, ask: account.saplingSk.ask);
    }
  }

  /// Generate proofs and signatures for Orchard spends
  if (outputs.orchardNotes.isNotEmpty) {
    for (final i in outputs.orchardNotes.indexed) {
      final account = accounts.firstWhere(
        (e) => e.orchardIvks.contains(i.$2.output.account),
      );
      await builder.signOrchard(
        index: i.$1,
        ask: OrchardSpendAuthorizingKey.fromSpendingKey(account.orchardSk),
      );
    }
    await builder.proofOrchard();
  }

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
  final txId = await builder.extractAndSendTransaction(provider);

  /// Example txid:
  /// 6a949fb8b5f2c090778f65a14d4fb670d5e3418f48fe83c3ca4a80ff5b875066
}
