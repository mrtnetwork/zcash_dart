import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:zcash_dart/zcash.dart';

/// Experiment requested by the user:
///
/// 1. Two accounts (A=sapling receiver, B=orchard receiver). Fund each with
///    shielded notes spread over MULTIPLE blocks (5 sapling notes in 5
///    blocks, then 5 orchard notes in 5 blocks).
/// 2. Fresh DefaultMerkleController: scan 1..tip with A's SAPLING keys only,
///    updateState, buildMerkle for the sapling notes (record anchor+paths).
/// 3. On the SAME controller: scan 1..tip with B's ORCHARD keys only,
///    updateState again, then buildMerkle for the ORIGINAL sapling notes.
///    Question: are the previous sapling markers still there / retrievable,
///    or did the second update wipe them?
/// 4. Repeat in reverse order on a second controller (orchard first, then
///    sapling) to show order-independence.
///
/// Block numbers are not important (chain keeps growing); the purpose —
/// double updateState(1..n) with different keys on one controller — is what
/// is tested. Uses DefaultMerkleController (pure Dart), NOT native.
Future<void> main() async {
  final host = Platform.environment['LWD_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9067');
  final context = await getContext(libraryPath: zcashRustLibrary());
  final provider = createGrpcClient(url: host, port: port);
  final rpc = _ZcashRpc();

  final accountA = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(201),
  );
  final accountB = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(202),
  );

  print('A sapling        : ${accountA.uivk.defaultAddress().address}');
  print('B orchard        : ${accountB.uivk.defaultAddress().address}');

  // ---- Phase 1: A already holds 5 sapling notes funded by the node wallet
  // (z_shieldcoinbase + z_sendmany, blocks 118..122). Verify, do not re-fund.
  // ---- Phase 2+3 share the LWD-sync helper ----
  Future<void> waitLwd(int height) async {
    for (var i = 0; i < 60; i++) {
      final h = await getLatestBlockId(provider);
      if (h >= height) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw StateError('lightwalletd did not sync to $height in time');
  }

  List<
    ZcashBlockProcessorScanKey<SaplingFullViewingKey, SaplingIncomingViewingKey>
  >
  saplingKeyOfA() => [
    ZcashBlockProcessorScanKey(
      fvk: accountA.saplingFvk.fvk,
      viewKeys:
          accountA.saplingIvks
              .map((e) => IVKWithActivationHeight(ivk: e))
              .toList(),
    ),
  ];
  final preScan = await getNotes(
    provider: provider,
    context: context,
    startHeight: 1,
    endHeight: await getLatestBlockId(provider),
    sapling: saplingKeyOfA(),
  );
  final preNotes =
      preScan.outputs
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .toList();
  final saplingHeights = <int>[118, 119, 120, 121, 122];
  print(
    'A holds ${preNotes.length} sapling notes '
    '(expected 5 at blocks $saplingHeights)',
  );
  if (preNotes.length < 5) {
    throw StateError('A does not hold the 5 funded sapling notes; aborting.');
  }

  // ---- Phase 3: 5 orchard notes to B (sapling -> orchard), one per block ----
  // Amounts fit inside A's 15 ZEC (1+2+3+4+5) with room for fees.
  final orchardHeights = <int>[];
  const orchAmounts = [50000000, 100000000, 150000000, 200000000, 250000000];
  for (var i = 0; i < 5; i++) {
    final txid = await _sendOrchardFromSapling(
      context: context,
      provider: provider,
      from: accountA,
      orchardTo: accountB.uivk.defaultAddress().address,
      amount: ZAmount.from(orchAmounts[i]),
    );
    await rpc.generate(1);
    final h = await rpc.getBlockCount();
    await waitLwd(h);
    orchardHeights.add(h);
    print('orchard note ${i + 1}/5 sent in tx $txid, mined at height $h');
  }

  final tip = await getLatestBlockId(provider);
  print('sapling note blocks: $saplingHeights');
  print('orchard note blocks: $orchardHeights');
  print('chain tip: $tip');

  // ---- Phase 4: scan each pool separately (same range 1..tip) ----
  List<
    ZcashBlockProcessorScanKey<OrchardFullViewingKey, OrchardIncomingViewingKey>
  >
  orchardKeyOf(ZcashTestAccount a) => [
    ZcashBlockProcessorScanKey(
      fvk: a.orchardFvk,
      viewKeys:
          a.orchardIvks.map((e) => IVKWithActivationHeight(ivk: e)).toList(),
    ),
  ];
  List<
    ZcashBlockProcessorScanKey<SaplingFullViewingKey, SaplingIncomingViewingKey>
  >
  saplingKeyOf(ZcashTestAccount a) => [
    ZcashBlockProcessorScanKey(
      fvk: a.saplingFvk.fvk,
      viewKeys:
          a.saplingIvks.map((e) => IVKWithActivationHeight(ivk: e)).toList(),
    ),
  ];

  // Sapling scan with A's keys only.
  final saplScan = await getNotes(
    provider: provider,
    context: context,
    startHeight: 1,
    endHeight: tip,
    sapling: saplingKeyOf(accountA),
  );
  final saplingOutputs =
      saplScan.outputs
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .toList();
  print(
    'sapling-only scan: ${saplScan.scannedBlocks.length} blocks, '
    '${saplingOutputs.length} sapling notes for A',
  );

  // Orchard scan with B's keys only.
  final orchScan = await getNotes(
    provider: provider,
    context: context,
    startHeight: 1,
    endHeight: tip,
    orchard: orchardKeyOf(accountB),
  );
  final orchardOutputs =
      orchScan.outputs
          .map((e) => e.output)
          .whereType<OrchardScannedOutput>()
          .toList();
  print(
    'orchard-only scan: ${orchScan.scannedBlocks.length} blocks, '
    '${orchardOutputs.length} orchard notes for B',
  );

  // ---- Phase 5: ONE DefaultMerkleController, sapling update THEN orchard update ----
  print('');
  print(
    '===== Controller-1: sapling update first, orchard update second =====',
  );
  final c1 = DefaultMerkleController(context: context, provider: provider);

  await c1.updateState(saplScan.scannedBlocks);
  print(
    'c1: after sapling updateState: '
    'sapling checkpoints=${c1.saplingCheckpointIds} '
    'orchard checkpoints=${c1.orchardCheckpointIds}',
  );
  final saplBuild1 = await c1.buildMerkle(
    targetHeight: tip,
    saplingOutputs: saplingOutputs,
  );
  print(
    'c1: buildMerkle(sapling) BEFORE orchard update: OK, '
    '${saplBuild1.saplingNotes.length} paths, anchor=${saplBuild1.saplingAnchor}',
  );
  final firstPathBefore = saplBuild1.saplingNotes.first.merklePath;

  await c1.updateState(orchScan.scannedBlocks);
  print(
    'c1: after orchard updateState: '
    'sapling checkpoints=${c1.saplingCheckpointIds} '
    'orchard checkpoints=${c1.orchardCheckpointIds}',
  );
  try {
    final saplBuild2 = await c1.buildMerkle(
      targetHeight: tip,
      saplingOutputs: saplingOutputs,
    );
    final sameAnchor = saplBuild2.saplingAnchor == saplBuild1.saplingAnchor;
    final firstPathAfter = saplBuild2.saplingNotes.first.merklePath;
    final samePath = firstPathAfter == firstPathBefore;
    print(
      'c1: buildMerkle(sapling) AFTER orchard update: OK, '
      '${saplBuild2.saplingNotes.length} paths, anchor=${saplBuild2.saplingAnchor}',
    );
    print(
      'c1: RESULT anchor identical: $sameAnchor, first witness identical: $samePath',
    );
    if (sameAnchor && samePath) {
      print(
        'c1: CONCLUSION: sapling markers SURVIVED the second update — '
        'previous witnesses are still retrievable.',
      );
    } else {
      print('c1: CONCLUSION: second update CHANGED sapling witnesses!');
    }
  } catch (e) {
    print('c1: buildMerkle(sapling) AFTER orchard update: FAILED -> $e');
    print('c1: CONCLUSION: second update REMOVED sapling markers.');
  }
  final orchBuild1 = await c1.buildMerkle(
    targetHeight: tip,
    orchardOutputs: orchardOutputs,
  );
  print(
    'c1: buildMerkle(orchard) after both updates: OK, '
    '${orchBuild1.orchardNotes.length} paths, anchor=${orchBuild1.orchardAnchor}',
  );

  // ---- Phase 6: reverse order on a fresh controller ----
  print('');
  print(
    '===== Controller-2: orchard update first, sapling update second =====',
  );
  final c2 = DefaultMerkleController(context: context, provider: provider);
  await c2.updateState(orchScan.scannedBlocks);
  final orchBuildFirst = await c2.buildMerkle(
    targetHeight: tip,
    orchardOutputs: orchardOutputs,
  );
  print(
    'c2: buildMerkle(orchard) BEFORE sapling update: OK, '
    '${orchBuildFirst.orchardNotes.length} paths, anchor=${orchBuildFirst.orchardAnchor}',
  );
  await c2.updateState(saplScan.scannedBlocks);
  final orchBuildSecond = await c2.buildMerkle(
    targetHeight: tip,
    orchardOutputs: orchardOutputs,
  );
  final orchSame =
      orchBuildSecond.orchardAnchor == orchBuildFirst.orchardAnchor;
  print(
    'c2: buildMerkle(orchard) AFTER sapling update: OK, anchor same: $orchSame',
  );
  final saplBuildC2 = await c2.buildMerkle(
    targetHeight: tip,
    saplingOutputs: saplingOutputs,
  );
  final crossAnchor = saplBuildC2.saplingAnchor == saplBuild1.saplingAnchor;
  print(
    'c2: buildMerkle(sapling): OK, anchor matches controller-1: $crossAnchor',
  );
  print('');
  print('DONE');
}

/// Sends ONE orchard output to [orchardTo], funded by ALL currently unspent
/// sapling notes of [from]. Sapling change returns to [from]'s sapling pool.
/// Mines nothing; caller must generate(1) afterwards.
Future<String> _sendOrchardFromSapling({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZcashTestAccount from,
  required String orchardTo,
  required ZAmount amount,
}) async {
  final target = await getLatestBlockId(provider);

  final saplingKeys = [
    ZcashBlockProcessorScanKey(
      fvk: from.saplingFvk.fvk,
      viewKeys:
          from.saplingIvks.map((e) => IVKWithActivationHeight(ivk: e)).toList(),
    ),
  ];
  final myNotes = await getNotes(
    provider: provider,
    context: context,
    startHeight: 1,
    endHeight: target,
    sapling: saplingKeys,
  );
  final scanned = myNotes.outputs.map((e) => e.output).toList();
  final saplingNotes = scanned.whereType<SaplingScannedOutput>().toList();
  if (saplingNotes.isEmpty) {
    throw StateError('no unspent sapling notes left for funding');
  }
  final merkle = DefaultMerkleController(context: context, provider: provider);
  await merkle.updateState(myNotes.scannedBlocks);
  final outputs = await merkle.buildMerkle(
    targetHeight: target,
    saplingOutputs: saplingNotes,
  );

  final builder = TransactionBuilder(
    targetHeight: target,
    config: TransactionBuildConfigStandard(
      orchard: outputs.orchardAnchor,
      sapling: outputs.saplingAnchor,
    ),
    context: context,
    network: ZcashNetwork.regtest,
  );
  for (final n in outputs.saplingNotes) {
    await builder.addSaplingSpend(
      fvk: from.saplingFvk.fvk,
      note: n.output.note,
      merklePath: n.merklePath,
    );
  }
  await builder.addOutput(
    target: TransactionOutputTarget.orchard(address: orchardTo),
    amount: amount,
  );
  // Sapling change back to the sender (keeps remaining funds spendable).
  await builder.addChange(
    target: TransactionOutputTarget.sapling(
      address: from.uivk.defaultAddress().address,
    ),
  );
  for (final i in outputs.saplingNotes.indexed) {
    await builder.setSaplingProofGenerationKey(
      index: i.$1,
      expsk: from.saplingSk,
    );
  }
  await builder.proofSapling();
  for (final i in outputs.saplingNotes.indexed) {
    await builder.signSapling(index: i.$1, ask: from.saplingSk.ask);
  }
  // Orchard outputs without orchard spends still need their proof.
  await builder.proofOrchard();
  final txid = await builder.extractAndSendTransaction(provider);
  return '$txid';
}

/// Minimal zcashd RPC client (regtest foo/bar @ 127.0.0.1:18232).
class _ZcashRpc {
  final _client = HttpClient();
  Future<Map<String, dynamic>> _call(
    String method,
    List<dynamic> params,
  ) async {
    final req = await _client.postUrl(Uri.parse('http://127.0.0.1:18232'));
    final auth = base64Encode(utf8.encode('foo:bar'));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Basic $auth');
    req.write(
      jsonEncode({
        'jsonrpc': '1.0',
        'id': '1',
        'method': method,
        'params': params,
      }),
    );
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (decoded['error'] != null) {
      throw StateError('RPC $method failed: ${decoded['error']}');
    }
    return decoded;
  }

  Future<void> sendToAddress(String addr, double amount) async {
    await _call('sendtoaddress', [addr, amount]);
  }

  Future<void> generate(int n) async {
    await _call('generate', [n]);
  }

  Future<int> getBlockCount() async {
    final r = await _call('getblockcount', []);
    return (r['result'] as num).toInt();
  }
}
