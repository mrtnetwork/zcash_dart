import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';

/// Diagnostics for the out-of-order merkle update: prints the tree state
/// (checkpoints) after each update, for the native and the pure-Dart
/// controller.
///
/// Usage:
///   LWD_PORT=9071 dart run lib/examples/transfer/out_of_order_diag.dart
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

  void dumpDart(
    String tag,
    SaplingShardTree sapling,
    OrchardShardTree orchard,
  ) {
    final s =
        sapling.store.getCheckpoints()..sort((a, b) => a.key.compareTo(b.key));
    final o =
        orchard.store.getCheckpoints()..sort((a, b) => a.key.compareTo(b.key));
    String fmt(List<MapEntry<int, Checkpoint>> c) => c
        .map((e) => '${e.key}@${e.value.position()?.position ?? 'empty'}')
        .join(' ');
    print('    $tag sapling checkpoints : ${fmt(s)}');
    print('    $tag orchard checkpoints : ${fmt(o)}');
  }

  Future<void> dumpNative(String tag, NativeMerkleController c) async {
    final bytes = await c.serialize();
    final state = NativeMerkleState.deserialize(bytes: bytes);
    String pool(String name, PoolTipJournal p) =>
        '$name tip=${p.tipSize} base=${p.base} '
        'leaves=${p.length} checkpoints=${p.checkpoints.length}';
    print(
      '    $tag bytes=${bytes.length} '
      'sapIdx=${state.saplingSubtreeIndex} '
      'orcIdx=${state.orchardSubtreeIndex} '
      'irwIdx=${state.ironwoodSubtreeIndex}',
    );
    print('    $tag ${pool('sapling', state.journal.sapling)}');
    print('    $tag ${pool('orchard', state.journal.orchard)}');
    print('    $tag ${pool('ironwood', state.journal.ironwood)}');
  }

  print('=== native controller ===');
  final native = NativeMerkleController(context: context, provider: provider);
  for (final range in const [(10, 100), (200, 300), (150, 250)]) {
    final blocks = await scan(range.$1, range.$2);
    final last = blocks.last;
    print(
      '  update ${range.$1}..${range.$2} '
      '(orchard size ${last.bundles.orchard.finalTreeSize}, '
      'sapling size ${last.bundles.sapling.finalTreeSize}, '
      'leaves in range: orchard ${last.bundles.orchard.commitments.length}, '
      'sapling ${last.bundles.sapling.commitments.length})',
    );
    try {
      await native.updateState(blocks);
    } catch (e) {
      print('    THREW: $e');
      continue;
    }
    await dumpNative('after', native);
  }

  print('=== pure-Dart controller ===');
  final dart = DefaultMerkleController(context: context, provider: provider);
  for (final range in const [(10, 100), (200, 300), (150, 250)]) {
    final blocks = await scan(range.$1, range.$2);
    print('  update ${range.$1}..${range.$2}');
    try {
      await dart.updateState(blocks);
    } catch (e) {
      print('    THREW: $e');
      continue;
    }
    dumpDart('after', dart.getSaplingShardTree(), dart.getOrcardShardTree());
  }
}
