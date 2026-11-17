// Zcash regtest: Orchard/Ironwood pool (shield, read note, spend to transparent).

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:zcash_dart/zcash.dart';

/// Amount shielded into the Ironwood pool, in ZEC.
const String shieldAmount = '0.4';

/// Amount unshielded back to a transparent address, in ZEC.
const String unshieldAmount = '0.1';

/// Shielded balance the example keeps topping up.
///
/// The addresses are deterministic, so a rerun inherits the previous run's
/// notes; topping up below this floor keeps the example repeatable instead of
/// slowly draining the account until the send no longer fits.
const String shieldFloor = '0.25';

Future<void> main() async {
  final net = await ZcashRegtest.connect();
  final alice = ZcashExampleAccount.fromSeed(net.context, index: 0);
  final bob = ZcashExampleAccount.fromSeed(net.context, index: 1);

  print('Zcash regtest: Orchard / Ironwood pool');
  print(
    field(
      'branch',
      '${net.branch.name} '
          '(0x${net.branch.branchId.toRadixString(16)})',
    ),
  );
  print(field('alice orchard', alice.orchardAddress));
  print('');

  /// ---- 1. the NU6.3 rule ------------------------------------------------
  print('NU6.3: the Orchard pool does not permit cross-address outputs');
  try {
    final probe = TransactionBuilder(
      targetHeight: await net.height(),
      config: TransactionBuildConfigStandard(),
      context: net.context,
      network: ZcashNetwork.regtest,
      activationProvider: LightwalletdBranchActivationProvider(net.branch),
    );
    await probe.addOutput(
      target: TransactionOutputTarget.orchard(address: bob.orchardAddress),
      amount: ZAmount.fromZec('0.01'),
    );
    await probe.proofOrchard();
    print(field('  result', 'accepted (unexpected)'));
  } on BuError catch (error) {
    print(field('  result', 'rejected'));
    print(field('  reason', error.details?['reason'] ?? error.message));
  }
  print('');

  /// ---- 2. shield into the Ironwood pool ---------------------------------
  var notes = await scanNotes(net, alice);

  /// The floor is per pool: a healthy Sapling balance must not stop the
  /// Ironwood pool from being topped up.
  await warmSaplingParams(spend: false);
  if (BigInt.parse((double.parse(shieldFloor) * 1e8).round().toString()) >
      notes.orchardTotal) {
    await ensureTransparent(
      net,
      alice,
      minZec: double.parse(shieldAmount) + 0.01,
    );
    final spendable = selectUtxos(
      await confirmedUtxos(net, [alice.transparentAddress]),
      minZec: double.parse(shieldAmount) + 0.01,
    );
    if (spendable.isEmpty) {
      throw StateError('alice has no spendable transparent output');
    }
    await net.syncBranch();
    final builder = TransactionBuilder(
      targetHeight: await net.height(),
      config: TransactionBuildConfigStandard(),
      context: net.context,
      network: ZcashNetwork.regtest,
      activationProvider: LightwalletdBranchActivationProvider(net.branch),
    );
    for (final utxo in spendable) {
      await builder.addTransparentSpend(TransparentSigningInput(input: utxo));
    }
    await builder.addOutput(
      target: IronwoodOutputTarget(address: alice.orchardAddress),
      amount: ZAmount.fromZec(shieldAmount),
    );
    final fee = await builder.addChange(
      target: TransactionOutputTarget.transparent(
        address: alice.transparentChangeAddress.address,
      ),
    );
    for (final i in spendable.indexed) {
      final sk = alice.transparentSk
          .childKey(Bip32KeyIndex(Bip44Changes.chainExt.value))
          .childKey(alice.transparentAddress.bip32Index);
      await builder.signTransparent(
        index: i.$1,
        sk: ZECPrivate.fromBip32(sk.privateKey),
      );
    }
    final proof = Stopwatch()..start();
    await builder.proofIronwood();
    final proofMs = proof.elapsedMilliseconds;
    final txid = await net.send(builder);
    print(field('shield', txid.toHex()));
    print(field('  amount', '$shieldAmount ZEC'));
    print(field('  fee', '${formatAmount(fee)} ZEC'));
    print(field('  proof', '${proofMs}ms'));
    notes = await scanNotes(net, alice);
  }

  /// ---- 3. the note, as getNotes sees it ---------------------------------
  print('');
  print('notes getNotes found for alice');
  for (final note in notes.orchard) {
    print(
      field(
        '  ${formatAmount(note.note.value)}',
        'position ${note.noteCommitmentTreePosition}',
      ),
    );
  }
  if (notes.orchard.isEmpty) throw StateError('no ironwood note found');
  print(field('  spent notes hidden', '${notes.spent.length}'));
  print('');

  /// ---- 4. unshield ------------------------------------------------------
  final tip = await net.height();
  final merkle = await merkleState(net);
  final built = await buildMerkle(
    merkle,
    notes,
    targetHeight: tip,
    ironwood: true,
  );
  print(field('merkle state', 'native (Rust) builder'));
  print(field('  ironwood notes', '${built.ironwoodNotes.length}'));

  await net.syncBranch();
  final builder = TransactionBuilder(
    targetHeight: tip,
    config: TransactionBuildConfigStandard(ironwood: built.ironwoodAnchor),
    context: net.context,
    network: ZcashNetwork.regtest,
    activationProvider: LightwalletdBranchActivationProvider(net.branch),
  );
  for (final input in built.ironwoodNotes) {
    await builder.addIronwoodSpend(
      fvk: alice.orchardFvk,
      note: input.output.note,
      merklePath: input.merklePath,
    );
  }

  /// Never try to send more than half the note: the other half stays as the
  /// shielded change.
  final sendable =
      built.ironwoodNotes.first.output.note.value.value ~/ BigInt.two;
  final wanted = BigInt.parse(
    (double.parse(unshieldAmount) * 1e8).round().toString(),
  );
  final sendAmount = sendable < wanted ? sendable : wanted;
  await builder.addOutput(
    target: TransactionOutputTarget.transparent(
      address: bob.transparentAddress.address,
    ),
    amount: ZAmount.fromZatoshi(sendAmount),
  );
  final fee = await builder.addChange(
    target: IronwoodOutputTarget(address: alice.orchardAddress),
  );

  final proof = Stopwatch()..start();
  await builder.proofIronwood();
  final proofMs = proof.elapsedMilliseconds;
  for (final i in built.ironwoodNotes.indexed) {
    await builder.signIronwood(
      index: i.$1,
      ask: RedPallasSpendPrivateKey.fromSpendingKey(alice.orchardSk),
    );
  }
  final txid = await net.send(builder);

  print('');
  print(field('unshield', txid.toHex()));
  print(field('  amount', '${formatZec(sendAmount)} ZEC to bob'));
  print(field('  fee', '${formatAmount(fee)} ZEC'));
  print(field('  proof', '${proofMs}ms'));

  final after = await scanNotes(net, alice);
  print('');
  print(field('shielded after', '${formatZec(after.total())} ZEC'));

  net.close();
  print('');
  print('done.');
}
