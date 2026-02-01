import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/sapling/builder/builder.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/value/value.dart';

void main() async {
  await _test();
}

Future<void> _test() async {
  test("Sapling transaction builder", () async {
    final context = DefaultZCashCryptoContext.lazy();
    final extendedKey =
        SaplingExtendedSpendingKey.master(QuickCrypto.generateRandom());
    final fv = extendedKey.toExtendedFvk().toDiversifiableFullViewingKey();
    final value = ZAmount.from(15000);
    final fvk = fv.fvk;
    final ovk = fv.toOvk(Bip44Changes.chainExt);
    final recipient = fv.defaultAddress();
    final change = fv.changeAddress();
    final rseed = SaplingRSeedAfterZip212(QuickCrypto.generateRandom());
    final note =
        SaplingNote(recipient: recipient.$1, value: value, rseed: rseed);
    final tree = SaplingShardTree(SaplingShardStore(context.saplingHashable()));
    final leaf = SaplingNode.fromCmu(note.cmu(context));
    tree.append(
        value: leaf,
        retention: RetentionCheckpoint(marking: MarkingState.marked, id: 0));
    final root = tree.rootAtCheckpointId(0)!;
    final position = tree.maxLeafPosition()!;
    final sMerkle =
        tree.witnessAtCheckpointId(position: position, checkpointId: 0)!;

    expect(
        root.inner,
        sMerkle
            .root(SaplingNode.fromCmu(note.cmu(context)),
                context.saplingHashable())
            .inner);
    final builder = SaplingBuilder(
        anchor: SaplingAnchor(root.inner),
        bundleType: SaplingBundleType.defaultBundle(),
        context: context);
    builder.addSpend(fvk: fvk, note: note, merklePath: sMerkle);
    builder.addOutput(
        recipient: recipient.$1,
        value: ZAmount.from(10000),
        memo: List<int>.filled(512, 0));
    builder.addOutput(
        ovk: ovk,
        recipient: change.$1,
        value: ZAmount.from(5000),
        memo: List<int>.filled(512, 0));
    final valueBalance = builder.valueBalance();
    expect(valueBalance, ZAmount.zero());
    final pcztBundle = builder.toPczt();

    final sighash = List<int>.filled(32, 0);
    await pcztBundle.bundle.finalize(sighash: sighash, context: context);
    pcztBundle.bundle.setProofGenerationKey(
        0,
        SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(
            extendedKey.sk));
    for (final i in pcztBundle.bundle.spends) {
      i.verifyCv();
      i.verifyNullifier(context);
      i.verifyRk();
    }
    expect(pcztBundle.bundle.spends.length, 1);
    expect(pcztBundle.bundle.outputs.length, 2);
    pcztBundle.bundle.setSpendProof(0,
        GrothProofBytes(List<int>.filled(GrothProofBytes.grothProofSize, 0)));
    pcztBundle.bundle.setOutputProof(1,
        GrothProofBytes(List<int>.filled(GrothProofBytes.grothProofSize, 0)));
    pcztBundle.bundle.setOutputProof(0,
        GrothProofBytes(List<int>.filled(GrothProofBytes.grothProofSize, 0)));
    await pcztBundle.bundle.spends[0]
        .sign(context: context, sighash: sighash, ask: extendedKey.sk.ask);

    final b = pcztBundle.bundle.extract();
    expect(b?.bundle.valueBalance, ZAmount.zero());
  });
}

// Future<void> r() async {
//   final params = readSpendParams();
//   final outp = readOutputParams();
//   final context = DefaultZCashCryptoContext.lazy(
//     saplingProver: DefaultSaplingProver(
//         outputParams: Groth16Parameters.deserialize(outp, check: false),
//         spendParams: Groth16Parameters.deserialize(params, check: false)),
//   );
//   QuickCrypto.setupPRNG(ChaCha20Rng(List<int>.filled(32, 13)));
//   final extendedKey =
//       SaplingExtendedSpendingKey.master(QuickCrypto.generateRandom());
//   final fv = extendedKey.toExtendedFvk().toDiversifiableFullViewingKey();
//   final value = ZAmount.from(15000);
//   final fvk = fv.fvk;
//   final ovk = fv.toOvk(Bip44Changes.chainExt);
//   final recipient = fv.defaultAddress();
//   final change = fv.changeAddress();
//   final rseed = SaplingRSeedAfterZip212(QuickCrypto.generateRandom());
//   final note = SaplingNote(recipient: recipient.$1, value: value, rseed: rseed);
//   final tree = SaplingShardTree(SaplingShardStore(context.saplingHashable()));
//   final leaf = SaplingNode.fromCmu(note.cmu(context));
//   tree.append(
//       value: leaf,
//       retention: RetentionCheckpoint(marking: MarkingState.marked, id: 0));
//   final root = tree.rootAtCheckpointId(0)!;
//   final position = tree.maxLeafPosition()!;
//   final sMerkle =
//       tree.witnessAtCheckpointId(position: position, checkpointId: 0)!;

//   assert(root.inner ==
//       sMerkle
//           .root(
//               SaplingNode.fromCmu(note.cmu(context)), context.saplingHashable())
//           .inner);
//   final builder = SaplingBuilder(
//       anchor: SaplingAnchor(root.inner),
//       bundleType: SaplingBundleType.defaultBundle(),
//       context: context);
//   builder.addSpend(fvk: fvk, note: note, merklePath: sMerkle);
//   builder.addOutput(
//       recipient: recipient.$1,
//       value: ZAmount.from(10000),
//       memo: List<int>.filled(512, 0));
//   builder.addOutput(
//       ovk: ovk,
//       recipient: change.$1,
//       value: ZAmount.from(5000),
//       memo: List<int>.filled(512, 0));
//   final valueBalance = builder.valueBalance();
//   assert(valueBalance == ZAmount.zero());
//   final pcztBundle = builder.toPczt();

//   final sighash = List<int>.filled(32, 0);
//   pcztBundle.bundle.finalize(sighash: sighash, context: context);
//   pcztBundle.bundle.setProofGenerationKey(0,
//       SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(extendedKey.sk));
//   for (final i in pcztBundle.bundle.spends) {
//     i.verifyCv();
//     i.verifyNullifier(context);
//     i.verifyRk();
//   }
//   QuickCrypto.setupPRNG(ChaCha20Rng(List<int>.filled(32, 13)));
//   await pcztBundle.bundle.createProofs(context);
//   assert(pcztBundle.bundle.spends.length == 1);
//   assert(BytesUtils.bytesEqual(
//       pcztBundle.bundle.spends[0].zkproof?.inner,
//       BytesUtils.fromHexString(
//           "89add681871bb42514158fe4d61ffcd135b5faeb93cbcb1a6307911642cc1c1dcd3da1ed5fba85e38395b5043ca4e28a992a28ba9e79e2e44c7141e825d3209931cbac804d60e0142db453cb7f854070a2e837899c6e2c9f8a0c3fee7db468f7113666363199112449ea8a37a8f1f443420770cb6c22a8e7f5b81d45d1370e835798fb4b4951f520f2ef85efc176f2b28b69a6559c6dfbc85214ccb372337c67cac33b00e9d492b8eed5467c0f9b73296ca66b929e1d7076480fba3c064c780a")));
//   assert(pcztBundle.bundle.outputs.length == 2);
//   assert(BytesUtils.bytesEqual(
//       pcztBundle.bundle.outputs[0].zkproof?.inner,
//       BytesUtils.fromHexString(
//           "aa49b2ff6f90e9ef21629dcf8b359a5d75ed377e37ddd1d73c9b7ee32f9a5fab0b0cd954d2d294344f6ee1d8d9fab389a4dc8ba957fe96faeeba0446c6c92b4a5d297361f356dde87ecb62bd675990c176557512adee3321abac9572eb3cff8717ee6ab1ce59c3ee9aab869b0207eda4e2d17a431144abf67a3b58af6dbd5c8f4bdd9fc6814cff59156f12eea6cdcec7882abe2470a80ba6587fe785053582d04ced296bab7d862b8c379274aa43f55134a58e035d2c59eb89ff51c9fac61672")));
//   assert(BytesUtils.bytesEqual(
//       pcztBundle.bundle.outputs[1].zkproof?.inner,
//       BytesUtils.fromHexString(
//           "9637b80a728e418839d240c8faf9887189df443f7ef40c7e9fa85034a5cba28cf1d2863423c7dc11bfe1f7621805132b88f72e7296fafd8f34842d54c5d836bffc934ed7d2f2951e0961f3dda424e7b7d38d788fa216389fa1adff9ec54220d512d670df3489c36adfdb55b78972d19978f862f9d1f7dd69ed15e4e2764f6058115764fbd5b208438aad3b1f935b107e91e7d33a0d30de58ef77501ce93824c16d3aee8c1e88e7b7601f0f7fd339b193e6747ac34cc5184a89f01de9fd656a00")));
//   await pcztBundle.bundle.spends[0]
//       .sign(context: context, sighash: sighash, ask: extendedKey.sk.ask);
//   final b = pcztBundle.bundle.extract();
//   final vr = SaplingBundleVerification()
//       .validateBundle(bundle: b!.bundle, sighash: sighash, context: context);
// }
