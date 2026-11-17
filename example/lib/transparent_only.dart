import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:example/examples/transfer/clinet/grpc_provider_example.dart';
import 'package:example/examples/transfer/context.dart';
import 'package:example/examples/transfer/test_account.dart';
import 'package:example/examples/transfer/utils.dart';
import 'package:zcash_dart/zcash.dart';

void main() async {
  final host = Platform.environment['LWD_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['LWD_PORT'] ?? '9067');
  final context = await getContext(libraryPath: zcashRustLibrary());
  final provider = createGrpcClient(url: host, port: port);

  final account = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(101),
  );

  final transparentAddr = account.uivk.defaultTransparentAddress();
  final allUtxos = await getAccountsConfrimedUtxos(provider, [transparentAddr]);
  final latestHeight = await getLatestBlockId(provider);
  final utxos =
      allUtxos
          .where(
            (u) => u.utxo.blockHeight > 0 && u.utxo.blockHeight <= latestHeight,
          )
          .toList();
  print(
    'Found ${utxos.length} confirmed UTXOs (of ${allUtxos.length} total, height: $latestHeight)',
  );

  final total = utxos.fold<BigInt>(
    BigInt.zero,
    (p, c) => p + c.utxo.amount.value,
  );
  print('Total amount: $total');

  if (total == BigInt.zero) {
    print('No funds available. Need to mine more blocks.');
    return;
  }

  final target = await getLatestBlockId(provider);
  print('Target height: $target');

  final builder = TransactionBuilder(
    targetHeight: target,
    config: TransactionBuildConfigStandard(),
    context: context,
    network: ZcashNetwork.regtest,
  );

  for (final utxo in utxos) {
    await builder.addTransparentSpend(TransparentSigningInput(input: utxo));
  }

  final account2 = ZcashTestAccount.fromSeed(
    context,
    accountIndex: Bip32KeyIndex.hardenIndex(102),
  );
  await builder.addOutput(
    target: TransactionOutputTarget.transparent(
      address: account2.uivk.defaultTransparentAddress().address,
    ),
    amount: ZAmount.from(1000),
  );

  await builder.addChange(
    target: TransactionOutputTarget.transparent(
      address: account.uivkInternal.defaultAddress().address,
    ),
  );

  final transparentAccounts =
      <TransparentDerivedAddress, (ZcashTestAccount, Bip44Changes)>{
        transparentAddr: (account, Bip44Changes.chainExt),
      };

  for (final i in utxos.indexed) {
    final acc = transparentAccounts.entries.firstWhere(
      (e) => e.key.address == i.$2.ownerDetails.address.address,
    );

    final sk = acc.value.$1.transparentSk
        .childKey(Bip32KeyIndex(acc.value.$2.value))
        .childKey(acc.key.bip32Index);

    await builder.signTransparent(
      index: i.$1,
      sk: ZECPrivate.fromBip32(sk.privateKey),
    );
  }

  final txId = await builder.extractAndSendTransaction(provider);
  print('Transaction sent! TXID: $txId');
}
