import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

import '../utils.dart';

/// Fake lightwalletd: latest block, empty tree state. Subtree-root RPCs
/// throw: every test below stays under 2^16 leaves with journal base 0,
/// so restores never need them (a fetch would fail the test loudly).
class _FakeProvider
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

/// Real sapling notes, so buildMerkle anchor checks recompute honestly.
class _Notes {
  final ZcashCryptoContext context;
  late final SaplingPaymentAddress recipient;
  _Notes(this.context) {
    final exsk = SaplingExtendedSpendingKey.master(
      List<int>.generate(32, (i) => i + 1),
    );
    recipient =
        exsk
            .toExtendedFvk()
            .toDiversifiableFullViewingKey()
            .defaultAddress()
            .$1;
  }

  SaplingNote note(int value) => SaplingNote(
    recipient: recipient,
    value: ZAmount.from(value),
    rseed: SaplingRSeedAfterZip212(
      List<int>.generate(32, (i) => (value * 31 + i) & 0xff),
    ),
  );

  SaplingNode cmu(SaplingNote n) => SaplingNode.fromCmu(n.cmu(context));
}

ScannedBlockCommitment<SaplingNode> _sc(
  SaplingNode node, {
  bool checkpoint = false,
  int id = 0,
  bool marked = false,
}) {
  if (marked && !checkpoint) {
    return ScannedBlockCommitment(
      node: node,
      retention: RetentionMarked<int>(),
    );
  }
  return ScannedBlockCommitment(
    node: node,
    retention:
        checkpoint
            ? RetentionCheckpoint<int>(marking: MarkingState.none, id: id)
            : RetentionEphemeral<int>(),
  );
}

ScannedBlockCommitment<OrchardMerkleHash> _oc(
  List<int> bytes, {
  bool checkpoint = false,
  int id = 0,
}) {
  return ScannedBlockCommitment(
    node: OrchardMerkleHash.fromBytes(bytes),
    retention:
        checkpoint
            ? RetentionCheckpoint<int>(marking: MarkingState.none, id: id)
            : RetentionEphemeral<int>(),
  );
}

List<int> _b(int v) => [v, ...List<int>.filled(31, 0)];

/// Blocks with explicit per-pool tips (caller tracks positions).
ScannedBlock _sizedBlock(
  int id, {
  required int sapStart,
  required List<ScannedBlockCommitment<SaplingNode>> sapling,
  int ironStart = 0,
  List<ScannedBlockCommitment<OrchardMerkleHash>> ironwood = const [],
}) {
  return ScannedBlock(
    blockId: id,
    timestamp: 0,
    blockhash: null,
    saplingNullifiers: const [],
    orchardNullifiers: const [],
    bundles: ScannedBlockBundles(
      sapling: ScannedProtocolBundles<SaplingNode>(
        finalTreeSize: sapStart + sapling.length,
        commitments: sapling,
      ),
      orchard: ScannedProtocolBundles<OrchardMerkleHash>(
        finalTreeSize: 0,
        commitments: const [],
      ),
      ironwood: ScannedProtocolBundles<OrchardMerkleHash>(
        finalTreeSize: ironStart + ironwood.length,
        commitments: ironwood,
      ),
    ),
  );
}

SaplingScannedOutput _out(SaplingNote n, int pos) => SaplingScannedOutput(
  index: 0,
  ephemeralKey: EphemeralKeyBytes.random(),
  note: n,
  noteCommitmentTreePosition: LeafPosition(pos),
);

List<String> _limbs(SaplingMerklePath p) =>
    p.authPath
        .map((e) => BytesUtils.toHexString(List<int>.from(e.toBytes())))
        .toList();

void nativeJournalRestoreTest() {
  test(
    'journal restore: contiguity + identical witnesses across restart',
    () async {
      if (blockchainUtils.backend == null) {
        markTestSkipped('native merkle needs the Rust backend (ffi/wasm).');
        return;
      }
      final context = DefaultZcashCryptoContext.lazy();
      final notes = _Notes(context);
      final nA = notes.note(1000);
      final nB = notes.note(2000);
      final nC = notes.note(3000);
      final nD = notes.note(4000);
      NativeMerkleController make() =>
          NativeMerkleController(context: context, provider: _FakeProvider());

      final a = make();
      await a.updateState([
        _sizedBlock(
          1,
          sapStart: 0,
          sapling: [
            _sc(notes.cmu(nA), marked: true),
            _sc(notes.cmu(nB), checkpoint: true, id: 1),
          ],
          ironStart: 0,
          ironwood: [_oc(_b(11), checkpoint: true, id: 1)],
        ),
        _sizedBlock(
          2,
          sapStart: 2,
          sapling: [_sc(notes.cmu(nC), checkpoint: true, id: 2)],
          ironStart: 1,
          ironwood: const [],
        ),
      ]);
      final before = await a.buildMerkle(
        targetHeight: 2,
        saplingOutputs: [_out(nA, 0)],
      );
      expect(before.saplingNotes, hasLength(1));

      // Persist: NativeMerkleState bytes only (no Dart trees anywhere).
      final bytes = await a.serialize();
      expect(bytes, isNotEmpty);
      final persisted = NativeMerkleState.deserialize(bytes: bytes);
      expect(persisted.journal.sapling.leaves.length, 3 * 32);
      expect(persisted.journal.sapling.base, 0);
      expect(persisted.journal.ironwood.leaves.length, 32);

      // Restore + keep syncing: contiguity across the restart proves the
      // journal tip is exact (the native contiguity gate would throw).
      final b = NativeMerkleController.fromState(
        context: context,
        provider: _FakeProvider(),
        state: persisted,
      );
      await b.updateState([
        _sizedBlock(
          3,
          sapStart: 3,
          sapling: [_sc(notes.cmu(nD), marked: true)],
          ironStart: 1,
          ironwood: const [],
        ),
      ]);
      // Same anchor height on both sides for an apples-to-apples witness
      // (targetHeight 2 pins the anchor at checkpoint 2 on both sides,
      // even though b also snapshotted checkpoint 3).
      final after = await b.buildMerkle(
        targetHeight: 2,
        saplingOutputs: [_out(nA, 0)],
      );
      expect(after.saplingNotes, hasLength(1));
      final beforePath = before.saplingNotes.first.merklePath;
      final afterPath = after.saplingNotes.first.merklePath;
      expect(
        BytesUtils.toHexString(List<int>.from(after.saplingAnchor.toBytes())),
        BytesUtils.toHexString(List<int>.from(before.saplingAnchor.toBytes())),
      );
      expect(afterPath.position.position, beforePath.position.position);
      expect(_limbs(afterPath), _limbs(beforePath));
      await a.closeContext();
      await b.closeContext();
    },
  );

  test('re-feeding identical leaves is a no-op (idempotent retry)', () async {
    if (blockchainUtils.backend == null) {
      markTestSkipped('native merkle needs the Rust backend (ffi/wasm).');
      return;
    }
    final context = DefaultZcashCryptoContext.lazy();
    final notes = _Notes(context);
    final nA = notes.note(1000);
    final nB = notes.note(2000);
    final c = NativeMerkleController(
      context: context,
      provider: _FakeProvider(),
    );
    ScannedBlock block1() => _sizedBlock(
      1,
      sapStart: 0,
      sapling: [
        _sc(notes.cmu(nA), marked: true),
        _sc(notes.cmu(nB), checkpoint: true, id: 1),
      ],
    );
    await c.updateState([block1()]);
    // Same batch again (e.g. retry after a crash): skipped silently.
    await c.updateState([block1()]);
    final out = await c.buildMerkle(
      targetHeight: 1,
      saplingOutputs: [_out(nA, 0)],
    );
    expect(out.saplingNotes, hasLength(1));
    // Serialized state is unchanged by the no-op re-feed.
    final bytes = await c.serialize();
    final journal = NativeMerkleState.deserialize(bytes: bytes).journal;
    expect(journal.sapling.leaves.length, 2 * 32);
    await c.closeContext();
  });

  test('re-feeding a fully covered range is a no-op', () async {
    if (blockchainUtils.backend == null) {
      markTestSkipped('native merkle needs the Rust backend (ffi/wasm).');
      return;
    }
    final context = DefaultZcashCryptoContext.lazy();
    final notes = _Notes(context);
    final nA = notes.note(1000);
    final nB = notes.note(2000);
    final nC = notes.note(3000);
    ScannedBlock block1() => _sizedBlock(
      1,
      sapStart: 0,
      sapling: [
        _sc(notes.cmu(nA), marked: true),
        _sc(notes.cmu(nB), checkpoint: true, id: 1),
      ],
    );
    ScannedBlock block2() => _sizedBlock(
      2,
      sapStart: 2,
      sapling: [_sc(notes.cmu(nC), checkpoint: true, id: 2)],
    );
    final c = NativeMerkleController(
      context: context,
      provider: _FakeProvider(),
    );
    await c.updateState([block1(), block2()]);
    final before = await c.buildMerkle(
      targetHeight: 2,
      saplingOutputs: [_out(nA, 0)],
    );
    expect(before.saplingNotes, hasLength(1));

    // Restore into a fresh controller, then feed the whole historical
    // range again (every pool batch fully covered): verify + skip.
    final bytes = await c.serialize();
    await c.closeContext();
    final r = NativeMerkleController.fromState(
      context: context,
      provider: _FakeProvider(),
      state: NativeMerkleState.deserialize(bytes: bytes),
    );
    await r.updateState([block1(), block2()]);
    final after = await r.buildMerkle(
      targetHeight: 2,
      saplingOutputs: [_out(nA, 0)],
    );
    expect(after.saplingNotes, hasLength(1));
    expect(
      BytesUtils.toHexString(List<int>.from(after.saplingAnchor.toBytes())),
      BytesUtils.toHexString(List<int>.from(before.saplingAnchor.toBytes())),
    );
    expect(
      _limbs(after.saplingNotes.first.merklePath),
      _limbs(before.saplingNotes.first.merklePath),
    );
    // Serialized state is unchanged by the no-op re-feed.
    final bytes2 = await r.serialize();
    expect(
      NativeMerkleState.deserialize(bytes: bytes2).journal.sapling.leaves,
      NativeMerkleState.deserialize(bytes: bytes).journal.sapling.leaves,
    );
    await r.closeContext();
  });

  test('diverged scan throws fail-closed (gap + reorg)', () async {
    if (blockchainUtils.backend == null) {
      markTestSkipped('native merkle needs the Rust backend (ffi/wasm).');
      return;
    }
    final context = DefaultZcashCryptoContext.lazy();
    final notes = _Notes(context);
    final nA = notes.note(1000);
    final nB = notes.note(2000);
    final nC = notes.note(3000);
    final c = NativeMerkleController(
      context: context,
      provider: _FakeProvider(),
    );
    await c.updateState([
      _sizedBlock(
        1,
        sapStart: 0,
        sapling: [
          _sc(notes.cmu(nA), marked: true),
          _sc(notes.cmu(nB), checkpoint: true, id: 1),
        ],
      ),
    ]);
    // Gap: block 3 while block 2 was never fed.
    await expectLater(
      c.updateState([
        _sizedBlock(
          3,
          sapStart: 2,
          sapling: [_sc(notes.cmu(nC), checkpoint: true, id: 3)],
        ),
      ]),
      throwsA(
        isA<BuError>().having(
          (e) => e.details?['diverged'],
          'diverged',
          'true',
        ),
      ),
    );
    // Reorg: same block id, different leaves at the same positions.
    await c.updateState([
      _sizedBlock(
        2,
        sapStart: 2,
        sapling: [_sc(notes.cmu(nC), checkpoint: true, id: 2)],
      ),
    ]);
    final nEvil = notes.note(9999);
    await expectLater(
      c.updateState([
        _sizedBlock(
          2,
          sapStart: 2,
          sapling: [_sc(notes.cmu(nEvil), checkpoint: true, id: 2)],
        ),
      ]),
      throwsA(isA<BuError>()),
    );
    // The controller is still consistent at the last good block.
    final got = await c.buildMerkle(
      targetHeight: 1,
      saplingOutputs: [_out(nA, 0)],
    );
    expect(got.saplingNotes, hasLength(1));
    await c.closeContext();
  });

  test('journal codec round-trips; garbage decodes as empty journal', () {
    final leaves = List<int>.generate(64, (i) => i);
    final j = MirrorTipJournal(
      sapling: PoolTipJournal(base: 0, leaves: leaves, checkpoints: {7: 3}),
    );
    final rt = MirrorTipJournal.tryDecode(j.toCbor());
    expect(rt, isNotNull);
    expect(rt!.sapling.base, 0);
    expect(rt.sapling.leaves, leaves);
    expect(rt.sapling.checkpoints, {7: 3});
    expect(rt.orchard.isEmpty, isTrue);
    // Garbage / wrong shapes are absent, never throw.
    expect(MirrorTipJournal.tryDecode(null), isNull);
    expect(MirrorTipJournal.tryDecode(CborBytesValue([1, 2, 3])), isNull);
    expect(
      MirrorTipJournal.tryDecode(CborListValue.definite(const <CborObject>[])),
      isNull,
    );

    // NativeMerkleState round-trips indices + journal through CBOR bytes.
    final state = NativeMerkleState(
      journal: j,
      saplingSubtreeIndex: 3,
      orchardSubtreeIndex: 5,
      ironwoodSubtreeIndex: 7,
    );
    final rtState = NativeMerkleState.deserialize(
      bytes: state.toCbor().encode(),
    );
    expect(rtState.saplingSubtreeIndex, 3);
    expect(rtState.orchardSubtreeIndex, 5);
    expect(rtState.ironwoodSubtreeIndex, 7);
    expect(rtState.journal.sapling.leaves, leaves);
  });
}

void main() {
  ZcashTestApi.runTest(nativeJournalRestoreTest, "Native Journal Restore");
}
