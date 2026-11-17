import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:zcash_dart/zcash.dart';

/// User's real scenario (single pool, multiple accounts, different sync
/// start heights):
/// - Account A synced 1..n, merkle state holds its checkpoints/witnesses.
/// - Account B joins with start height 2..n; wallet reuses the SAME merkle
///   controller and feeds 2..n, then later 1..n again.
/// Question: does re-feeding an overlapping range on the same controller
/// lose account A's checkpoints/witnesses?
///
/// Runs against BOTH DefaultMerkleController and NativeMerkleController.
Future<void> main() async {
  final host = Platform.environment['LWD_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9067');
  final context = await getContext(libraryPath: zcashRustLibrary());
  final provider = createGrpcClient(url: host, port: port);
  final accountA = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(201),
  );
  // Fresh account B: never received anything. Its keys cannot decrypt A's
  // notes, so A's positions enter as ephemeral (not marked) in its scan.
  final accountB = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(203),
  );

  final rpc = _ZcashRpc();
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
  saplingKeysOf(ZcashTestAccount a) => [
    ZcashBlockProcessorScanKey(
      fvk: a.saplingFvk.fvk,
      viewKeys:
          a.saplingIvks.map((e) => IVKWithActivationHeight(ivk: e)).toList(),
    ),
  ];
  Future<int> countUnspentSapling(ZcashTestAccount a) async {
    final s = await getNotes(
      provider: provider,
      context: context,
      startHeight: 1,
      endHeight: await getLatestBlockId(provider),
      sapling: saplingKeysOf(a),
    );
    return s.outputs
        .map((e) => e.output)
        .whereType<SaplingScannedOutput>()
        .length;
  }

  // ---- Funding: A >= 10 and B >= 10 unspent sapling notes, EACH in its
  // OWN block (distinct block ids). One single-output tx per block.
  // Stage 1: top B up to 10 (0.3 ZEC each, funded by A).
  // Stage 2: chain 10 self-sends for A (0.3 ZEC each), all above B's notes
  // (reverse layout). Flaky native proves are retried (rebuild from scratch).
  Future<String> sendSaplingRetry(
    List<(String, ZAmount)> outs, {
    bool spendAll = true,
    String? transparentChangeTo,
  }) async {
    Object? last;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await _sendSaplingMulti(
          context: context,
          provider: provider,
          from: accountA,
          outputs: outs,
          spendAll: spendAll,
          transparentChangeTo: transparentChangeTo,
        );
      } catch (e) {
        last = e;
        print(
          '  attempt $attempt failed (${'$e'.split('\n').first}), retrying...',
        );
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    throw StateError('send failed 3x: $last');
  }

  Future<BigInt> totalUnspentSapling(ZcashTestAccount a) async {
    final s = await getNotes(
      provider: provider,
      context: context,
      startHeight: 1,
      endHeight: await getLatestBlockId(provider),
      sapling: saplingKeysOf(a),
    );
    return s.outputs
        .map((e) => e.output)
        .whereType<SaplingScannedOutput>()
        .fold<BigInt>(BigInt.zero, (p, c) => p + c.note.value.value);
  }

  final perNote = ZAmount.from(30000000); // 0.3 ZEC
  var bCount = await countUnspentSapling(accountB);
  print('start: B notes=$bCount (need 10, one per block)');
  while (bCount < 10) {
    final txid = await sendSaplingRetry([
      (accountB.uivk.defaultAddress().address, perNote),
    ]);
    await rpc.generate(1);
    final h = await rpc.getBlockCount();
    await waitLwd(h);
    print('B note ${bCount + 1}/10 in tx $txid at height $h');
    bCount = await countUnspentSapling(accountB);
  }
  var aCount = await countUnspentSapling(accountA);
  var aTotal = await totalUnspentSapling(accountA);
  print('A holds $aCount notes, total=${aTotal}zat');
  // Self-send chaining only if A can afford 0.3 outputs (needs 0.3+fee
  // in its biggest note); otherwise skip to the funder top-up below.
  var aMade = 0;
  while (aCount < 11 && aTotal >= BigInt.from(31000000)) {
    // Spend ONLY the biggest note (change), leave the rest untouched:
    // +1 note per block, each in its own block. Small 0.04 notes: the
    // killed earlier run left A with ~0.5 ZEC total across 2 notes.
    final txid = await sendSaplingRetry([
      (accountA.uivk.defaultAddress().address, ZAmount.from(4000000)),
    ], spendAll: false);
    await rpc.generate(1);
    final h = await rpc.getBlockCount();
    await waitLwd(h);
    aMade++;
    print('A note +1 in tx $txid at height $h');
    aCount = await countUnspentSapling(accountA);
    if (aMade > 14) throw StateError('A count stuck at $aCount');
  }
  print('after funding: A=$aCount notes, B=$bCount notes');
  // A top-up via FUNDer transparent (sweep change above landed there):
  // one 0.3-ZEC sapling note per block until A holds >= 11. B untouched.
  {
    final funder = ZcashTestAccount.fromSeed(
      context,
      accountIndex: Bip32KeyIndex.hardenIndex(200),
    );
    while (aCount < 11) {
      final txid = await sendTransparentRetry(
        context: context,
        provider: provider,
        from: funder,
        saplingTo: accountA.uivk.defaultAddress().address,
        amount: ZAmount.from(30000000),
      );
      await rpc.generate(1);
      final h = await rpc.getBlockCount();
      await waitLwd(h);
      print('A note top-up in tx $txid at height $h');
      aCount = await countUnspentSapling(accountA);
    }
    bCount = await countUnspentSapling(accountB);
    print('final: A=$aCount notes, B=$bCount notes');
    if (aCount < 10 || bCount < 10) {
      throw StateError('need >= 10 notes each, got A=$aCount B=$bCount');
    }
  }

  final tip = await getLatestBlockId(provider);
  print('tip: $tip');

  final full = await getNotes(
    provider: provider,
    context: context,
    startHeight: 1,
    endHeight: tip,
    sapling: saplingKeysOf(accountA),
  );
  final aNotes =
      full.outputs
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .toList();
  // Protocol purity: A scan used sapling keys only -> no orchard outputs.
  final aOrchard =
      full.outputs
          .map((e) => e.output)
          .whereType<OrchardScannedOutput>()
          .length;
  print('A unspent notes: ${aNotes.length} sapling, $aOrchard orchard');
  if (aNotes.isEmpty) throw StateError('no notes to witness');

  // Overlapping ranges: 1..tip with A's keys (account A sync) then 2..tip
  // with B's keys (new account B joins, start height 2).
  final rangeFull = full.scannedBlocks;
  final bScan = await getNotes(
    provider: provider,
    context: context,
    startHeight: 2,
    endHeight: tip,
    sapling: saplingKeysOf(accountB),
  );
  final rangeFrom2 = bScan.scannedBlocks;
  final bNotes =
      bScan.outputs
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .toList();
  final bOrchard =
      bScan.outputs
          .map((e) => e.output)
          .whereType<OrchardScannedOutput>()
          .length;
  print(
    'rangeFull blocks: ${rangeFull.length}, rangeFrom2 blocks: ${rangeFrom2.length}',
  );
  print('B notes in 2..n scan: ${bNotes.length} sapling, $bOrchard orchard');

  bool pathsEqual(BuildMerleOutput x, BuildMerleOutput y) {
    if (x.saplingNotes.length != y.saplingNotes.length) return false;
    for (var i = 0; i < x.saplingNotes.length; i++) {
      if (x.saplingNotes[i].merklePath != y.saplingNotes[i].merklePath) {
        return false;
      }
    }
    return true;
  }

  // Straight-run native references for the serde pass below.
  BuildMerleOutput? refB1, refB2, refB2a, refB3, refB3a;
  for (final kind in ['default', 'native']) {
    print('');
    print('===== $kind controller: feed 1..n, then 2..n, then 1..n =====');
    final MerkleController c =
        kind == 'default'
            ? DefaultMerkleController(context: context, provider: provider)
            : NativeMerkleController(context: context, provider: provider);

    await c.updateState(rangeFull);
    // Witness BOTH accounts' notes (all sapling, single protocol).
    // NOTE: B's notes are ephemeral in A's feed (A cannot decrypt them),
    // so they become witnessable only after B's own feed marks them.
    final b1 = await c.buildMerkle(
      targetHeight: tip,
      saplingOutputs: [...aNotes],
    );
    print(
      '$kind: after 1..n: ${b1.saplingNotes.length} sapling paths ok '
      '(A=${aNotes.length})',
    );
    if (kind == 'native') refB1 = b1;

    await c.updateState(rangeFrom2);
    String r2;
    try {
      final b2 = await c.buildMerkle(
        targetHeight: tip,
        saplingOutputs: [...aNotes, ...bNotes],
      );
      final b2a = await c.buildMerkle(
        targetHeight: tip,
        saplingOutputs: [...aNotes],
      );
      final sameA = b2a.saplingAnchor == b1.saplingAnchor;
      final sameP = pathsEqual(b2a, b1);
      r2 =
          'OK, A anchor same: $sameA, A witnesses same: $sameP; '
          'B paths now witnessable: ${b2.saplingNotes.length - b2a.saplingNotes.length}';
      if (kind == 'native') {
        refB2 = b2;
        refB2a = b2a;
      }
    } catch (e) {
      r2 = 'FAILED -> ${'$e'.split('\n').first}';
    }
    print('$kind: after 2..n (B keys): buildMerkle(A+B notes): $r2');

    await c.updateState(rangeFull);
    String r3;
    try {
      final b3 = await c.buildMerkle(
        targetHeight: tip,
        saplingOutputs: [...aNotes, ...bNotes],
      );
      final b3a = await c.buildMerkle(
        targetHeight: tip,
        saplingOutputs: [...aNotes],
      );
      final sameA = b3a.saplingAnchor == b1.saplingAnchor;
      final sameP = pathsEqual(b3a, b1);
      r3 =
          'OK, A anchor same: $sameA, A witnesses same: $sameP; '
          'A+B paths: ${b3.saplingNotes.length}';
      if (kind == 'native') {
        refB3 = b3;
        refB3a = b3a;
      }
    } catch (e) {
      r3 = 'FAILED -> ${'$e'.split('\n').first}';
    }
    print('$kind: after 1..n again: buildMerkle(A+B notes): $r3');

    if (c is NativeMerkleController) await c.closeContext();
  }

  // Native serde pass: fresh instance per round via serialize/deserialize.
  // Each round's outputs must equal the straight native run bit-for-bit.
  {
    print('');
    print('===== native-serde: fresh instance per round =====');
    final refs = [refB1, refB2, refB2a, refB3, refB3a];
    if (refs.any((e) => e == null)) throw StateError('missing native refs');
    final rB1 = refB1 as BuildMerleOutput;
    final rB2 = refB2 as BuildMerleOutput;
    final rB2a = refB2a as BuildMerleOutput;
    final rB3 = refB3 as BuildMerleOutput;
    final rB3a = refB3a as BuildMerleOutput;
    var c = NativeMerkleController(context: context, provider: provider);

    Future<NativeMerkleController> roundTrip(NativeMerkleController c) async {
      final bytes = (await c.serialize()).toList();
      print('serde: serialized ${bytes.length} bytes');
      if (bytes.isEmpty) throw StateError('empty serialization');
      await c.closeContext();
      return NativeMerkleController.deserialize(
        bytes: bytes,
        context: context,
        provider: provider,
      );
    }

    bool sameAs(BuildMerleOutput got, BuildMerleOutput want, String tag) {
      final ok =
          got.saplingAnchor == want.saplingAnchor &&
          got.saplingNotes.length == want.saplingNotes.length &&
          pathsEqual(got, want);
      print(
        'serde: $tag identical to straight run: $ok '
        '(notes=${got.saplingNotes.length})',
      );
      return ok;
    }

    var allOk = true;
    // Round 1 on instance 1.
    await c.updateState(rangeFull);
    allOk &= sameAs(
      await c.buildMerkle(targetHeight: tip, saplingOutputs: [...aNotes]),
      rB1,
      'round1 A',
    );
    // Fresh instance 2 continues with round 2 (must reproduce round 1 first).
    c = await roundTrip(c);
    allOk &= sameAs(
      await c.buildMerkle(targetHeight: tip, saplingOutputs: [...aNotes]),
      rB1,
      'round2-pre A',
    );
    await c.updateState(rangeFrom2);
    allOk &= sameAs(
      await c.buildMerkle(
        targetHeight: tip,
        saplingOutputs: [...aNotes, ...bNotes],
      ),
      rB2,
      'round2 A+B',
    );
    allOk &= sameAs(
      await c.buildMerkle(targetHeight: tip, saplingOutputs: [...aNotes]),
      rB2a,
      'round2 A',
    );
    // Fresh instance 3 continues with round 3.
    c = await roundTrip(c);
    await c.updateState(rangeFull);
    allOk &= sameAs(
      await c.buildMerkle(
        targetHeight: tip,
        saplingOutputs: [...aNotes, ...bNotes],
      ),
      rB3,
      'round3 A+B',
    );
    allOk &= sameAs(
      await c.buildMerkle(targetHeight: tip, saplingOutputs: [...aNotes]),
      rB3a,
      'round3 A',
    );
    await c.closeContext();
    if (!allOk) throw StateError('serde round-trip mismatch');
    print('serde: ALL ROUNDS IDENTICAL');
  }
  print('');
  print('DONE');
}

/// Sends sapling outputs to [outputs] (address, amount pairs).
/// When [spendAll] (default) every unspent note of [from] is spent.
/// When false, only the single highest-value note is spent, so the note
/// COUNT grows by exactly the number of created outputs per call.
/// Remainder returns to [from] as sapling change. Mines nothing.
Future<String> _sendSaplingMulti({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZcashTestAccount from,
  required List<(String, ZAmount)> outputs,
  bool spendAll = true,
  String? transparentChangeTo,
}) async {
  final target = await getLatestBlockId(provider);
  final myNotes = await getNotes(
    provider: provider,
    context: context,
    startHeight: 1,
    endHeight: target,
    sapling: [
      ZcashBlockProcessorScanKey(
        fvk: from.saplingFvk.fvk,
        viewKeys:
            from.saplingIvks
                .map((e) => IVKWithActivationHeight(ivk: e))
                .toList(),
      ),
    ],
  );
  final saplingNotes =
      myNotes.outputs
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .toList();
  if (saplingNotes.isEmpty) throw StateError('no unspent sapling notes left');

  final merkle = DefaultMerkleController(context: context, provider: provider);
  await merkle.updateState(myNotes.scannedBlocks);
  final built = await merkle.buildMerkle(
    targetHeight: target,
    saplingOutputs: saplingNotes,
  );

  final builder = TransactionBuilder(
    targetHeight: target,
    config: TransactionBuildConfigStandard(
      orchard: built.orchardAnchor,
      sapling: built.saplingAnchor,
    ),
    context: context,
    network: ZcashNetwork.regtest,
  );
  var spends = built.saplingNotes;
  if (!spendAll) {
    spends = [...spends]..sort(
      (a, b) => b.output.note.value.value.compareTo(a.output.note.value.value),
    );
    spends = spends.take(1).toList();
  }
  for (final n in spends) {
    await builder.addSaplingSpend(
      fvk: from.saplingFvk.fvk,
      note: n.output.note,
      merklePath: n.merklePath,
    );
  }
  for (final o in outputs) {
    await builder.addOutput(
      target: TransactionOutputTarget.sapling(address: o.$1),
      amount: o.$2,
    );
  }
  await builder.addChange(
    target:
        transparentChangeTo != null
            ? TransactionOutputTarget.transparent(address: transparentChangeTo)
            : TransactionOutputTarget.sapling(
              address: from.uivk.defaultAddress().address,
            ),
  );
  for (final i in spends.indexed) {
    await builder.setSaplingProofGenerationKey(
      index: i.$1,
      expsk: from.saplingSk,
    );
  }
  await builder.proofSapling();
  for (final i in spends.indexed) {
    await builder.signSapling(index: i.$1, ask: from.saplingSk.ask);
  }
  final txid = await builder.extractAndSendTransaction(provider);
  return '$txid';
}

/// Sends ONE sapling output funded by funder's transparent UTXOs.
/// Transparent change returns to [from]'s external address.
/// Mines nothing; caller must generate(1) afterwards. Retried 3x.
Future<String> sendTransparentRetry({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZcashTestAccount from,
  required String saplingTo,
  required ZAmount amount,
}) async {
  Object? last;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final utxos = await getAccountsConfrimedUtxos(provider, [
        from.uivk.defaultTransparentAddress(),
      ]);
      if (utxos.isEmpty) throw StateError('no confirmed transparent UTXOs');
      final target = await getLatestBlockId(provider);
      final myNotes = await getNotes(
        provider: provider,
        context: context,
        startHeight: 1,
        endHeight: target,
      );
      final merkle = DefaultMerkleController(
        context: context,
        provider: provider,
      );
      await merkle.updateState(myNotes.scannedBlocks);
      final scanned = myNotes.outputs.map((e) => e.output).toList();
      final outputs = await merkle.buildMerkle(
        targetHeight: target,
        orchardOutputs: scanned.whereType<OrchardScannedOutput>().toList(),
        saplingOutputs: scanned.whereType<SaplingScannedOutput>().toList(),
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
      for (final u in utxos) {
        await builder.addTransparentSpend(TransparentSigningInput(input: u));
      }
      await builder.addOutput(
        target: TransactionOutputTarget.sapling(address: saplingTo),
        amount: amount,
      );
      await builder.addChange(
        target: TransactionOutputTarget.transparent(
          address: from.uivk.defaultTransparentAddress().address,
        ),
      );
      await builder.proofSapling();
      for (final i in utxos.indexed) {
        final sk = from.transparentSk
            .childKey(Bip32KeyIndex(Bip44Changes.chainExt.value))
            .childKey(from.uivk.defaultTransparentAddress().bip32Index);
        await builder.signTransparent(
          index: i.$1,
          sk: ZECPrivate.fromBip32(sk.privateKey),
        );
      }
      final txid = await builder.extractAndSendTransaction(provider);
      return '$txid';
    } catch (e) {
      last = e;
      print(
        '  attempt $attempt failed (${'$e'.split('\n').first}), retrying...',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
  throw StateError('send failed 3x: $last');
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

  Future<void> generate(int n) async {
    await _call('generate', [n]);
  }

  Future<int> getBlockCount() async {
    final r = await _call('getblockcount', []);
    return (r['result'] as num).toInt();
  }
}
