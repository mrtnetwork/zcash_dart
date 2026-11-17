import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';

/// Validation suite for the local regtest setup.
///
///   1. Merkle round trip: scan 1..110 -> update the merkle -> serialize ->
///      deserialize -> restore -> update with 300..310 -> build the anchors ->
///      build, sign and broadcast a transaction that spends a note created
///      BEFORE the restore and notes created AFTER it.
///   2. Multi-spend: spend several sapling and several orchard notes plus
///      several transparent UTXOs in one transaction, with transparent,
///      sapling and orchard outputs.
///   3. Orchard pool versions: report the bundle version the chain uses and
///      check the version mapping for v1 / v2 / v3.
///
/// Usage (run from the example package):
///   LWD_PORT=9071 dart run lib/examples/transfer/validation_suite.dart
/// Stable identity of a transparent coin (txid:vout).
String _outpoint(TransparentUtxo utxo) =>
    '${utxo.txId.hash.join(',')}:${utxo.vout}';

/// Tree positions of the notes that an earlier test already spent, so the
/// tests in this suite do not fight over the same notes. Every note has a
/// unique position in its pool's note commitment tree.
final Set<int> spentPositions = {};

/// Outpoints (txid:index) of the transparent coins an earlier test spent.
final Set<String> spentCoins = {};

Future<void> main() async {
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9071');
  final context = await getContext(libraryPath: zcashRustLibrary());
  final provider = createGrpcClient(url: '127.0.0.1', port: port);

  final account = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(101),
  );

  final saplingKey = ZcashBlockProcessorScanKey(
    fvk: account.saplingFvk.fvk,
    viewKeys:
        account.saplingIvks
            .map((e) => IVKWithActivationHeight(ivk: e))
            .toList(),
  );
  final orchardKey = ZcashBlockProcessorScanKey(
    fvk: account.orchardFvk,
    viewKeys:
        account.orchardIvks
            .map((e) => IVKWithActivationHeight(ivk: e))
            .toList(),
  );

  print('=' * 72);
  print('1. MERKLE SERIALIZE / DESERIALIZE / RESTORE / UPDATE / ANCHOR');
  print('=' * 72);
  await merkleRoundTrip(
    context: context,
    provider: provider,
    account: account,
    saplingKey: saplingKey,
    orchardKey: orchardKey,
  );

  print('');
  print('=' * 72);
  print('2. MULTI-SPEND (several sapling + orchard notes, mixed outputs)');
  print('=' * 72);
  await multiSpend(
    context: context,
    provider: provider,
    account: account,
    saplingKey: saplingKey,
    orchardKey: orchardKey,
  );

  print('');
  print('=' * 72);
  print('3. ORCHARD POOL VERSIONS');
  print('=' * 72);
  orchardVersions(context: context, provider: provider);
}

/// Scans [start]..[end] and returns the scanned blocks plus every output
/// that belongs to the account.
Future<({List<ScannedBlock> blocks, List<ScannedOutputWithIvk> outputs})>
scanRange(
  ZcashWalletdProvider provider,
  ZcashCryptoContext context,
  ZcashBlockProcessorScanKey<SaplingFullViewingKey, SaplingIncomingViewingKey>
  saplingKey,
  ZcashBlockProcessorScanKey<OrchardFullViewingKey, OrchardIncomingViewingKey>
  orchardKey, {
  required int start,
  required int end,
}) async {
  final scan = DefaultZcashBlockScanner(
    config: ZcashBlockProcessorConfig(
      network: ZcashNetwork.regtest,
      context: context,
      orchardViewKeys: [orchardKey],
      saplingViewKeys: [saplingKey],
    ),
    provider: provider,
  );
  final blocks = <ScannedBlock>[];
  final outputs = <ScannedOutputWithIvk>[];
  await for (final block in scan.scanBlock(start, end)) {
    blocks.add(block);
    for (final tx in block.txes) {
      for (final output in tx.scannedOutputs()) {
        outputs.add(output);
      }
    }
  }
  return (blocks: blocks, outputs: outputs);
}

Future<void> merkleRoundTrip({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZcashTestAccount account,
  required ZcashBlockProcessorScanKey<
    SaplingFullViewingKey,
    SaplingIncomingViewingKey
  >
  saplingKey,
  required ZcashBlockProcessorScanKey<
    OrchardFullViewingKey,
    OrchardIncomingViewingKey
  >
  orchardKey,
}) async {
  // ---- phase 1: scan the first range and feed the merkle tree ----------
  print('-- scanning blocks 1..110 (sapling notes live at 101..110)');
  final first = await scanRange(
    provider,
    context,
    saplingKey,
    orchardKey,
    start: 1,
    end: 110,
  );
  print(
    '   scanned ${first.blocks.length} blocks, '
    '${first.outputs.length} outputs',
  );

  final merkle = NativeMerkleController(context: context, provider: provider);
  await merkle.updateState(first.blocks);
  final bytes = await merkle.serialize();
  print('   merkle state serialized: ${bytes.length} bytes');

  // ---- phase 2: restore into a fresh controller -------------------------
  final restored = NativeMerkleController.deserialize(
    context: context,
    provider: provider,
    bytes: bytes,
  );
  print('   merkle state deserialized into a fresh controller');

  // ---- phase 3: continue with a later range ----------------------------
  print('-- scanning blocks 300..310 (orchard notes live at 300..310)');
  final second = await scanRange(
    provider,
    context,
    saplingKey,
    orchardKey,
    start: 300,
    end: 310,
  );
  print(
    '   scanned ${second.blocks.length} blocks, '
    '${second.outputs.length} outputs',
  );
  await restored.updateState(second.blocks);
  print('   restored controller updated with the second range');

  // ---- phase 4: build the anchors --------------------------------------
  final saplingOutputs =
      first.outputs
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .toList();
  final orchardOutputs =
      second.outputs
          .map((e) => e.output)
          .whereType<OrchardScannedOutput>()
          .toList();
  print(
    '   sapling notes: ${saplingOutputs.length}, '
    'orchard notes: ${orchardOutputs.length}',
  );

  final merkleOut = await restored.buildMerkle(
    targetHeight: 310,
    saplingOutputs: saplingOutputs,
    orchardOutputs: orchardOutputs,
  );
  print('   sapling anchor : ${merkleOut.saplingAnchor.inner}');
  print('   orchard anchor : ${merkleOut.orchardAnchor.inner}');
  print(
    '   merkle paths: ${merkleOut.saplingNotes.length} sapling, '
    '${merkleOut.orchardNotes.length} orchard',
  );

  // The anchors must match the ones a controller that scanned the whole
  // chain (without any restore) produces.
  print('-- reference: a fresh controller over the whole chain');
  final whole = await scanRange(
    provider,
    context,
    saplingKey,
    orchardKey,
    start: 1,
    end: 310,
  );
  final fresh = NativeMerkleController(context: context, provider: provider);
  await fresh.updateState(whole.blocks);
  final freshOut = await fresh.buildMerkle(
    targetHeight: 310,
    saplingOutputs: saplingOutputs,
    orchardOutputs: orchardOutputs,
  );
  final saplingMatch =
      freshOut.saplingAnchor.inner == merkleOut.saplingAnchor.inner;
  final orchardMatch =
      freshOut.orchardAnchor.inner == merkleOut.orchardAnchor.inner;
  print('   anchor matches the fresh controller (sapling): $saplingMatch');
  print('   anchor matches the fresh controller (orchard): $orchardMatch');
  if (!saplingMatch || !orchardMatch) {
    print('   fresh  sapling anchor: ${freshOut.saplingAnchor.inner}');
    print('   fresh  orchard anchor: ${freshOut.orchardAnchor.inner}');
    throw StateError('the restored merkle anchor does not match the chain');
  }

  // ---- phase 5: spend one note from before and one from after the
  //      restore, in a single transaction -------------------------------
  final builder = TransactionBuilder(
    targetHeight: 310,
    config: TransactionBuildConfigStandard(
      orchard: merkleOut.orchardAnchor,
      sapling: merkleOut.saplingAnchor,
    ),
    context: context,
    network: ZcashNetwork.regtest,
  );

  // transparent input. The fixture paid the transparent coinbase to the
  // unified address' transparent receiver, so that is the address to spend
  // from (it is a different derivation than defaultTransparentAddress()).
  final transparentAddress = account.uivk.defaultAddress().transparent!;
  final utxos = await provider.request(
    WalletdRequestGetAddressUtxosWithAccountOwner([
      TransparentUtxoOwner(
        publicKey: ZECPublic.fromBip32(transparentAddress.publicKey),
        address: ZcashTransparentAddress(transparentAddress.address),
      ),
    ]),
  );
  print('   transparent utxos: ${utxos.length}');
  if (utxos.isEmpty) throw StateError('no transparent utxo');
  await builder.addTransparentSpend(
    TransparentSigningInput(input: utxos.first),
  );

  // one sapling note from the first range
  final saplingNote = merkleOut.saplingNotes.first;
  await builder.addSaplingSpend(
    fvk: account.saplingFvk.fvk,
    note: saplingNote.output.note,
    merklePath: saplingNote.merklePath,
  );
  await builder.setSaplingProofGenerationKey(
    index: 0,
    expsk: account.saplingSk,
  );

  // one orchard note from the second range
  final orchardNote = merkleOut.orchardNotes.first;
  await builder.addOrchardSpend(
    fvk: account.orchardFvk,
    note: orchardNote.output.note,
    merklePath: orchardNote.merklePath,
  );

  // outputs: one to each pool
  await builder.addOutput(
    target: TransactionOutputTarget.transparent(
      address: account.uivk.defaultTransparentAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    target: TransactionOutputTarget.sapling(
      address: account.uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    target: TransactionOutputTarget.orchard(
      address: account.uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addChange(
    target: TransactionOutputTarget.transparent(
      address: account.uivk.defaultTransparentAddress().address,
    ),
  );

  await builder.proofSapling();
  await builder.signSapling(index: 0, ask: account.saplingSk.ask);
  await builder.proofOrchard();
  await builder.signOrchard(
    index: 0,
    ask: RedPallasSpendPrivateKey.fromSpendingKey(account.orchardSk),
  );
  await builder.signTransparent(
    index: 0,
    sk: ZECPrivate.fromBip32(
      account.transparentSk
          .childKey(Bip32KeyIndex(Bip44Changes.chainExt.value))
          .childKey(account.uivk.defaultAddress().transparent!.bip32Index)
          .privateKey,
    ),
  );

  final txId = await builder.extractAndSendTransaction(provider);
  print('   broadcast OK: ${txId.txId}');
  spentCoins.add(_outpoint(utxos.first.utxo));
  spentPositions.add(saplingNote.output.noteCommitmentTreePosition.position);
  spentPositions.add(orchardNote.output.noteCommitmentTreePosition.position);
}

Future<void> multiSpend({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZcashTestAccount account,
  required ZcashBlockProcessorScanKey<
    SaplingFullViewingKey,
    SaplingIncomingViewingKey
  >
  saplingKey,
  required ZcashBlockProcessorScanKey<
    OrchardFullViewingKey,
    OrchardIncomingViewingKey
  >
  orchardKey,
}) async {
  final scanned = await scanRange(
    provider,
    context,
    saplingKey,
    orchardKey,
    start: 1,
    end: 310,
  );
  final saplingOutputs =
      scanned.outputs
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .where(
            (e) =>
                !spentPositions.contains(e.noteCommitmentTreePosition.position),
          )
          .toList();
  final orchardOutputs =
      scanned.outputs
          .map((e) => e.output)
          .whereType<OrchardScannedOutput>()
          .where(
            (e) =>
                !spentPositions.contains(e.noteCommitmentTreePosition.position),
          )
          .toList();
  print(
    '   found ${saplingOutputs.length} sapling notes and '
    '${orchardOutputs.length} orchard notes (after excluding the ones '
    'test 1 spent)',
  );

  final merkle = NativeMerkleController(context: context, provider: provider);
  await merkle.updateState(scanned.blocks);
  final merkleOut = await merkle.buildMerkle(
    targetHeight: 310,
    saplingOutputs: saplingOutputs,
    orchardOutputs: orchardOutputs,
  );

  final transparentAddress = account.uivk.defaultAddress().transparent!;
  final utxos = await provider.request(
    WalletdRequestGetAddressUtxosWithAccountOwner([
      TransparentUtxoOwner(
        publicKey: ZECPublic.fromBip32(transparentAddress.publicKey),
        address: ZcashTransparentAddress(transparentAddress.address),
      ),
    ]),
  );
  print('   transparent utxos: ${utxos.length}');

  final builder = TransactionBuilder(
    targetHeight: 310,
    config: TransactionBuildConfigStandard(
      orchard: merkleOut.orchardAnchor,
      sapling: merkleOut.saplingAnchor,
    ),
    context: context,
    network: ZcashNetwork.regtest,
  );

  // spend every transparent utxo the account has
  final freshUtxos =
      utxos.where((e) => !spentCoins.contains(_outpoint(e.utxo))).toList();
  final transparentCount = freshUtxos.length < 3 ? freshUtxos.length : 3;
  for (final utxo in freshUtxos.take(transparentCount)) {
    await builder.addTransparentSpend(TransparentSigningInput(input: utxo));
  }
  // spend N sapling notes
  final nSapling = int.parse(Platform.environment['MS_SAPLING'] ?? '2');
  final nOrchard = int.parse(Platform.environment['MS_ORCHARD'] ?? '2');
  for (final note in merkleOut.saplingNotes.take(nSapling)) {
    final index = await builder.addSaplingSpend(
      fvk: account.saplingFvk.fvk,
      note: note.output.note,
      merklePath: note.merklePath,
    );
    await builder.setSaplingProofGenerationKey(
      index: index,
      expsk: account.saplingSk,
    );
  }
  // spend M orchard notes
  for (final note in merkleOut.orchardNotes.take(nOrchard)) {
    await builder.addOrchardSpend(
      fvk: account.orchardFvk,
      note: note.output.note,
      merklePath: note.merklePath,
    );
  }

  // outputs to all three pools
  await builder.addOutput(
    target: TransactionOutputTarget.transparent(
      address: account.uivk.defaultTransparentAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    target: TransactionOutputTarget.sapling(
      address: account.uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addOutput(
    target: TransactionOutputTarget.orchard(
      address: account.uivk.defaultAddress().address,
    ),
    amount: ZAmount.from(1000),
  );
  await builder.addChange(
    target: TransactionOutputTarget.transparent(
      address: account.uivk.defaultTransparentAddress().address,
    ),
  );

  await builder.proofSapling();
  for (var i = 0; i < nSapling; i++) {
    await builder.signSapling(index: i, ask: account.saplingSk.ask);
  }
  await builder.proofOrchard();
  for (var i = 0; i < nOrchard; i++) {
    await builder.signOrchard(
      index: i,
      ask: RedPallasSpendPrivateKey.fromSpendingKey(account.orchardSk),
    );
  }
  for (var i = 0; i < transparentCount; i++) {
    await builder.signTransparent(
      index: i,
      sk: ZECPrivate.fromBip32(
        account.transparentSk
            .childKey(Bip32KeyIndex(Bip44Changes.chainExt.value))
            .childKey(account.uivk.defaultAddress().transparent!.bip32Index)
            .privateKey,
      ),
    );
  }

  final txId = await builder.extractAndSendTransaction(provider);
  print('   broadcast OK: ${txId.txId}');
}

void orchardVersions({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
}) {
  const provider2 = DefaultUpgradeActivationProvider();
  for (final branch in ZcashNetworkProtocol.values) {
    final bundle = OrchardBundleVersion.forBranch(branch);
    final params =
        branch >= ZcashNetworkProtocol.nu5
            ? OrchardPcztBundleParams.forBranch(
              branch: branch,
              isIronwoodPool: false,
            ).version
            : null;
    print(
      '   ${branch.name.toString().padRight(10)} '
      'bundle=${bundle?.protocolVersion.name ?? "-"} '
      'extractParams=${params?.name ?? "-"}',
    );
  }
  // The chain this suite runs against.
  final regtest = provider2.protocolFromHeight(ZcashNetwork.regtest, 310);
  print(
    '   regtest at height 310 -> ${regtest.name} '
    '(branch id 0x${regtest.branchId.toRadixString(16)})',
  );
  print(
    '   -> tx version '
    '${TxVersionType.v5.suggestedVersionForBranch(regtest).type.name}',
  );
  print(
    '   -> orchard bundle '
    '${OrchardBundleVersion.forBranch(regtest)?.protocolVersion.name}',
  );
}
