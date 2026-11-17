import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';

/// Step-by-step probe of what happens to the merkle tree after each
/// out-of-order update. Prints checkpoints and tries buildMerkle after
/// each step.
///
/// Usage:
///   LWD_PORT=9071 dart run lib/examples/transfer/out_of_order_steps.dart
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

  Future<List<ScannedBlock>> scan(int from, int to) async {
    final scanner = DefaultZcashBlockScanner(
      config: ZcashBlockProcessorConfig(
        network: ZcashNetwork.regtest,
        context: context,
        orchardViewKeys: [orchardKey],
        saplingViewKeys: [saplingKey],
      ),
      provider: provider,
    );
    final blocks = <ScannedBlock>[];
    await for (final b in scanner.scanBlock(from, to)) {
      blocks.add(b);
    }
    return blocks;
  }

  final all = await scan(1, 300);
  final outputs =
      all
          .expand((b) => b.txes)
          .expand((t) => t.scannedOutputs())
          .map((e) => e.output)
          .toList();
  print('Total outputs found: ${outputs.length}');
  for (final o in outputs) {
    if (o is SaplingScannedOutput) {
      print(
        '  sapling: height=${o.noteCommitmentTreePosition.position}, value=${o.note.value}',
      );
    } else if (o is OrchardScannedOutput) {
      print(
        '  orchard: height=${o.noteCommitmentTreePosition.position}, value=${o.note.value}',
      );
    }
  }
  final saplingOutputs = outputs.whereType<SaplingScannedOutput>().toList();
  final orchardOutputs = outputs.whereType<OrchardScannedOutput>().toList();
  print(
    'Sapling notes: ${saplingOutputs.length}, Orchard notes: ${orchardOutputs.length}',
  );

  Future<void> probe(String label, DefaultMerkleController c) async {
    final tree = await c.getSaplingShardTree();
    final cps =
        tree.store.getCheckpoints()..sort((a, b) => a.key.compareTo(b.key));
    final txt = cps
        .map((e) => '${e.key}@${e.value.position()?.position ?? 'empty'}')
        .join(' ');
    print('    checkpoints: $txt');
    try {
      final out = await c.buildMerkle(
        targetHeight: 300,
        saplingOutputs: saplingOutputs,
        orchardOutputs: orchardOutputs,
      );
      print('    $label buildMerkle: OK');
      print(
        '       sapling anchor: '
        '${BytesUtils.toHexString(out.saplingAnchor.inner.toBytes().reversed.toList())}',
      );
      print(
        '       orchard anchor: '
        '${BytesUtils.toHexString(out.orchardAnchor.inner.toBytes().reversed.toList())}',
      );
    } catch (e) {
      final msg = '$e'.split('\n').first;
      print('    $label buildMerkle: FAILED -> $msg');
    }
  }

  // The reference: a single update of 1..300.
  print('=== reference: a single update of 1..300 ===');
  final ref = DefaultMerkleController(context: context, provider: provider);
  await ref.updateState(all);
  await probe('single', ref);

  // The out-of-order sequence, probing after each step.
  print('=== step by step: 10..100 -> 200..300 -> 150..250 ===');
  final c = DefaultMerkleController(context: context, provider: provider);
  for (final range in const [(10, 100), (200, 300), (150, 250)]) {
    final blocks = await scan(range.$1, range.$2);
    print('  after update ${range.$1}..${range.$2}');
    await c.updateState(blocks);
    await probe('step ${range.$1}..${range.$2}', c);
  }
}
