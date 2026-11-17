import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

import '../utils.dart';

/// Fake lightwalletd: latest block + empty tree state. Subtree-root RPCs
/// throw (this test stays below 2^16 leaves, so they are never called).
class FakeHwProvider
    implements
        IGrpcProvider<
          IServiceProvider,
          ZcashWalletdRequestDetails,
          BaseGRPCServiceRequestParams
        > {
  @override
  IServiceProvider get service => throw UnimplementedError();

  @override
  Future<RESULT> request<RESULT, SERVICERESPONSE>(
    IServiceRequest<RESULT, SERVICERESPONSE, ZcashWalletdRequestDetails>
    request, {
    Duration? timeout,
  }) async {
    final msg = request as ZcashGrpcRequestMessage;
    final inner = msg.request;
    if (inner is ZWalletdGetLatestBlock) {
      return msg.onResponse(
            const ZWalletdBlockID(height: null, hash: null).toBuffer(),
          )
          as RESULT;
    }
    if (inner is ZWalletdGetTreeState) {
      return msg.onResponse(
            const ZWalletdTreeState(
              network: 'main',
              height: null,
              hash:
                  '0000000000000000000000000000000000000000000000000000000000000000',
              time: 0,
            ).toBuffer(),
          )
          as RESULT;
    }
    throw UnimplementedError('fake request ${inner.runtimeType}');
  }

  @override
  Future<SERVICERESPONSE> requestDynamic<RESULT, SERVICERESPONSE>(
    IServiceRequest<RESULT, SERVICERESPONSE, ZcashWalletdRequestDetails>
    request, {
    Duration? timeout,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<RESULT> requestStream<RESULT>(
    IGRPCServiceRequest<RESULT, BaseGRPCServiceRequestParams> request, {
    Duration? timeout,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<RESULT>> requestOnce<RESULT>(
    IGRPCServiceRequest<RESULT, BaseGRPCServiceRequestParams> request, {
    Duration? timeout,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Stream<RESULT>> requestStreamAsync<RESULT>(
    IGRPCServiceRequest<RESULT, BaseGRPCServiceRequestParams> request, {
    Duration? timeout,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<RESULT>> requestOnceAsync<RESULT>(
    IGRPCServiceRequest<RESULT, BaseGRPCServiceRequestParams> request, {
    Duration? timeout,
  }) {
    throw UnimplementedError();
  }
}

/// Real orchard notes (ironwood leaves are orchard-shaped), so buildMerkle
/// anchor checks recompute honestly.
OrchardNote _note(ZcashCryptoContext context, int v) {
  final (_, _, note) = OrchardNote.dummy(context, amount: ZAmount.from(v));
  return note;
}

List<int> _cmx(ZcashCryptoContext context, OrchardNote note) {
  return List<int>.from(
    note.commitment(context).toExtractedNoteCommitment().inner.toBytes(),
  );
}

OrchardScannedOutput _out(OrchardNote note, int pos) => OrchardScannedOutput(
  index: 0,
  ephemeralKey: EphemeralKeyBytes.random(),
  note: note,
  noteCommitmentTreePosition: LeafPosition(pos),
);

ScannedBlock _block(
  int id, {
  required ZcashCryptoContext context,
  required int ironStart,
  required List<OrchardNote> ironwood,
}) {
  ScannedBlockCommitment<OrchardMerkleHash> c(OrchardNote note) {
    return ScannedBlockCommitment(
      node: OrchardMerkleHash.fromBytes(_cmx(context, note)),
      retention: RetentionEphemeral<int>(),
    );
  }

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
        finalTreeSize: 0,
        commitments: const [],
      ),
      ironwood: ScannedProtocolBundles<OrchardMerkleHash>(
        finalTreeSize: ironStart + ironwood.length,
        commitments: ironwood.map(c).toList(),
      ),
    ),
  );
}

List<String> _limbs(OrchardMerklePath p) =>
    p.authPath
        .map((e) => BytesUtils.toHexString(List<int>.from(e.toBytes())))
        .toList();

void nativeIronwoodTest() {
  // These tests drive the native mirror through blockchainUtils.api, so
  // they run on the Rust backend (ffi/wasm) and skip visibly otherwise.
  test('ironwood leaves feed the native mirror (kind=2)', () async {
    if (blockchainUtils.backend == null) {
      markTestSkipped('native merkle needs the Rust backend (ffi/wasm).');
      return;
    }
    final context = DefaultZcashCryptoContext.lazy();
    final oA = _note(context, 100);
    final oB = _note(context, 200);
    final oC = _note(context, 300);
    NativeMerkleController make() =>
        NativeMerkleController(context: context, provider: FakeHwProvider());

    final c = make();
    // Previously threw "no native mirror yet"; now appends to kind=2.
    final report = await c.updateState([
      _block(1, context: context, ironStart: 0, ironwood: [oA, oB]),
    ]);
    expect(report, isNotNull);
    expect(report!.finalIronwoodTree, 2);

    final before = await c.buildMerkle(
      targetHeight: 1,
      ironwoodOutputs: [_out(oA, 0), _out(oB, 1)],
    );
    expect(before.ironwoodNotes, hasLength(2));

    // The journal inside NativeMerkleState restores the mirror: a new
    // controller from the serialized state keeps appending seamlessly.
    final bytes = await c.serialize();
    expect(bytes, isNotEmpty);
    final persisted = NativeMerkleState.deserialize(bytes: bytes);
    expect(persisted.journal.ironwood.leaves.length, 2 * 32);
    final c2 = NativeMerkleController.fromState(
      context: context,
      provider: FakeHwProvider(),
      state: persisted,
    );
    final report2 = await c2.updateState([
      _block(2, context: context, ironStart: 2, ironwood: [oC]),
    ]);
    expect(report2, isNotNull);
    final bytes2 = await c2.serialize();
    expect(
      NativeMerkleState.deserialize(
        bytes: bytes2,
      ).journal.ironwood.leaves.length,
      3 * 32,
    );

    // Pre-restore witnesses are bit-identical after restore + continuation.
    final after = await c2.buildMerkle(
      targetHeight: 1,
      ironwoodOutputs: [_out(oA, 0), _out(oB, 1)],
    );
    expect(
      BytesUtils.toHexString(List<int>.from(after.ironwoodAnchor.toBytes())),
      BytesUtils.toHexString(List<int>.from(before.ironwoodAnchor.toBytes())),
    );
    expect(
      _limbs(after.ironwoodNotes.first.merklePath),
      _limbs(before.ironwoodNotes.first.merklePath),
    );
    // And the new note is witnessable at the new tip.
    final tip = await c2.buildMerkle(
      targetHeight: 2,
      ironwoodOutputs: [_out(oA, 0), _out(oB, 1), _out(oC, 2)],
    );
    expect(tip.ironwoodNotes, hasLength(3));
    await c.closeContext();
    await c2.closeContext();
  });

  test('diverged ironwood scan throws; mirror stays consistent', () async {
    if (blockchainUtils.backend == null) {
      markTestSkipped('native merkle needs the Rust backend (ffi/wasm).');
      return;
    }
    final context = DefaultZcashCryptoContext.lazy();
    final oA = _note(context, 100);
    final oB = _note(context, 200);
    final oEvil = _note(context, 9999);
    final c = NativeMerkleController(
      context: context,
      provider: FakeHwProvider(),
    );
    await c.updateState([
      _block(1, context: context, ironStart: 0, ironwood: [oA]),
    ]);
    final bytes = await c.serialize();
    final persisted = NativeMerkleState.deserialize(bytes: bytes);
    final c2 = NativeMerkleController.fromState(
      context: context,
      provider: FakeHwProvider(),
      state: persisted,
    );
    // Genuine continuation works.
    final report = await c2.updateState([
      _block(2, context: context, ironStart: 1, ironwood: [oB]),
    ]);
    expect(report, isNotNull);
    // Same block id, different leaves: fail-closed.
    await expectLater(
      c2.updateState([
        _block(2, context: context, ironStart: 1, ironwood: [oEvil]),
      ]),
      throwsA(isA<BuError>()),
    );
    // Pre-divergence witnesses are unaffected.
    final got = await c2.buildMerkle(
      targetHeight: 1,
      ironwoodOutputs: [_out(oA, 0)],
    );
    expect(got.ironwoodNotes, hasLength(1));
    await c.closeContext();
    await c2.closeContext();
  });

  test('NativeMerkleState round-trips subtree indices + journal', () {
    if (blockchainUtils.backend == null) {
      markTestSkipped('native merkle needs the Rust backend (ffi/wasm).');
      return;
    }
    final state = NativeMerkleState(
      journal: MirrorTipJournal(
        ironwood: PoolTipJournal(
          base: 65536,
          leaves: List<int>.filled(32, 9),
          checkpoints: {42: 65537},
        ),
      ),
      saplingSubtreeIndex: 1,
      orchardSubtreeIndex: 2,
      ironwoodSubtreeIndex: 3,
    );
    final rt = NativeMerkleState.deserialize(bytes: state.toCbor().encode());
    expect(rt.saplingSubtreeIndex, 1);
    expect(rt.orchardSubtreeIndex, 2);
    expect(rt.ironwoodSubtreeIndex, 3);
    expect(rt.journal.ironwood.base, 65536);
    expect(rt.journal.ironwood.leaves, List<int>.filled(32, 9));
    expect(rt.journal.ironwood.checkpoints, {42: 65537});
    expect(rt.journal.sapling.isEmpty, isTrue);
  });
}

void main() {
  ZcashTestApi.runTest(nativeIronwoodTest, "Native Ironwood");
}
