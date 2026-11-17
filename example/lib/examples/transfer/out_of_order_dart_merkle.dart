import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';

/// Focused demo: does `merkle.dart`'s DefaultMerkleController (pure Dart,
/// no native mirror) accept an out-of-order update?
///
/// It prints, for each step, whether updateState() complained and whether
/// buildMerkle() could produce an anchor afterwards.
///
/// Usage:
///   LWD_PORT=9071 dart run lib/examples/transfer/out_of_order_dart_merkle.dart
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
  final saplingOutputs = outputs.whereType<SaplingScannedOutput>().toList();
  final orchardOutputs = outputs.whereType<OrchardScannedOutput>().toList();

  for (final continually in [false, true]) {
    print(
      '=== merkle.dart DefaultMerkleController  '
      'continually: $continually ===',
    );
    final c = DefaultMerkleController(context: context, provider: provider);
    for (final range in const [(10, 100), (200, 300), (150, 250)]) {
      final blocks = await scan(range.$1, range.$2);
      try {
        await c.updateState(blocks, continually: continually);
        print('  update ${range.$1}..${range.$2}: accepted, no error');
      } catch (e) {
        final msg = '$e';
        print('  update ${range.$1}..${range.$2}: REJECTED');
        print('     ${msg.split('\n').first}');
      }
    }
    try {
      final out = await c.buildMerkle(
        targetHeight: 300,
        saplingOutputs: saplingOutputs,
        orchardOutputs: orchardOutputs,
      );
      print('  buildMerkle: OK (anchor computed)');
      print(
        '     sapling paths: ${out.saplingNotes.length}, '
        'orchard paths: ${out.orchardNotes.length}',
      );
    } catch (e) {
      final msg = '$e';
      print('  buildMerkle: FAILED');
      print('     ${msg.split('\n').first}');
    }
    print('');
  }
}
