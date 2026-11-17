import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:zcash_dart/zcash.dart';

/// Multi-account merkle merge test (zebra regtest).
///
/// 1. Creates three sapling accounts with different keys (plus a transparent
///    funder).
/// 2. Funds each account with 4 shielded notes in interleaved blocks:
///    acc1 lands on H+1,H+4,H+7,H+10, acc2 on H+2,H+5,H+8,H+11 and acc3 on
///    H+3,H+6,H+9,H+12 (H = tip before funding).
/// 3. Merkle merge sequence, mirroring a wallet that onboards accounts one
///    at a time over one shared state:
///      scan(acc1) -> updateState -> serialize -> deserialize
///      -> merge scan(acc2) -> serialize -> deserialize
///      -> merge scan(acc3)
///    then account-1 witnesses must still be retrievable and identical to
///    the pre-merge ones.
///
/// Usage (zebra regtest, lightwalletd on 9073):
///   LWD_PORT=9073 ZEBRA_RPC=http://127.0.0.1:18235 \
///     dart run lib/examples/transfer/multi_account_merkle_merge.dart
Future<void> main() async {
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9073');
  final zebraRpc =
      Platform.environment['ZEBRA_RPC'] ?? 'http://127.0.0.1:18235';
  final libraryPath = zcashRustLibrary();
  final context = await getContext(libraryPath: libraryPath);
  final provider = createGrpcClient(url: '127.0.0.1', port: port);
  final rpc = _ZebraRpc(zebraRpc);

  // ---- 1. three sapling accounts with different keys + a funder ---------
  final funder = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(200),
  );
  final acc1 = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(1),
    seed: List<int>.filled(32, 11),
  );
  final acc2 = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(2),
    seed: List<int>.filled(32, 22),
  );
  final acc3 = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(3),
    seed: List<int>.filled(32, 33),
  );
  print('acc1 sapling : ${acc1.uivk.defaultAddress().address}');
  print('acc2 sapling : ${acc2.uivk.defaultAddress().address}');
  print('acc3 sapling : ${acc3.uivk.defaultAddress().address}');
  final funderT = funder.uivk.defaultTransparentAddress();
  print('funder transp : ${funderT.address}');

  // ---- 2. fund the three accounts in interleaved blocks ------------------
  await _ensureFunderFunds(
    context: context,
    provider: provider,
    rpc: rpc,
    funder: funder,
  );
  // ---- 3. baseline scans (pre-funding) + funding + post scans ---------
  // Baseline positions let the script re-run on the same chain: only notes
  // funded by *this* run count toward the merge test.
  final tip0 = await getLatestBlockId(provider);
  print('funding starts at chain tip $tip0');
  Future<Set<int>> baselinePositions(ZcashTestAccount acc) async {
    final scan = await getNotes(
      provider: provider,
      context: context,
      startHeight: 1,
      endHeight: tip0,
      sapling: [
        ZcashBlockProcessorScanKey(
          fvk: acc.saplingFvk.fvk,
          viewKeys:
              acc.saplingIvks
                  .map((e) => IVKWithActivationHeight(ivk: e))
                  .toList(),
        ),
      ],
    );
    return scan.outputs
        .map((e) => e.output)
        .whereType<SaplingScannedOutput>()
        .map((e) => e.noteCommitmentTreePosition.position)
        .toSet();
  }

  final base1 = await baselinePositions(acc1);
  final base2 = await baselinePositions(acc2);
  final base3 = await baselinePositions(acc3);
  print(
    'baseline notes: acc1=${base1.length}, acc2=${base2.length}, '
    'acc3=${base3.length}',
  );
  final perNote = ZAmount.from(10000000); // 0.1 ZEC
  final fundedAt = <String, List<int>>{'acc1': [], 'acc2': [], 'acc3': []};
  final accounts = [('acc1', acc1), ('acc2', acc2), ('acc3', acc3)];
  for (var round = 0; round < 4; round++) {
    for (final (name, acc) in accounts) {
      final txid = await _sendShieldedRetry(
        context: context,
        provider: provider,
        from: funder,
        saplingTo: acc.uivk.defaultAddress().address,
        amount: perNote,
      );
      await rpc.generateToAddress(1, funderT.address);
      final h = await rpc.getBlockCount();
      await _waitLwd(provider, h);
      fundedAt[name]!.add(h);
      print('  $name note ${fundedAt[name]!.length}/4 in block $h (tx $txid)');
    }
  }
  print('funding pattern:');
  for (final e in fundedAt.entries) {
    print('  ${e.key} -> blocks ${e.value}');
  }

  // ---- 3. scan once per account over the funding range -------------------
  final tip = await getLatestBlockId(provider);
  Future<({List<ScannedBlock> blocks, List<SaplingScannedOutput> notes})>
  scanAcc(String name, ZcashTestAccount acc, Set<int> baseline) async {
    final scan = await getNotes(
      provider: provider,
      context: context,
      startHeight: 1,
      endHeight: tip,
      sapling: [
        ZcashBlockProcessorScanKey(
          fvk: acc.saplingFvk.fvk,
          viewKeys:
              acc.saplingIvks
                  .map((e) => IVKWithActivationHeight(ivk: e))
                  .toList(),
        ),
      ],
    );
    final notes =
        scan.outputs
            .map((e) => e.output)
            .whereType<SaplingScannedOutput>()
            .where(
              (e) => !baseline.contains(e.noteCommitmentTreePosition.position),
            )
            .toList();
    print(
      '$name scan 1..$tip: ${scan.scannedBlocks.length} blocks, '
      '${notes.length} new notes',
    );
    return (blocks: scan.scannedBlocks, notes: notes);
  }

  final s1 = await scanAcc('acc1', acc1, base1);
  final s2 = await scanAcc('acc2', acc2, base2);
  final s3 = await scanAcc('acc3', acc3, base3);
  var failures = 0;
  void check(bool ok, String label) {
    print('  [${ok ? 'OK' : 'FAIL'}] $label');
    if (!ok) failures++;
  }

  check(s1.notes.length == 4, 'acc1 owns 4 notes');
  check(s2.notes.length == 4, 'acc2 owns 4 notes');
  check(s3.notes.length == 4, 'acc3 owns 4 notes');

  // ---- 4. merge sequence with serialize/deserialize between accounts -----
  print('--- merge: acc1 -> serde -> acc2 -> serde -> acc3 ---');
  var c = NativeMerkleController(context: context, provider: provider);
  await c.updateState(s1.blocks);
  final ref = await c.buildMerkle(targetHeight: tip, saplingOutputs: s1.notes);
  check(ref.saplingNotes.length == 4, 'acc1 witnesses before merge');
  var bytes = await c.serialize();
  print('  after acc1: ${bytes.length} bytes');
  await c.closeContext();

  c = NativeMerkleController.deserialize(
    bytes: bytes,
    context: context,
    provider: provider,
  );
  await c.updateState(s2.blocks);
  bytes = await c.serialize();
  print('  after acc2: ${bytes.length} bytes');
  await c.closeContext();

  c = NativeMerkleController.deserialize(
    bytes: bytes,
    context: context,
    provider: provider,
  );
  await c.updateState(s3.blocks);
  bytes = await c.serialize();
  print('  after acc3: ${bytes.length} bytes');

  // ---- 5. account-1 witnesses must still be retrievable ------------------
  final got = await c.buildMerkle(targetHeight: tip, saplingOutputs: s1.notes);
  check(got.saplingNotes.length == 4, 'acc1 witnesses after merge');
  check(
    got.saplingAnchor == ref.saplingAnchor,
    'acc1 anchor identical to pre-merge',
  );
  var pathsSame = true;
  for (var i = 0; i < s1.notes.length; i++) {
    if (got.saplingNotes[i].merklePath != ref.saplingNotes[i].merklePath) {
      pathsSame = false;
    }
  }
  check(pathsSame, 'acc1 paths identical to pre-merge');

  // Bonus: every new note witnessable from the merged state.
  final all = await c.buildMerkle(
    targetHeight: tip,
    saplingOutputs: [...s1.notes, ...s2.notes, ...s3.notes],
  );
  check(
    all.saplingNotes.length ==
        s1.notes.length + s2.notes.length + s3.notes.length,
    'all new notes witnessable merged (${all.saplingNotes.length})',
  );
  await c.closeContext();

  if (failures > 0) throw StateError('$failures checks FAILED');
  print('DONE: all checks passed');
}

/// Mines 101 blocks to the funder unless it already holds confirmed funds
/// (coinbase needs 100 confirmations).
Future<void> _ensureFunderFunds({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required _ZebraRpc rpc,
  required ZcashTestAccount funder,
}) async {
  final taddr = funder.uivk.defaultTransparentAddress();
  var utxos = await getAccountsConfrimedUtxos(provider, [taddr]);
  if (utxos.isNotEmpty) {
    print('funder already holds ${utxos.length} confirmed utxos');
    return;
  }
  print('mining 101 blocks to funder ${taddr.address} ...');
  await rpc.generateToAddress(101, taddr.address);
  final h = await rpc.getBlockCount();
  await _waitLwd(provider, h);
  utxos = await getAccountsConfrimedUtxos(provider, [taddr]);
  print('funder confirmed utxos after mining: ${utxos.length}');
  if (utxos.isEmpty) throw StateError('funder still has no mature funds');
}

/// Sends one transparent -> sapling output, retrying up to 3 times.
Future<String> _sendShieldedRetry({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZcashTestAccount from,
  required String saplingTo,
  required ZAmount amount,
}) async {
  Object? last;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      return await _sendShielded(
        context: context,
        provider: provider,
        from: from,
        saplingTo: saplingTo,
        amount: amount,
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

Future<String> _sendShielded({
  required ZcashCryptoContext context,
  required ZcashWalletdProvider provider,
  required ZcashTestAccount from,
  required String saplingTo,
  required ZAmount amount,
}) async {
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
  final merkle = DefaultMerkleController(context: context, provider: provider);
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
    activationProvider: const _ZebraRegtestActivations(),
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
}

Future<void> _waitLwd(ZcashWalletdProvider provider, int height) async {
  for (var i = 0; i < 120; i++) {
    final h = await getLatestBlockId(provider);
    if (h >= height) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw StateError('lightwalletd did not sync to $height in time');
}

/// Activation heights of the local zebra regtest chain: every upgrade,
/// including NU6.3 (Ironwood) and later, is active from height 1 — unlike
/// zcashd regtest, which tops out at NU6.2.
class _ZebraRegtestActivations extends DefaultUpgradeActivationProvider {
  const _ZebraRegtestActivations();

  @override
  int activationHeight(ZcashNetworkProtocol protocol, ZcashNetwork network) {
    if (network == ZcashNetwork.regtest &&
        protocol >= ZcashNetworkProtocol.nu6_3) {
      return 1;
    }
    return super.activationHeight(protocol, network);
  }

  @override
  ZcashNetworkProtocol protocolFromHeight(ZcashNetwork network, int height) {
    if (network == ZcashNetwork.regtest && height >= 1) {
      // Latest known protocol (tables resolve regtest to it via the
      // height-1 defaults above) — never pin an older upgrade here.
      return super.protocolFromHeight(network, height);
    }
    return super.protocolFromHeight(network, height);
  }
}

/// Minimal zebra RPC client (regtest, no auth).
class _ZebraRpc {
  final String baseUrl;
  int _id = 0;
  _ZebraRpc(this.baseUrl);

  Future<dynamic> _call(String method, List<dynamic> params) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(baseUrl));
      req.headers.set('Content-Type', 'application/json');
      req.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': ++_id,
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
      return decoded['result'];
    } finally {
      client.close();
    }
  }

  Future<List<String>> generateToAddress(int n, String addr) async {
    final r = await _call('generatetoaddress', [n, addr]);
    return List<String>.from(r as List);
  }

  Future<int> getBlockCount() async {
    final r = await _call('getblockchaininfo', []);
    return ((r as Map)['blocks'] as num).toInt();
  }
}
