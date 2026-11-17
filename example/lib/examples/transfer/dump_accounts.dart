import 'dart:convert';
import 'dart:io';

import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/zcash.dart';

/// Dumps the deterministic regtest test accounts (transparent / sapling /
/// orchard addresses) as JSON, so shell fixtures can fund them.
///
/// Usage:
///   dart run lib/examples/transfer/dump_accounts.dart > accounts.json
Future<void> main() async {
  final context = await getContext(libraryPath: zcashRustLibrary());

  final out = <String, dynamic>{};
  for (final index in [101, 102, 103]) {
    final account = ZcashTestAccount.fromSeed(
      context,
      accountIndex: Bip32KeyIndex.hardenIndex(index),
    );
    final ua = account.uivk.defaultAddress();
    out['$index'] = {
      'transparent': ua.transparent?.address,
      'transparentDefault': account.uivk.defaultTransparentAddress().address,
      'sapling':
          ZcashUnifiedAddress.fromReceivers(
            receivers: [ua.sapling!],
            network: ZcashNetwork.regtest,
          ).address,
      'orchard':
          ZcashUnifiedAddress.fromReceivers(
            receivers: [ua.orchard!],
            network: ZcashNetwork.regtest,
          ).address,
      'unified': ua.address,
    };
  }
  stdout.write(const JsonEncoder.withIndent('  ').convert(out));
}
