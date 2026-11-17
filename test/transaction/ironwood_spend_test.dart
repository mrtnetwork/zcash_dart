import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

import '../utils.dart';
import '../merkle/native_ironwood_test.dart' show FakeHwProvider;

void ironwoodSpendTest() {
  ZcashTestApi.runTest(_run, 'Ironwood spends');
}

void main() {
  ZcashTestApi.runTest(ironwoodSpendTest, 'Ironwood spends');
}

const int target = 3428144; // mainnet NU6.3 active

({OrchardSpendingKey sk, OrchardFullViewingKey fvk}) _key(
  DefaultZcashCryptoContext context,
) {
  final d = OrchardUtils.createDummySpendKey();
  return (sk: d.sk, fvk: d.fvk);
}

OrchardAddress _addr(
  DefaultZcashCryptoContext context,
  OrchardFullViewingKey fvk,
) => fvk.addressAt(
  j: DiversifierIndex.zero(),
  context: context,
  scope: Bip44Changes.chainExt,
);

OrchardNote _note(
  DefaultZcashCryptoContext context,
  OrchardAddress to,
  int value, {
  OrchardNoteVersion version = OrchardNoteVersion.v2,
}) {
  final rho = OrchardRho(PallasFp.random().toBytes());
  return OrchardNote.build(
    recipient: to,
    value: ZAmount.from(value),
    rseed: OrchardNoteRandomSeed.random(rho),
    rho: rho,
    context: context,
    version: version,
  );
}

OrchardScannedOutput _out(OrchardNote n, int pos) => OrchardScannedOutput(
  index: 0,
  ephemeralKey: EphemeralKeyBytes.random(),
  note: n,
  noteCommitmentTreePosition: LeafPosition(pos),
);

ScannedBlock _block(
  int id,
  List<OrchardNote> orchard,
  List<OrchardNote> ironwood,
  DefaultZcashCryptoContext context,
) {
  ScannedBlockCommitment<OrchardMerkleHash> c(OrchardNote n) =>
      ScannedBlockCommitment(
        node: OrchardMerkleHash.fromBytes(
          n.commitment(context).toExtractedNoteCommitment().inner.toBytes(),
        ),
        retention: RetentionEphemeral<int>(),
      );
  return ScannedBlock(
    blockId: id,
    timestamp: 0,
    blockhash: null,
    saplingNullifiers: const [],
    orchardNullifiers: const [],
    bundles: ScannedBlockBundles(
      sapling: ScannedProtocolBundles<SaplingNode>(
        finalTreeSize: 0,
        commitments: const [],
      ),
      orchard: ScannedProtocolBundles<OrchardMerkleHash>(
        finalTreeSize: orchard.length,
        commitments: orchard.map(c).toList(),
      ),
      ironwood: ScannedProtocolBundles<OrchardMerkleHash>(
        finalTreeSize: ironwood.length,
        commitments: ironwood.map(c).toList(),
      ),
    ),
  );
}

bool _requireNative() {
  if (blockchainUtils.backend == null) {
    markTestSkipped('ironwood proving needs the Rust backend (ffi/wasm).');
    return false;
  }
  return true;
}

void _run() {
  test('A: v2 spend + orchard change', () async {
    if (!_requireNative()) return;
    final context = DefaultZcashCryptoContext.lazy();
    final sender = _key(context);
    final note = _note(context, _addr(context, sender.fvk), 15000);
    final controller = NativeMerkleController(
      context: context,
      provider: FakeHwProvider(),
    );
    try {
      await controller.updateState([
        _block(target, [note], const [], context),
      ]);
      final sout = _out(note, 0);
      final merkleOut = await controller.buildMerkle(
        targetHeight: target,
        orchardOutputs: [sout],
      );
      final builder = TransactionBuilder(
        targetHeight: target,
        config: TransactionBuildConfigStandard(
          sapling: merkleOut.saplingAnchor,
          orchard: merkleOut.orchardAnchor,
          ironwood: merkleOut.ironwoodAnchor,
        ),
        context: context,
        network: ZcashNetwork.mainnet,
      );
      final ix = await builder.addOrchardSpend(
        fvk: sender.fvk,
        note: note,
        merklePath: merkleOut.getOrchardOutput(sout).merklePath,
      );
      await builder.addOrchardChangeOutput(
        fvk: sender.fvk,
        recipient: _addr(context, sender.fvk),
        amount: ZAmount.from(10000),
        scope: Bip44Changes.chainExt,
      );
      await builder.proofSapling();
      await builder.proofOrchard();
      await builder.proofIronwood();
      await builder.signOrchard(
        index: ix,
        ask: RedPallasSpendPrivateKey.fromSpendingKey(sender.sk),
      );
      await builder.signOrchardChange(
        changeIndex: 0,
        ask: RedPallasSpendPrivateKey.fromSpendingKey(sender.sk),
      );
      final _ = await builder.extractTransaction();
    } finally {
      await controller.closeContext();
    }
  });

  test('B: v2 spend + ironwood output (no change)', () async {
    if (!_requireNative()) return;
    final context = DefaultZcashCryptoContext.lazy();
    final sender = _key(context);
    final ext = _key(context);
    final note = _note(context, _addr(context, sender.fvk), 15000);
    final controller = NativeMerkleController(
      context: context,
      provider: FakeHwProvider(),
    );
    try {
      await controller.updateState([
        _block(target, [note], const [], context),
      ]);
      final sout = _out(note, 0);
      final merkleOut = await controller.buildMerkle(
        targetHeight: target,
        orchardOutputs: [sout],
      );
      final builder = TransactionBuilder(
        targetHeight: target,
        config: TransactionBuildConfigStandard(
          sapling: merkleOut.saplingAnchor,
          orchard: merkleOut.orchardAnchor,
          ironwood: merkleOut.ironwoodAnchor,
        ),
        context: context,
        network: ZcashNetwork.mainnet,
      );
      final ix = await builder.addOrchardSpend(
        fvk: sender.fvk,
        note: note,
        merklePath: merkleOut.getOrchardOutput(sout).merklePath,
      );
      await builder.addOutput(
        target: IronwoodOutputTarget(orchardAddress: _addr(context, ext.fvk)),
        amount: ZAmount.from(10000),
      );
      await builder.proofSapling();
      await builder.proofOrchard();
      await builder.proofIronwood();
      await builder.signOrchard(
        index: ix,
        ask: RedPallasSpendPrivateKey.fromSpendingKey(sender.sk),
      );
      final _ = await builder.extractTransaction();
    } finally {
      await controller.closeContext();
    }
  });

  test('D: v2 spend + ironwood change (no external output)', () async {
    if (!_requireNative()) return;
    final context = DefaultZcashCryptoContext.lazy();
    final sender = _key(context);
    final note = _note(context, _addr(context, sender.fvk), 15000);
    final controller = NativeMerkleController(
      context: context,
      provider: FakeHwProvider(),
    );
    try {
      await controller.updateState([
        _block(target, [note], const [], context),
      ]);
      final sout = _out(note, 0);
      final merkleOut = await controller.buildMerkle(
        targetHeight: target,
        orchardOutputs: [sout],
      );
      final builder = TransactionBuilder(
        targetHeight: target,
        config: TransactionBuildConfigStandard(
          sapling: merkleOut.saplingAnchor,
          orchard: merkleOut.orchardAnchor,
          ironwood: merkleOut.ironwoodAnchor,
        ),
        context: context,
        network: ZcashNetwork.mainnet,
      );
      final ix = await builder.addOrchardSpend(
        fvk: sender.fvk,
        note: note,
        merklePath: merkleOut.getOrchardOutput(sout).merklePath,
      );
      await builder.addIronwoodChangeOutput(
        fvk: sender.fvk,
        recipient: _addr(context, sender.fvk),
        amount: ZAmount.from(10000),
        scope: Bip44Changes.chainExt,
      );
      await builder.proofSapling();
      await builder.proofOrchard();
      await builder.proofIronwood();
      await builder.signOrchard(
        index: ix,
        ask: RedPallasSpendPrivateKey.fromSpendingKey(sender.sk),
      );
      final _ = await builder.extractTransaction();
    } finally {
      await controller.closeContext();
    }
  });

  test('E: v2 spend + ironwood output + ironwood change', () async {
    if (!_requireNative()) return;
    final context = DefaultZcashCryptoContext.lazy();
    final sender = _key(context);
    final ext = _key(context);
    final note = _note(context, _addr(context, sender.fvk), 15000);
    final controller = NativeMerkleController(
      context: context,
      provider: FakeHwProvider(),
    );
    try {
      await controller.updateState([
        _block(target, [note], const [], context),
      ]);
      final sout = _out(note, 0);
      final merkleOut = await controller.buildMerkle(
        targetHeight: target,
        orchardOutputs: [sout],
      );
      final builder = TransactionBuilder(
        targetHeight: target,
        config: TransactionBuildConfigStandard(
          sapling: merkleOut.saplingAnchor,
          orchard: merkleOut.orchardAnchor,
          ironwood: merkleOut.ironwoodAnchor,
        ),
        context: context,
        network: ZcashNetwork.mainnet,
      );
      final ix = await builder.addOrchardSpend(
        fvk: sender.fvk,
        note: note,
        merklePath: merkleOut.getOrchardOutput(sout).merklePath,
      );
      await builder.addOutput(
        target: IronwoodOutputTarget(orchardAddress: _addr(context, ext.fvk)),
        amount: ZAmount.from(6000),
      );
      await builder.addIronwoodChangeOutput(
        fvk: sender.fvk,
        recipient: _addr(context, sender.fvk),
        amount: ZAmount.from(4000),
        scope: Bip44Changes.chainExt,
      );
      await builder.proofSapling();
      await builder.proofOrchard();
      await builder.proofIronwood();
      await builder.signOrchard(
        index: ix,
        ask: RedPallasSpendPrivateKey.fromSpendingKey(sender.sk),
      );
      final _ = await builder.extractTransaction();
    } finally {
      await controller.closeContext();
    }
  });

  test('C: v3 ironwood spend + ironwood output', () async {
    if (!_requireNative()) return;
    final context = DefaultZcashCryptoContext.lazy();
    final sender = _key(context);
    final ext = _key(context);
    final note = _note(
      context,
      _addr(context, sender.fvk),
      15000,
      version: OrchardNoteVersion.v3,
    );
    final controller = NativeMerkleController(
      context: context,
      provider: FakeHwProvider(),
    );
    try {
      await controller.updateState([
        _block(target, const [], [note], context),
      ]);
      final sout = _out(note, 0);
      final merkleOut = await controller.buildMerkle(
        targetHeight: target,
        ironwoodOutputs: [sout],
      );
      final builder = TransactionBuilder(
        targetHeight: target,
        config: TransactionBuildConfigStandard(
          sapling: merkleOut.saplingAnchor,
          orchard: merkleOut.orchardAnchor,
          ironwood: merkleOut.ironwoodAnchor,
        ),
        context: context,
        network: ZcashNetwork.mainnet,
      );
      final ix = await builder.addIronwoodSpend(
        fvk: sender.fvk,
        note: note,
        merklePath: merkleOut.getIronwoodOutput(sout).merklePath,
      );
      await builder.addOutput(
        target: IronwoodOutputTarget(orchardAddress: _addr(context, ext.fvk)),
        amount: ZAmount.from(10000),
      );
      await builder.proofSapling();
      await builder.proofOrchard();
      await builder.proofIronwood();
      await builder.signIronwood(
        index: ix,
        ask: RedPallasSpendPrivateKey.fromSpendingKey(sender.sk),
      );
      final _ = await builder.extractTransaction();
    } finally {
      await controller.closeContext();
    }
  });
}
