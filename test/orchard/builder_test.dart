import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/orchard/builder/builder.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/pczt/pczt.dart';
import 'package:zcash_dart/src/value/value.dart';

void main() {
  _test();
}

Future<void> _test() async {
  test(
    "Orchard transaction builder",
    () async {
      final context = DefaultZCashCryptoContext.lazy();
      QuickCrypto.setupPRNG(ChaCha20Rng(List<int>.filled(32, 12)));
      final dummy = OrchardUtils.createDummySpendKey();
      final sk = dummy.sk;
      final fvk = dummy.fvk;
      final recipient = fvk.addressAt(
          j: DiversifierIndex.zero(),
          context: context,
          scope: Bip44Changes.chainExt);
      final value = ZAmount.from(15000);
      final note =
          createNote(context: context, recipient: recipient, value: value);
      final merkle = buildMerkle(note: note, context: context);
      final builder = OrchardBuilder(
          bundleType: OrchardBundleType.defaultBundle(),
          anchor: merkle.anchor,
          context: context);
      builder.addSpend(fvk: fvk, note: note, merklePath: merkle.merklePath);
      builder.addOutput(
          recipient: recipient,
          value: ZAmount.from(10000),
          memo: List<int>.filled(512, 0));
      builder.addOutput(
          ovk: fvk.toOvk(Bip44Changes.chainInt),
          recipient: fvk.addressAt(
              j: DiversifierIndex.zero(),
              context: context,
              scope: Bip44Changes.chainInt),
          value: ZAmount.from(5000),
          memo: List<int>.filled(512, 0));
      final valueBalance = builder.valueBalance();
      expect(valueBalance, ZAmount.zero());
      final pczt = builder.toPczt();
      final sighash = List<int>.filled(32, 0);
      pczt.bundle.finalize(sighash: sighash, context: context);
      pczt.bundle.setZkProof(OrchardProof(List.filled(14592 ~/ 2, 0)));
      expect(() => pczt.bundle.extract(), throwsA(isA<PcztException>()));
      for (final action in pczt.bundle.actions) {
        if (action.spend.value == value) {
          await action.sign(
              sighash: sighash,
              ask: OrchardSpendAuthorizingKey.fromSpendingKey(sk),
              context: context);
        }
      }
      final extract = pczt.bundle.extract();
      expect(extract?.bundle.balance, ZAmount.zero());
      await extract?.buildBindingAutorization(
          sighash: sighash, context: context);
    },
  );
}

({OrchardAnchor anchor, OrchardMerklePath merklePath}) buildMerkle(
    {required OrchardNote note, required DefaultZCashCryptoContext context}) {
  final cmx = note.commitment(context).toExtractedNoteCommitment();
  final leaf = OrchardMerkleHash(cmx.inner);
  final tree = OrchardShardTree(OrchardShardStore(context.orchardHashable()));
  tree.append(
      value: leaf,
      retention: RetentionCheckpoint(marking: MarkingState.marked, id: 0));
  final root = tree.rootAtCheckpointId(0)?.toAnchor();
  final position = tree.maxLeafPosition()!;
  final oMerkle =
      tree.witnessAtCheckpointId(position: position, checkpointId: 0)!;

  expect(root, oMerkle.root(cmx: cmx, hashContext: context.orchardHashable()));
  return (anchor: root!, merklePath: oMerkle);
}

OrchardNote createNote({
  required DefaultZCashCryptoContext context,
  required OrchardAddress recipient,
  required ZAmount value,
}) {
  final rho = OrchardRho(PallasNativeFp.random());
  final seed = OrchardNoteRandomSeed.random(rho);
  return OrchardNote.build(
      recipient: recipient,
      value: value,
      rseed: seed,
      rho: rho,
      context: context);
}
