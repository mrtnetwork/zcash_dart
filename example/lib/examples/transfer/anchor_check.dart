import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';

/// Prints the anchor the library computes at the chain tip and compares it
/// with the anchor the node itself reports (zcash-cli z_gettreestate).
///
/// Usage:
///   LWD_PORT=9071 dart run lib/examples/transfer/anchor_check.dart
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
  await for (final b in scanner.scanBlock(1, 300)) {
    blocks.add(b);
  }
  final outputs =
      blocks
          .expand((b) => b.txes)
          .expand((t) => t.scannedOutputs())
          .map((e) => e.output)
          .toList();
  final saplingOutputs = outputs.whereType<SaplingScannedOutput>().toList();
  final orchardOutputs = outputs.whereType<OrchardScannedOutput>().toList();
  print(
    'notes: ${saplingOutputs.length} sapling, ${orchardOutputs.length} orchard',
  );

  for (final target in [299, 300]) {
    final merkle = NativeMerkleController(context: context, provider: provider);
    await merkle.updateState(blocks);
    try {
      final out = await merkle.buildMerkle(
        targetHeight: target,
        saplingOutputs: saplingOutputs,
        orchardOutputs: orchardOutputs,
      );
      print('target $target:');
      final sb = out.saplingAnchor.inner.toBytes();
      final ob = out.orchardAnchor.inner.toBytes();
      print('  sapling anchor      : ${BytesUtils.toHexString(sb)}');
      print(
        '  sapling anchor rev  : ${BytesUtils.toHexString(sb.reversed.toList())}',
      );
      print('  orchard anchor      : ${BytesUtils.toHexString(ob)}');
      print(
        '  orchard anchor rev  : ${BytesUtils.toHexString(ob.reversed.toList())}',
      );
    } catch (e) {
      print('target $target: THREW $e');
    }
  }
}
