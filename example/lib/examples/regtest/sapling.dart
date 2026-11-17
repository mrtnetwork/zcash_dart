// Zcash regtest: Sapling pool (shield 0.4 ZEC, read note, spend back).

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:zcash_dart/zcash.dart';

/// Amount shielded into the Sapling pool, in ZEC.
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

  print('Zcash regtest: Sapling pool');
  print(field('branch', '${net.branch.name}'));
  print(field('alice sapling', alice.saplingAddress));
  print(field('bob transparent', bob.transparentAddress.address));
  print('');

  /// ---- 1. shield -------------------------------------------------------
  var notes = await scanNotes(net, alice);

  /// The floor is per pool: a healthy Ironwood balance must not stop the
  /// Sapling pool from being topped up.
  await warmSaplingParams();
  if (BigInt.parse((double.parse(shieldFloor) * 1e8).round().toString()) >
      notes.saplingTotal) {
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
    final target = await net.height();
    final builder = TransactionBuilder(
      targetHeight: target,
      config: TransactionBuildConfigStandard(),
      context: net.context,
      network: ZcashNetwork.regtest,
      activationProvider: LightwalletdBranchActivationProvider(net.branch),
    );
    for (final utxo in spendable) {
      await builder.addTransparentSpend(TransparentSigningInput(input: utxo));
    }
    await builder.addOutput(
      target: TransactionOutputTarget.sapling(address: alice.saplingAddress),
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
    final stopwatch = Stopwatch()..start();
    await builder.proofSapling();
    final proofMs = stopwatch.elapsedMilliseconds;
    final txid = await net.send(builder);
    print(field('shield', txid.toHex()));
    print(field('  amount', '$shieldAmount ZEC'));
    print(field('  fee', '${formatAmount(fee)} ZEC'));
    print(field('  proof', '${proofMs}ms'));
    notes = await scanNotes(net, alice);
  }

  /// ---- 2. the note, as getNotes sees it ---------------------------------
  print('');
  print('notes getNotes found for alice');
  for (final note in notes.sapling) {
    print(
      field(
        '  ${formatAmount(note.note.value)}',
        'position ${note.noteCommitmentTreePosition}',
      ),
    );
  }
  if (notes.sapling.isEmpty) throw StateError('no sapling note found');

  /// ---- 3. unshield -----------------------------------------------------
  final tip = await net.height();
  final merkle = await merkleState(net);
  final built = await buildMerkle(
    merkle,
    notes,
    targetHeight: tip,
    sapling: true,
  );
  print('');
  print(field('merkle state', 'native (Rust) builder'));
  print(field('  sapling notes', '${built.saplingNotes.length}'));
  print(field('  anchor', '${built.saplingAnchor}'));

  await net.syncBranch();
  final builder = TransactionBuilder(
    targetHeight: tip,
    config: TransactionBuildConfigStandard(sapling: built.saplingAnchor),
    context: net.context,
    network: ZcashNetwork.regtest,
    activationProvider: LightwalletdBranchActivationProvider(net.branch),
  );
  for (final input in built.saplingNotes) {
    await builder.addSaplingSpend(
      fvk: alice.saplingFvkFull,
      note: input.output.note,
      merklePath: input.merklePath,
    );
  }

  /// Never try to send more than half the note: the other half stays as the
  /// shielded change.
  final sendable =
      built.saplingNotes.first.output.note.value.value ~/ BigInt.two;
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
    target: TransactionOutputTarget.sapling(address: alice.saplingAddress),
  );

  for (final i in built.saplingNotes.indexed) {
    await builder.setSaplingProofGenerationKey(
      index: i.$1,
      expsk: alice.saplingSk,
    );
  }
  final spendProof = Stopwatch()..start();
  await builder.proofSapling();
  final spendProofMs = spendProof.elapsedMilliseconds;
  for (final i in built.saplingNotes.indexed) {
    await builder.signSapling(index: i.$1, ask: alice.saplingSk.ask);
  }
  final txid = await net.send(builder);

  print('');
  print(field('unshield', txid.toHex()));
  print(field('  amount', '${formatZec(sendAmount)} ZEC to bob'));
  print(field('  fee', '${formatAmount(fee)} ZEC'));
  print(field('  spend proof', '${spendProofMs}ms'));

  /// ---- 4. what is left -------------------------------------------------
  final after = await scanNotes(net, alice);
  print('');
  print('notes after the spend');
  for (final note in after.sapling) {
    print(
      field(
        '  ${formatAmount(note.note.value)}',
        'position ${note.noteCommitmentTreePosition}',
      ),
    );
  }
  final change = after.sapling.fold<BigInt>(
    BigInt.zero,
    (p, c) => p + c.note.value.value,
  );
  print(field('  shielded total', '${formatZec(change)} ZEC'));

  net.close();
  print('');
  print('done.');
}
