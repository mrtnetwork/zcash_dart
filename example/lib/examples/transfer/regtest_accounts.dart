import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:zcash_dart/zcash.dart';

/// Derives the local test accounts used by the transfer example and prints
/// the addresses that need funding on the regtest chain.
///
/// Usage:
///   dart run lib/examples/transfer/regtest_accounts.dart
Future<void> main() async {
  final context = await getContext(libraryPath: zcashRustLibrary());
  print('crypto context ready');

  for (final index in [101, 102, 103]) {
    final account = ZcashTestAccount.fromSeed(
      context,
      accountIndex: Bip32KeyIndex.hardenIndex(index),
    );
    final ua = account.uivk.defaultAddress();
    final sapling = ZcashUnifiedAddress.fromReceivers(
      receivers: [ua.sapling!],
      network: ZcashNetwork.regtest,
    );
    final orchard = ZcashUnifiedAddress.fromReceivers(
      receivers: [ua.orchard!],
      network: ZcashNetwork.regtest,
    );
    print('--- account $index ---');
    print(
      'transparent (defaultTransparentAddress) : '
      '${account.uivk.defaultTransparentAddress().address}',
    );
    print(
      'transparent (defaultAddress.transparent) : ${ua.transparent?.address}',
    );
    print('sapling     : ${sapling.address}');
    print('orchard     : ${orchard.address}');
    print('unified     : ${ua.address}');
  }
}
