import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/value/value.dart';

import '../utils.dart';

void saplingBuilderTest() {
  test("Sapling transaction builder", () async {
    final context = DefaultZcashCryptoContext.lazy();
    final extendedKey = SaplingExtendedSpendingKey.master(
      QuickCrypto.generateRandom(),
    );
    final fv = extendedKey.toExtendedFvk().toDiversifiableFullViewingKey();
    final value = ZAmount.from(15000);
    final fvk = fv.fvk;
    final ovk = fv.toOvk(Bip44Changes.chainExt);
    final recipient = fv.defaultAddress();
    final change = fv.changeAddress();
    final rseed = SaplingRSeedAfterZip212(QuickCrypto.generateRandom());
    final note = SaplingNote(
      recipient: recipient.$1,
      value: value,
      rseed: rseed,
    );
    final tree = SaplingShardTree(SaplingShardStore(context.saplingHashable()));
    final leaf = SaplingNode.fromCmu(note.cmu(context));
    tree.append(
      value: leaf,
      retention: RetentionCheckpoint(marking: MarkingState.marked, id: 0),
    );
    final root = tree.rootAtCheckpointId(0)!;
    final position = tree.maxLeafPosition()!;
    final sMerkle =
        tree.witnessAtCheckpointId(position: position, checkpointId: 0)!;

    expect(
      root.inner,
      sMerkle
          .root(
            SaplingNode.fromCmu(note.cmu(context)),
            context.saplingHashable(),
          )
          .inner,
    );
    final builder = SaplingBuilder(
      anchor: SaplingAnchor(root.inner),
      bundleType: SaplingBundleType.defaultBundle(),
      context: context,
    );
    builder.addSpend(fvk: fvk, note: note, merklePath: sMerkle);
    builder.addOutput(
      recipient: recipient.$1,
      value: ZAmount.from(10000),
      memo: List<int>.filled(512, 0),
    );
    builder.addOutput(
      ovk: ovk,
      recipient: change.$1,
      value: ZAmount.from(5000),
      memo: List<int>.filled(512, 0),
    );
    final valueBalance = builder.valueBalance();
    expect(valueBalance, ZAmount.zero());
    final pcztBundle = builder.toPczt();

    final sighash = List<int>.filled(32, 0);
    await pcztBundle.bundle.finalize(sighash: sighash, context: context);
    pcztBundle.bundle.setProofGenerationKey(
      0,
      SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(extendedKey.sk),
    );
    for (final i in pcztBundle.bundle.spends) {
      i.verifyCv();
      i.verifyNullifier(context);
      i.verifyRk();
    }
    expect(pcztBundle.bundle.spends.length, 1);
    expect(pcztBundle.bundle.outputs.length, 2);
    pcztBundle.bundle.setSpendProof(
      0,
      GrothProofBytes(List<int>.filled(GrothProofBytes.grothProofSize, 0)),
    );
    pcztBundle.bundle.setOutputProof(
      1,
      GrothProofBytes(List<int>.filled(GrothProofBytes.grothProofSize, 0)),
    );
    pcztBundle.bundle.setOutputProof(
      0,
      GrothProofBytes(List<int>.filled(GrothProofBytes.grothProofSize, 0)),
    );
    await pcztBundle.bundle.spends[0].sign(
      context: context,
      sighash: sighash,
      ask: extendedKey.sk.ask,
    );

    final b = pcztBundle.bundle.extract();
    expect(b?.bundle.valueBalance, ZAmount.zero());
  });
}

void builderTest() {
  ZcashTestApi.runTest(saplingBuilderTest, "Builder");
}

void main() {
  ZcashTestApi.runTest(builderTest, "Builder");
}
