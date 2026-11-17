// Zcash regtest: transparent pool (fund, read UTXOs, spend with change).

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:zcash_dart/zcash.dart';

/// Amount sent from alice to bob, in ZEC.
const String sendAmount = '0.1';

Future<void> main() async {
  final net = await ZcashRegtest.connect();
  final alice = ZcashExampleAccount.fromSeed(net.context, index: 0);
  final bob = ZcashExampleAccount.fromSeed(net.context, index: 1);

  print('Zcash regtest: transparent pool');
  print(field('lightwalletd', '$zcashLightwalletdHost:$zcashLightwalletdPort'));
  print(field('branch', '${net.branch.name}'));
  print(field('alice', alice.transparentAddress.address));
  print(field('bob', bob.transparentAddress.address));
  print('');

  /// ---- 1. fund ---------------------------------------------------------
  final from = await net.height();
  var utxos = await confirmedUtxos(net, [alice.transparentAddress]);
  final balance = utxos.fold<BigInt>(
    BigInt.zero,
    (p, c) => p + c.utxo.amount.value,
  );
  final wanted = double.parse(sendAmount) + 0.01;
  if (balance < BigInt.from((wanted * 1e8).round())) {
    await ensureTransparent(net, alice, minZec: wanted);
    utxos = await confirmedUtxos(net, [alice.transparentAddress]);
    print(
      field(
        'mined',
        '$zcashFundingBlocks blocks to alice '
            '(height ${from + 1}..${await net.height()})',
      ),
    );
  }

  /// The fewest, largest utxos that cover the payment: the fee grows with the
  /// number of inputs, so sweeping in every dust output would eat the change.
  final available = utxos.length;
  utxos = selectUtxos(utxos, minZec: wanted);
  print('utxos alice can spend');
  for (final utxo in utxos.take(5)) {
    print(
      field(
        '  ${formatZec(utxo.utxo.amount.value)}',
        'height ${utxo.utxo.blockHeight}',
      ),
    );
  }
  if (utxos.length > 5) {
    print(field('  ...', '${utxos.length - 5} more'));
  }
  final total = utxos.fold<BigInt>(
    BigInt.zero,
    (p, c) => p + c.utxo.amount.value,
  );
  print(
    field(
      '  total',
      '${formatZec(total)} ZEC '
          '(${utxos.length} of $available utxos)',
    ),
  );
  if (utxos.isEmpty) throw StateError('alice has no spendable output');
  print('');

  /// ---- 2. spend --------------------------------------------------------
  await net.syncBranch();
  final target = await net.height();
  final builder = TransactionBuilder(
    targetHeight: target,
    config: TransactionBuildConfigStandard(),
    context: net.context,
    network: ZcashNetwork.regtest,
    activationProvider: LightwalletdBranchActivationProvider(net.branch),
  );
  for (final utxo in utxos) {
    await builder.addTransparentSpend(TransparentSigningInput(input: utxo));
  }
  await builder.addOutput(
    target: TransactionOutputTarget.transparent(
      address: bob.transparentAddress.address,
    ),
    amount: ZAmount.fromZec(sendAmount),
  );
  final fee = await builder.addChange(
    target: TransactionOutputTarget.transparent(
      address: alice.transparentChangeAddress.address,
    ),
  );

  /// Each input is signed with the key derived at its own BIP-32 index.
  for (final i in utxos.indexed) {
    final address = alice.transparentAddress;
    final sk = alice.transparentSk
        .childKey(Bip32KeyIndex(Bip44Changes.chainExt.value))
        .childKey(address.bip32Index);
    await builder.signTransparent(
      index: i.$1,
      sk: ZECPrivate.fromBip32(sk.privateKey),
    );
  }

  final txid = await net.send(builder);
  print(field('tx', txid.toHex()));
  print(field('fee', '${formatAmount(fee)} ZEC'));
  print('');

  /// ---- 3. read back ----------------------------------------------------
  final bobUtxos = await confirmedUtxos(net, [
    bob.transparentAddress,
  ], requiredConfirmations: 1);
  final newest =
      bobUtxos.isEmpty
          ? null
          : bobUtxos.reduce(
            (a, b) => a.utxo.blockHeight > b.utxo.blockHeight ? a : b,
          );
  print(field('bob utxos', '${bobUtxos.length}'));
  if (newest != null) {
    print(
      field(
        '  newest',
        '${formatZec(newest.utxo.amount.value)} ZEC '
            'at height ${newest.utxo.blockHeight}',
      ),
    );
  }

  net.close();
  print('');
  print('done.');
}
