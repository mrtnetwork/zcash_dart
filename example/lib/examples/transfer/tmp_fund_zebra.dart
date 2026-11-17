import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:zcash_dart/zcash.dart';

// Funds a Sapling regtest address from the local Zebra chain's test account 101.
// Usage: dart run lib/examples/transfer/tmp_fund_zebra.dart <sapling-address> [amount=1.0]
// Env: LWD_HOST (default 127.0.0.1), LWD_PORT (default 9073), ZCASH_RUST_LIBRARY (required).
Future<void> main(List<String> args) async {
  final dest =
      args.isEmpty
          ? 'zregtestsapling17mt9shmuc5nvnxu76uc60srtfwsf0czpkja2j47dhxvmgespue08z37wfskly9ke9f6q6ehztn8'
          : args[0];
  final amountZec = args.length > 1 ? args[1] : '1.0';
  final host = Platform.environment['LWD_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9073');
  final context = await getContext(libraryPath: zcashRustLibrary());
  final provider = createGrpcClient(url: host, port: port);

  final funder = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(101),
  );
  final taddr = funder.uivk.defaultTransparentAddress();
  print('funder transparent: ${taddr.address}');
  print('destination       : $dest');
  print('amount            : $amountZec ZEC');

  final utxos = await getAccountsConfrimedUtxos(provider, [taddr]);
  print('mature utxos       : ${utxos.length}');
  if (utxos.isEmpty) {
    print(
      'ERROR: no mature UTXOs. Mine 101+ blocks to ${taddr.address} first.',
    );
    exit(2);
  }
  final target = await getLatestBlockId(provider);
  print('target height     : $target');

  // Pick enough UTXOs to cover amount + fee margin (2x amount is plenty).
  final need = BigInt.from((double.parse(amountZec) * 1e8).round());
  BigInt gathered = BigInt.zero;
  final selected = <TransparentUtxoWithOwner>[];
  for (final u in utxos) {
    selected.add(u);
    gathered += u.utxo.amount.value;
    if (gathered >= need * BigInt.from(2)) break;
  }
  print('selected ${selected.length} utxo(s), total $gathered zatoshis');

  final builder = TransactionBuilder(
    targetHeight: target,
    config: TransactionBuildConfigStandard(),
    context: context,
    network: ZcashNetwork.regtest,
  );
  for (final u in selected) {
    await builder.addTransparentSpend(TransparentSigningInput(input: u));
  }
  await builder.addOutput(
    target: TransactionOutputTarget.sapling(address: dest),
    amount: ZAmount.fromZec(amountZec),
  );
  final fee = await builder.addChange(
    target: TransactionOutputTarget.transparent(
      address: funder.uivkInternal.defaultTransparentAddress().address,
    ),
  );
  print('fee               : ${fee.value} zatoshis');

  await builder.proofSapling();
  for (final u in selected.indexed) {
    final sk = funder.transparentSk
        .childKey(Bip32KeyIndex(Bip44Changes.chainExt.value))
        .childKey(taddr.bip32Index);
    await builder.signTransparent(
      index: u.$1,
      sk: ZECPrivate.fromBip32(sk.privateKey),
    );
  }
  final txid = await builder.extractAndSendTransaction(provider);
  print('sent txid         : ${txid.toHex()}');
}
