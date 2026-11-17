import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';

/// Characterises what happens when the merkle tree is updated with ranges
/// that are not in ascending order, e.g. when a wallet that keeps ONE merkle
/// state per chain adds an account whose notes start at an older height.
///
///   1. update 10..100
///   2. update 200..300        (a gap: 101..199 never scanned)
///   3. update 150..250        (behind the tip, overlapping range 2)
///
/// Usage:
///   LWD_PORT=9071 dart run lib/examples/transfer/out_of_order_update.dart
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

  final notes = await scan(1, 300);
  final saplingOutputs =
      notes
          .expand((b) => b.txes)
          .expand((t) => t.scannedOutputs())
          .map((e) => e.output)
          .whereType<SaplingScannedOutput>()
          .toList();
  final orchardOutputs =
      notes
          .expand((b) => b.txes)
          .expand((t) => t.scannedOutputs())
          .map((e) => e.output)
          .whereType<OrchardScannedOutput>()
          .toList();

  // The reference: a controller that scanned the whole chain.
  final reference = NativeMerkleController(
    context: context,
    provider: provider,
  );
  await reference.updateState(notes);
  final refOut = await reference.buildMerkle(
    targetHeight: 300,
    saplingOutputs: saplingOutputs,
    orchardOutputs: orchardOutputs,
  );

  Future<void> report(
    String name,
    MerkleController controller, {
    bool continually = false,
  }) async {
    for (final range in const [(10, 100), (200, 300), (150, 250)]) {
      final blocks = await scan(range.$1, range.$2);
      try {
        await controller.updateState(blocks, continually: continually);
        print('  $name update ${range.$1}..${range.$2}: OK');
      } catch (e) {
        print('  $name update ${range.$1}..${range.$2}: THREW');
        print('     $e');
      }
    }
    try {
      final out = await controller.buildMerkle(
        targetHeight: 300,
        saplingOutputs: saplingOutputs,
        orchardOutputs: orchardOutputs,
      );
      print(
        '  $name buildMerkle: OK  '
        'saplingAnchor matches reference: '
        '${out.saplingAnchor.inner == refOut.saplingAnchor.inner}  '
        'orchardAnchor matches reference: '
        '${out.orchardAnchor.inner == refOut.orchardAnchor.inner}  '
        'paths: ${out.saplingNotes.length}/${out.orchardNotes.length}',
      );
    } catch (e) {
      print('  $name buildMerkle: THREW');
      print('     $e');
    }
  }

  print('=== A. NativeMerkleController, out-of-order ranges ===');
  await report(
    'native',
    NativeMerkleController(context: context, provider: provider),
  );

  print('=== B. pure-Dart DefaultMerkleController, same sequence ===');
  await report(
    'dart',
    DefaultMerkleController(context: context, provider: provider),
  );

  print('=== C. NativeMerkleController, continually: true ===');
  await report(
    'native(continually)',
    NativeMerkleController(context: context, provider: provider),
    continually: true,
  );

  print('=== D. the wallet scenario: tip first, then an older range ===');
  print('--- D1. native controller ---');
  final wallet = NativeMerkleController(context: context, provider: provider);
  for (final range in const [(200, 300), (100, 300)]) {
    final blocks = await scan(range.$1, range.$2);
    try {
      await wallet.updateState(blocks);
      print('  update ${range.$1}..${range.$2}: OK');
    } catch (e) {
      print('  update ${range.$1}..${range.$2}: THREW');
      print('     $e');
    }
  }
  try {
    final out = await wallet.buildMerkle(
      targetHeight: 300,
      saplingOutputs: saplingOutputs,
      orchardOutputs: orchardOutputs,
    );
    print(
      '  buildMerkle: OK  saplingAnchor matches reference: '
      '${out.saplingAnchor.inner == refOut.saplingAnchor.inner}  '
      'orchardAnchor matches reference: '
      '${out.orchardAnchor.inner == refOut.orchardAnchor.inner}',
    );
  } catch (e) {
    print('  buildMerkle: THREW');
    print('     $e');
  }

  print('--- D2. the same scenario on the pure-Dart controller ---');
  final wallet2 = DefaultMerkleController(context: context, provider: provider);
  for (final range in const [(200, 300), (100, 300)]) {
    final blocks = await scan(range.$1, range.$2);
    try {
      await wallet2.updateState(blocks);
      print('  update ${range.$1}..${range.$2}: OK');
    } catch (e) {
      print('  update ${range.$1}..${range.$2}: THREW');
      print('     $e');
    }
  }
  try {
    final out = await wallet2.buildMerkle(
      targetHeight: 300,
      saplingOutputs: saplingOutputs,
      orchardOutputs: orchardOutputs,
    );
    print(
      '  buildMerkle: OK  saplingAnchor matches reference: '
      '${out.saplingAnchor.inner == refOut.saplingAnchor.inner}  '
      'orchardAnchor matches reference: '
      '${out.orchardAnchor.inner == refOut.orchardAnchor.inner}',
    );
  } catch (e) {
    print('  buildMerkle: THREW');
    print('     $e');
  }
}
