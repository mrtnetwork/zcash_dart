import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:zcash_dart/zcash.dart';

/// Live count experiment on the local zebra regtest (lightwalletd 9073).
///
/// Funds 7 fresh Ironwood notes, then submits a 7-action Ironwood spend
/// and a 6-action one, printing the node verdict for each. Diagnoses the
/// "7 actions fail, 6 succeed" report without touching wallet code.
///
/// Usage (from the example package):
///   LWD_PORT=9073 ZEBRA_RPC=http://127.0.0.1:18235 ZCASH_RUST_LIBRARY=<'path-to-.so> \
///   dart run lib/examples/transfer/live_ironwood_count.dart
///
/// NOTE: throwaway diagnostic script (delete after use).
Future<void> main() async {
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9073');
  final zebraRpc =
      Platform.environment['ZEBRA_RPC'] ?? 'http://127.0.0.1:18235';
  final context = await getContext(libraryPath: zcashRustLibrary());
  final provider = createGrpcClient(url: '127.0.0.1', port: port);
  final rpc = _Rpc(zebraRpc);

  final funder = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(200),
  );
  final acc = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(11),
    seed: List<int>.filled(32, 11),
  );
  final ext = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(12),
    seed: List<int>.filled(32, 12),
  );
  final funderT = funder.uivk.defaultTransparentAddress();
  print('tip=${await getLatestBlockId(provider)} funder=${funderT.address}');

  // 1. fund the transparent faucet.
  var utxos = await getAccountsConfrimedUtxos(provider, [funderT]);
  if (utxos.isEmpty) {
    print('mining 101 to funder...');
    await rpc.generateToAddress(101, funderT.address);
    await _waitLwd(provider, await rpc.getBlockCount());
    utxos = await getAccountsConfrimedUtxos(provider, [funderT]);
  }
  print('funder utxos=${utxos.length}');
  if (utxos.isEmpty) throw StateError('no mature funds');

  OrchardAddress oaddr(OrchardFullViewingKey f) => f.addressAt(
    j: DiversifierIndex.zero(),
    context: context,
    scope: Bip44Changes.chainExt,
  );

  // 2. shield N ironwood notes (NOUT env, default 7).
  final nNotes = int.parse(Platform.environment['NOUT'] ?? '7');
  const noteV = 1500000;
  {
    final target = await getLatestBlockId(provider);
    final scan = await getNotes(
      provider: provider,
      context: context,
      startHeight: 1,
      endHeight: target,
      orchard: [
        ZcashBlockProcessorScanKey(
          fvk: acc.orchardFvk,
          viewKeys:
              acc.orchardIvks
                  .map((e) => IVKWithActivationHeight(ivk: e))
                  .toList(),
        ),
      ],
    );
    final mirror = NativeMerkleController(context: context, provider: provider);
    try {
      await mirror.updateState(scan.scannedBlocks);
      final wit = await mirror.buildMerkle(
        targetHeight: target,
        ironwoodOutputs: const [],
      );
      final builder = TransactionBuilder(
        targetHeight: target,
        config: TransactionBuildConfigStandard(
          sapling: wit.saplingAnchor,
          orchard: wit.orchardAnchor,
          ironwood: wit.ironwoodAnchor,
        ),
        context: context,
        network: ZcashNetwork.regtest,
        activationProvider: const _RegtestNu63(),
      );
      for (final u in utxos.take(2)) {
        await builder.addTransparentSpend(TransparentSigningInput(input: u));
      }
      for (var i = 0; i < nNotes; i++) {
        await builder.addOutput(
          target: IronwoodOutputTarget(orchardAddress: oaddr(acc.orchardFvk)),
          amount: ZAmount.from(noteV),
        );
      }
      await builder.addChange(
        target: TransactionOutputTarget.transparent(address: funderT.address),
      );
      await builder.proofSapling();
      await builder.proofOrchard();
      await builder.proofIronwood();
      final skBase = funder.transparentSk.childKey(
        Bip32KeyIndex(Bip44Changes.chainExt.value),
      );
      final used = utxos.take(2).toList();
      for (var i = 0; i < used.length; i++) {
        final sk = skBase.childKey(funderT.bip32Index);
        await builder.signTransparent(
          index: i,
          sk: ZECPrivate.fromBip32(sk.privateKey),
        );
      }
      final txid = await builder.extractAndSendTransaction(provider);
      print('shielding tx $txid');
    } finally {
      await mirror.closeContext();
    }
  }
  final fundH = await rpc.getBlockCount();
  await rpc.generateToAddress(1, funderT.address);
  await _waitLwd(provider, fundH + 1);

  // 3. scan the new notes + build witnesses (WITH_SPEND=1 only; the
  // shielding tx must confirm first).
  if (Platform.environment['WITH_SPEND'] != '1') {
    print('done (shielding only). re-run with WITH_SPEND=1 after mining.');
    return;
  }
  final tip = await getLatestBlockId(provider);
  final scan = await getNotes(
    provider: provider,
    context: context,
    startHeight: fundH,
    endHeight: tip,
    orchard: [
      ZcashBlockProcessorScanKey(
        fvk: acc.orchardFvk,
        viewKeys:
            acc.orchardIvks
                .map((e) => IVKWithActivationHeight(ivk: e))
                .toList(),
      ),
    ],
  );
  final notes =
      scan.outputs
          .map((e) => e.output)
          .whereType<OrchardScannedOutput>()
          .toList();
  print('scanned ${notes.length} fresh ironwood notes at tip $tip');
  if (notes.length < nNotes) throw StateError('funding not visible yet');

  Future<String> spend(int n) async {
    final mirror = NativeMerkleController(context: context, provider: provider);
    try {
      await mirror.updateState(scan.scannedBlocks);
      final wit = await mirror.buildMerkle(
        targetHeight: tip,
        ironwoodOutputs: notes.take(n).toList(),
      );
      final builder = TransactionBuilder(
        targetHeight: tip,
        config: TransactionBuildConfigStandard(
          sapling: wit.saplingAnchor,
          orchard: wit.orchardAnchor,
          ironwood: wit.ironwoodAnchor,
        ),
        context: context,
        network: ZcashNetwork.regtest,
        activationProvider: const _RegtestNu63(),
      );
      final ixs = <int>[];
      for (var i = 0; i < n; i++) {
        ixs.add(
          await builder.addIronwoodSpend(
            fvk: acc.orchardFvk,
            note: notes[i].note,
            merklePath: wit.getIronwoodOutput(notes[i]).merklePath,
          ),
        );
      }
      await builder.addOutput(
        target: IronwoodOutputTarget(orchardAddress: oaddr(ext.orchardFvk)),
        amount: ZAmount.from(n * noteV - 100000),
      );
      await builder.proofSapling();
      await builder.proofOrchard();
      await builder.proofIronwood();
      for (final ix in ixs) {
        await builder.signIronwood(
          index: ix,
          ask: RedPallasSpendPrivateKey.fromSpendingKey(acc.orchardSk),
        );
      }
      try {
        final txid = await builder.extractAndSendTransaction(provider);
        return 'ACCEPTED txid=$txid';
      } catch (e) {
        return 'REJECTED: ${'$e'.split('\n').first}';
      }
    } finally {
      await mirror.closeContext();
    }
  }

  print('--- 7-action spend ---');
  print(await spend(7));
  print('--- 6-action spend ---');
  print(await spend(6));
}

/// Regtest chain fact: NU6.3 active (tip 1096), NU7 pending at 1500.
class _RegtestNu63 extends DefaultUpgradeActivationProvider {
  const _RegtestNu63();
  @override
  ZcashNetworkProtocol protocolFromHeight(ZcashNetwork network, int height) {
    if (network == ZcashNetwork.regtest) {
      return ZcashNetworkProtocol.nu6_3;
    }
    return super.protocolFromHeight(network, height);
  }
}

Future<void> _waitLwd(ZcashWalletdProvider provider, int height) async {
  for (var i = 0; i < 120; i++) {
    if (await getLatestBlockId(provider) >= height) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw StateError('lwd did not sync to $height');
}

class _Rpc {
  final String baseUrl;
  int _id = 0;
  _Rpc(this.baseUrl);
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
      final body = await (await req.close()).transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        throw StateError('RPC $method failed: ${decoded['error']}');
      }
      return decoded['result'];
    } finally {
      client.close();
    }
  }

  Future<void> generateToAddress(int n, String addr) async {
    await _call('generatetoaddress', [n, addr]);
  }

  Future<int> getBlockCount() async {
    return (((await _call('getblockchaininfo', [])) as Map)['blocks'] as num)
        .toInt();
  }
}
