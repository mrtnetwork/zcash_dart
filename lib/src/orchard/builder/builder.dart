import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/transaction/builders/types.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';
import 'package:zcash_dart/src/value/value.dart';

sealed class OrchardBundleType {
  const OrchardBundleType();
  OrchardBundleFlags get flags;

  factory OrchardBundleType.defaultBundle() => OrchardBundleTypeTransactional(
    flags: OrchardBundleFlags.enabled,
    bundleRequired: false,
  );
  factory OrchardBundleType.disabled() => OrchardBundleTypeTransactional(
    flags: OrchardBundleFlags(spendsEnabled: false, outputsEnabled: false),
    bundleRequired: false,
  );
  int numActions({
    required int numSpends,
    required int numOutputs,
    bool crossAddressEnabled = true,
  });
}

class OrchardBundleTypeTransactional extends OrchardBundleType {
  @override
  final OrchardBundleFlags flags;
  final bool bundleRequired;
  const OrchardBundleTypeTransactional({
    required this.flags,
    required this.bundleRequired,
  });

  @override
  int numActions({
    required int numSpends,
    required int numOutputs,
    bool crossAddressEnabled = true,
  }) {
    if (!flags.spendsEnabled && numSpends > 0) {
      throw ZcashErrors.orchardBuilderFailed(
        "numActions",
        reason: "Spends are disabled.",
      );
    }
    if (!flags.outputsEnabled && numOutputs > 0) {
      throw ZcashErrors.orchardBuilderFailed(
        reason: "numActions",
        "Outputs are disabled.",
      );
    }
    const int minActions = 2;
    // Official restricted path: spend and output never share an action.
    final rActions =
        crossAddressEnabled
            ? IntUtils.max(numSpends, numOutputs)
            : numSpends + numOutputs;
    if (bundleRequired || rActions > 0) {
      return IntUtils.max(rActions, minActions);
    }
    return 0;
  }
}

class OrchardBundleTypeCoinbase extends OrchardBundleType {
  const OrchardBundleTypeCoinbase();

  @override
  int numActions({
    required int numSpends,
    required int numOutputs,
    bool crossAddressEnabled = true,
  }) {
    if (numSpends > 0) {
      throw ZcashErrors.orchardBuilderFailed(
        "numActions",
        reason: "Coinbase bundles have spends disabled.",
      );
    }
    return numOutputs;
  }

  @override
  OrchardBundleFlags get flags => OrchardBundleFlags.spendDisabled;
}

class OrchardSpendInfo {
  final OrchardSpendingKey? dummySk;
  final OrchardFullViewingKey fvk;
  final Bip44Changes? scope;
  final OrchardNote note;
  final OrchardMerklePath merklePath;
  const OrchardSpendInfo({
    this.dummySk,
    required this.fvk,
    this.scope,
    required this.note,
    required this.merklePath,
  });
  factory OrchardSpendInfo.dummy(
    ZcashCryptoContext context, [
    OrchardNoteVersion version = OrchardNoteVersion.v2,
  ]) {
    final (sk, fvk, note) = OrchardNote.dummy(context, version: version);
    final merklePath = OrchardMerklePath.dummy();
    return OrchardSpendInfo(
      dummySk: sk,
      fvk: fvk,
      note: note,
      merklePath: merklePath,
      scope: Bip44Changes.chainExt,
    );
  }

  Bip44Changes getScope(ZCryptoContext context) {
    final scope =
        this.scope ??
        fvk.scopeForAddress(address: note.recipient, context: context);
    if (scope == null) {
      throw ZcashErrors.orchardBuilderFailed(
        "getScope",
        reason: "Invalid full view key for note.",
      );
    }
    return scope;
  }

  bool hasMatchingAnchor(ZcashCryptoContext context, OrchardAnchor anchor) {
    if (note.value.isZero()) {
      return true;
    }
    final cm = note.commitment(context);
    final pathRoot = merklePath.root(
      cmx: cm.toExtractedNoteCommitment(),
      hashContext: context.orchardHashable(),
    );
    return pathRoot == anchor;
  }

  ({
    OrchardNullifier nullifier,
    OrchardSpendValidatingKey ak,
    BuBytes alpha,
    RedPallasSpendPublicKey rk,
  })
  build(ZcashCryptoContext context) {
    final nfOld = note.nullifier(context: context, fvk: fvk);
    final ak = fvk.ak;
    final alpha = blockchainUtils.api.pallas.scReduce64(
      QuickCrypto.generateRandom(length: 64),
    );
    final rk = ak.key.randomize(alpha);
    return (nullifier: nfOld, ak: ak, alpha: alpha, rk: rk);
  }

  OrchardPcztSpend toPczt(ZcashCryptoContext context) {
    final build = this.build(context);
    return OrchardPcztSpend(
      nullifier: build.nullifier,
      rk: build.rk,
      recipient: note.recipient,
      alpha: build.alpha,
      witness: merklePath,
      dummySk: dummySk,
      fvk: fvk,
      rho: note.rho,
      rseed: note.rseed,
      value: note.value,
    );
  }
}

class OrchardOutputInfo {
  final OrchardOutgoingViewingKey? ovk;
  final OrchardAddress recipient;
  final ZAmount value;
  final List<int> memo;
  OrchardOutputInfo({
    this.ovk,
    required this.recipient,
    required this.value,
    required List<int> memo,
  }) : memo = memo.exc(
         length: NoteEncryptionConst.memoLength,
         operation: "OrchardOutputInfo",
         reason: "Invalid memo bytes length.",
       );
  factory OrchardOutputInfo.dummy(ZCryptoContext context) {
    final dummy = OrchardUtils.createDummySpendKey();
    return OrchardOutputInfo(
      recipient: dummy.fvk.addressAt(
        context: context,
        j: DiversifierIndex.zero(),
        scope: Bip44Changes.chainExt,
      ),
      value: ZAmount.zero(),
      memo: List<int>.filled(NoteEncryptionConst.memoLength, 0),
    );
  }

  ({
    OrchardNote note,
    OrchardExtractedNoteCommitment cmx,
    OrchardTransmittedNoteCiphertext encryotedNote,
  })
  build({
    required OrchardValueCommitment cvNet,
    required OrchardNullifier nfOld,
    required ZcashCryptoContext context,
    OrchardNoteVersion version = OrchardNoteVersion.v2,
  }) {
    final rho = OrchardRho(nfOld.inner);
    final note = OrchardNote.build(
      recipient: recipient,
      value: value,
      rseed: OrchardNoteRandomSeed.random(rho),
      rho: rho,
      context: context,
      version: version,
    );
    final cmNew = note.commitment(context);
    final cmx = cmNew.toExtractedNoteCommitment();
    // encrypt with the note's pool version. The domain
    // writes the version byte of the transmitted plaintext; a v2 domain
    // on a v3 note stamps the wrong byte, so the receiver rebuilds a v2
    // note whose commitment can never match cmx and trial-decryption
    // silently drops the output (wallet never receives ironwood).
    final domain = OrchardDomain(context, version: version);
    final encryptor = domain.createNote(note: note, memo: memo, ovk: ovk);
    final encryptedNote = OrchardTransmittedNoteCiphertext(
      epkBytes: encryptor.epk,
      encCiphertext: domain.encryptNotePlaintext(encryptor),
      outCiphertext: domain.encryptOutgoingPlaintext(
        encryotedNote: encryptor,
        cv: cvNet,
        cm: cmx,
      ),
    );
    return (note: note, cmx: cmx, encryotedNote: encryptedNote);
  }

  ///output notes must use the pool's version (orchard
  /// pool v2, ironwood pool v3 — same pool rule as spends). The old v2
  /// default built invalid v3-pool notes, whose commitments could never
  /// match the v3 circuits (bundles failed verification at extract).
  OrchardPcztOutput toPczt({
    required OrchardValueCommitment cvNet,
    required OrchardNullifier nfOld,
    required ZcashCryptoContext context,
    required OrchardNoteVersion version,
  }) {
    final build = this.build(
      context: context,
      cvNet: cvNet,
      nfOld: nfOld,
      version: version,
    );
    return OrchardPcztOutput(
      cmx: build.cmx,
      encryptedNote: build.encryotedNote,
      recipient: recipient,
      value: value,
      rseed: build.note.rseed,
    );
  }
}

/// Wallet-controlled change output (mirrors official `ChangeInfo`).
///
/// In cross-address-restricted bundles (Orchard pool under NU6.3) plain
/// outputs are rejected and retained value must arrive as change: the
/// change output pairs with a fabricated zero-valued spend controlled
/// by [fvk], so every action stays addressed to the note it spends.
class OrchardChangeInfo {
  final OrchardFullViewingKey fvk;
  final Bip44Changes? scope;
  final OrchardOutputInfo output;
  const OrchardChangeInfo({
    required this.fvk,
    this.scope,
    required this.output,
  });
}

class OrchardActionInfo {
  final OrchardSpendInfo spend;
  final OrchardOutputInfo output;
  final OrchardValueCommitTrapdoor rcv;
  OrchardActionInfo({
    required this.spend,
    required this.output,
    OrchardValueCommitTrapdoor? rcv,
  }) : rcv = rcv ?? OrchardValueCommitTrapdoor.random();
  ZAmount valueSum() => spend.note.value - output.value;

  ({
    OrchardTransfableCircuit circuit,
    OrchardAction action,
    OrchardSpendingKey? dummySk,
    OrchardSpendValidatingKey ak,
    BuBytes alpha,
  })
  build(
    ZcashCryptoContext context, {
    OrchardNoteVersion version = OrchardNoteVersion.v2,
  }) {
    final vNet = valueSum();
    final cvNet = OrchardValueCommitment.derive(value: vNet, rcv: rcv);
    this.spend.dummySk;
    final spend = this.spend.build(context);
    final output = this.output.build(
      context: context,
      cvNet: cvNet,
      nfOld: spend.nullifier,
      version: version,
    );
    final action = OrchardAction(
      nf: spend.nullifier,
      rk: spend.rk,
      cmx: output.cmx,
      encryptedNote: output.encryotedNote,
      cvNet: cvNet,
    );
    final circuit = OrchardTransfableCircuit.fromActionContext(
      spend: this.spend,
      outputNote: output.note,
      alpha: spend.alpha,
      context: context,
      rcv: rcv,
    );
    return (
      circuit: circuit,
      action: action,
      dummySk: this.spend.dummySk,
      ak: spend.ak,
      alpha: spend.alpha,
    );
  }

  /// [version] is the pool's note version (see
  /// [OrchardBuilder.noteVersion]) — it must match the version the
  /// prover rebuilds notes with, or commitments diverge and the bundle
  /// fails verification.
  OrchardPcztAction toPczt(
    ZcashCryptoContext context, {
    required OrchardNoteVersion version,
  }) {
    final vNet = valueSum();
    final cvNet = OrchardValueCommitment.derive(value: vNet, rcv: rcv);
    final spend = this.spend.toPczt(context);
    final output = this.output.toPczt(
      context: context,
      cvNet: cvNet,
      nfOld: spend.nullifier,
      version: version,
    );
    return OrchardPcztAction(
      cvNet: cvNet,
      spend: spend,
      output: output,
      rcv: rcv,
    );
  }
}

class OrchardBuilder
    implements
        BundleBuilder<
          OrchardBundle,
          OrchardExtractedBundle,
          OrchardPcztBundleParams,
          OrchardPcztBundle,
          RedPallasBindingPrivateKey
        > {
  List<OrchardSpendInfo> _spends;
  List<OrchardSpendInfo> get spends => _spends;
  List<OrchardOutputInfo> _outputs;
  List<OrchardOutputInfo> get outputs => _outputs;
  List<OrchardChangeInfo> _changes;
  List<OrchardChangeInfo> get changes => _changes;
  final OrchardBundleType bundleType;
  final OrchardAnchor anchor;
  final ZcashCryptoContext context;

  /// The value pool this builder targets. Cross-address transfers are
  /// permitted only in the Ironwood pool under NU6.3; the Orchard pool
  /// forbids them from NU6.3 onward (see `OrchardBundleFlags`).
  final OrchardValuePool pool;

  /// Consensus branch this builder targets, when known. Used to derive
  /// the bundle version and to enforce NU6.3 pool rules (including the
  /// coinbase rule below). Null means "pre-NU6.2 legacy".
  final ZcashNetworkProtocol? networkUpgrade;

  /// Explicit bundle-version override. Defaults to the version derived
  /// from ([networkUpgrade], [pool]).
  final OrchardBundleVersion? bundleVersionOverride;
  PcztBundleWithMetadata<
    OrchardBundle,
    OrchardExtractedBundle,
    OrchardPcztBundleParams,
    OrchardPcztBundle
  >?
  _cachedPczt;
  OrchardBuilder({
    List<OrchardSpendInfo> spends = const [],
    List<OrchardOutputInfo> outputs = const [],
    List<OrchardChangeInfo> changes = const [],
    required this.bundleType,
    required this.anchor,
    required this.context,
    this.pool = OrchardValuePool.orchard,
    this.networkUpgrade,
    this.bundleVersionOverride,
  }) : _spends = spends.immutable,
       _outputs = outputs.immutable,
       _changes = changes.immutable;

  /// Note version for outputs created by this builder: v3 for the
  /// Ironwood pool, v2 for the Orchard pool.
  OrchardNoteVersion get noteVersion =>
      pool == OrchardValuePool.ironwood
          ? OrchardNoteVersion.v3
          : OrchardNoteVersion.v2;

  /// Effective flags for built bundles: the configured flags with the
  /// cross-address bit canonicalized to what [bundleVersion] permits
  /// (cleared for the Orchard pool under V3). Mirrors official
  /// `default_flags` / flag-byte policy.
  OrchardBundleFlags get effectiveFlags {
    if (bundleVersion.permitsCrossAddressTransfers) {
      return bundleType.flags;
    }
    return bundleType.flags.copyWith(crossAddressEnabled: false);
  }

  /// Whether this builder targets a cross-address-restricted bundle
  /// (Orchard pool under protocol V3 / NU6.3).
  bool get isRestricted => !bundleVersion.permitsCrossAddressTransfers;

  /// Bundle version for bundles created by this builder.
  OrchardBundleVersion get bundleVersion {
    final override = bundleVersionOverride;
    if (override != null) return override;
    final branch = networkUpgrade;
    if (branch != null) {
      final resolved = OrchardBundleVersion.forBranch(
        branch,
        isIronwoodPool: pool == OrchardValuePool.ironwood,
      );
      if (resolved != null) return resolved;
    }
    return pool == OrchardValuePool.ironwood
        ? OrchardBundleVersion.ironwoodV3
        : OrchardBundleVersion.orchardV1;
  }

  int _addSpend(OrchardSpendInfo spend) {
    _spends = [..._spends, spend].toImutableList;
    _cachedPczt = null;
    return _spends.indexOf(spend).asPositive;
  }

  int _addOutput(OrchardOutputInfo output) {
    _outputs = [..._outputs, output].toImutableList;
    _cachedPczt = null;
    return _outputs.indexOf(output).asPositive;
  }

  int _addChange(OrchardChangeInfo change) {
    _changes = [..._changes, change].toImutableList;
    _cachedPczt = null;
    return _changes.indexOf(change).asPositive;
  }

  int addSpend({
    required OrchardFullViewingKey fvk,
    required OrchardNote note,
    required OrchardMerklePath merklePath,
  }) {
    if (!bundleType.flags.spendsEnabled) {
      throw ZcashErrors.orchardBuilderFailed(
        "addSpend",
        reason: "Spends disabled.",
      );
    }
    final spend = OrchardSpendInfo(
      fvk: fvk,
      merklePath: merklePath,
      note: note,
    );
    if (!spend.hasMatchingAnchor(context, anchor)) {
      throw ZcashErrors.orchardBuilderFailed(
        "addSpend",
        reason: "Anchor mismatch.",
      );
    }
    return _addSpend(spend);
  }

  int addOutput({
    required OrchardAddress recipient,
    required ZAmount value,
    required List<int> memo,
    OrchardOutgoingViewingKey? ovk,
  }) {
    if (!bundleType.flags.outputsEnabled) {
      throw ZcashErrors.orchardBuilderFailed(
        "addOutput",
        reason: "Outputs disabled.",
      );
    }
    final output = OrchardOutputInfo(
      recipient: recipient,
      value: value,
      memo: memo,
      ovk: ovk,
    );
    return _addOutput(output);
  }

  /// Adds a wallet-controlled change output (mirrors official
  /// `Builder::add_change_output`).
  ///
  /// In cross-address-restricted bundles (Orchard pool under NU6.3)
  /// retained value must arrive as change: the change output pairs with
  /// a fabricated zero-valued spend controlled by [fvk], keeping every
  /// action addressed to the note it spends.
  /// Returns whether the change was recorded. Zero-valued
  /// change is skipped (`false`) — it carries no value but would cost an
  /// action and fee to spend, and a silent skip would shift change
  /// indices, so callers must only count `true` results (the wallet
  /// tracks `orchardChanges` the same way for `signOrchardChange`).
  bool addChangeOutput({
    required OrchardFullViewingKey fvk,
    required OrchardAddress recipient,
    required ZAmount value,
    required List<int> memo,
    Bip44Changes? scope,
    OrchardOutgoingViewingKey? ovk,
  }) {
    if (!bundleType.flags.outputsEnabled) {
      throw ZcashErrors.orchardBuilderFailed(
        "addChangeOutput",
        reason: "Outputs disabled.",
      );
    }
    if (value.isZero()) return false;
    _addChange(
      OrchardChangeInfo(
        fvk: fvk,
        scope: scope,
        output: OrchardOutputInfo(
          recipient: recipient,
          value: value,
          memo: memo,
          ovk: ovk,
        ),
      ),
    );
    return true;
  }

  @override
  ZAmount valueBalance() {
    final value = spends
        .map((e) => e.note.value - ZAmount.zero())
        .followedBy(outputs.map((e) => ZAmount.zero() - e.value))
        .followedBy(changes.map((e) => ZAmount.zero() - e.output.value))
        .fold<ZAmount>(ZAmount.zero(), (p, c) => p + c);
    return value.asI64();
  }

  @override
  BundleWithMetadata<OrchardBundle, RedPallasBindingPrivateKey> build() {
    final bundle = _buildBundle();
    final valueBalance = bundle.valueBalance.asI64();
    final bsk =
        bundle.actions
            .fold<OrchardValueCommitTrapdoor>(
              OrchardValueCommitTrapdoor.zero(),
              (p, c) => p + c.rcv,
            )
            .toBsk();
    final actionWithCircuit =
        bundle.actions
            .map((e) => e.build(context, version: noteVersion))
            .toList();
    final actions = actionWithCircuit.map((e) => e.action).toList();
    final bvk =
        (OrchardValueCommitment.from(actions.map((e) => e.cvNet).toList()) -
                OrchardValueCommitment.derive(
                  value: valueBalance,
                  rcv: OrchardValueCommitTrapdoor.zero(),
                ))
            .toBvk();
    assert(bsk.publicKey == bvk);
    return BundleWithMetadata(
      bundle: OrchardBundle(
        actions: actions,
        flags: effectiveFlags,
        balance: valueBalance,
        anchor: anchor,
        authorization: null,
        bundleVersion: bundleVersion,
      ),
      data: bsk,
      metadata: bundle.bundleMeta,
    );
  }

  @override
  PcztBundleWithMetadata<
    OrchardBundle,
    OrchardExtractedBundle,
    OrchardPcztBundleParams,
    OrchardPcztBundle
  >
  toPczt() {
    final pczt =
        _cachedPczt ??= () {
          final bundle = _buildBundle();
          final actions =
              bundle.actions
                  .map((e) => e.toPczt(context, version: noteVersion))
                  .toList();
          final pczt = OrchardPcztBundle(
            actions: actions,
            flags: effectiveFlags,
            valueSum: bundle.valueBalance,
            anchor: anchor,
            bundleVersion: bundleVersion,
          );
          return PcztBundleWithMetadata<
            OrchardBundle,
            OrchardExtractedBundle,
            OrchardPcztBundleParams,
            OrchardPcztBundle
          >(bundle: pczt, metadata: bundle.bundleMeta);
        }();
    return pczt.clone();
  }

  /// Fabricates a zero-valued output to [recipient] (restricted
  /// pairing and dummy padding). Mirrors official fabricated outputs.
  OrchardOutputInfo _fabricatedZeroOutput(OrchardAddress recipient) {
    return OrchardOutputInfo(
      recipient: recipient,
      value: ZAmount.zero(),
      memo: List<int>.filled(NoteEncryptionConst.memoLength, 0),
    );
  }

  /// Fabricates a zero-valued wallet-controlled spend at [recipient]
  /// (restricted change pairing). The spend carries no dummy key: it is
  /// signed through the normal flow by [fvk]. Mirrors official
  /// fabricated change spends.
  OrchardSpendInfo _fabricatedZeroSpend({
    required OrchardFullViewingKey fvk,
    required Bip44Changes? scope,
    required OrchardAddress recipient,
  }) {
    final rho = OrchardRho.random();
    final note = OrchardNote.build(
      recipient: recipient,
      value: ZAmount.zero(),
      rseed: OrchardNoteRandomSeed.random(rho),
      rho: rho,
      context: context,
      version: noteVersion,
    );
    return OrchardSpendInfo(
      fvk: fvk,
      scope: scope,
      note: note,
      merklePath: OrchardMerklePath.dummy(),
    );
  }

  ({
    BundleMetadata bundleMeta,
    List<OrchardActionInfo> actions,
    ZAmount valueBalance,
  })
  _buildBundle() {
    if (!bundleType.flags.spendsEnabled && spends.isNotEmpty) {
      throw ZcashErrors.orchardBuilderFailed(
        "buildBundle",
        reason: "Spends disabled",
      );
    }
    final numPlainOutputs = outputs.length;
    final numChanges = changes.length;
    if (!bundleType.flags.outputsEnabled &&
        (numPlainOutputs + numChanges) > 0) {
      throw ZcashErrors.orchardBuilderFailed(
        "buildBundle",
        reason: "Outputs disabled",
      );
    }
    final version = bundleVersion;
    if (version.valuePool == OrchardValuePool.ironwood &&
        version.protocolVersion != OrchardProtocolVersion.v3) {
      throw ZcashErrors.orchardBuilderFailed(
        "buildBundle",
        reason: "The Ironwood pool exists only from NU6.3 (protocol v3).",
      );
    }
    // NU6.3 coinbase rule (librustzcash): coinbase builders no longer
    // expose Orchard outputs.
    if (bundleType is OrchardBundleTypeCoinbase &&
        pool == OrchardValuePool.orchard &&
        (numPlainOutputs + numChanges) > 0 &&
        (networkUpgrade?.hasIronwood() ?? false)) {
      throw ZcashErrors.orchardBuilderFailed(
        "buildBundle",
        reason:
            "Coinbase transactions cannot create Orchard outputs under NU6.3.",
      );
    }
    if (isRestricted) {
      return _buildRestricted();
    }
    return _buildUnrestricted();
  }

  /// Pair-by-construction build for cross-address-restricted bundles
  /// (Orchard pool under V3). Mirrors the official restricted path:
  /// plain outputs are rejected (retained value must arrive as
  /// wallet-controlled change), spends pair with fabricated zero
  /// outputs to their own address, changes pair with fabricated zero
  /// spends, padding pairs self-addressed dummies; only complete pairs
  /// are shuffled.
  ({
    BundleMetadata bundleMeta,
    List<OrchardActionInfo> actions,
    ZAmount valueBalance,
  })
  _buildRestricted() {
    if (outputs.isNotEmpty) {
      throw ZcashErrors.orchardBuilderFailed(
        "buildBundle",
        reason:
            "Cross-address transfers are disabled for the Orchard pool under NU6.3: plain outputs are not allowed. Use pool ironwood, or addChangeOutput for wallet-controlled change.",
      );
    }
    final numSpends = spends.length;
    final numOutputs = changes.length;
    final numActions = bundleType.numActions(
      numSpends: numSpends,
      numOutputs: numOutputs,
      crossAddressEnabled: false,
    );
    // Each pair holds (spend index?, change index?, spend, output).
    final pairs = <(int?, int?, OrchardSpendInfo, OrchardOutputInfo)>[];
    for (final (sIndex, spend) in spends.indexed) {
      pairs.add((
        sIndex,
        null,
        spend,
        _fabricatedZeroOutput(spend.note.recipient),
      ));
    }
    for (final (cIndex, change) in changes.indexed) {
      pairs.add((
        null,
        cIndex,
        _fabricatedZeroSpend(
          fvk: change.fvk,
          scope: change.scope,
          recipient: change.output.recipient,
        ),
        change.output,
      ));
    }
    while (pairs.length < numActions) {
      final spend = OrchardSpendInfo.dummy(context, noteVersion);
      pairs.add((
        null,
        null,
        spend,
        _fabricatedZeroOutput(spend.note.recipient),
      ));
    }
    pairs.shuffle(QuickCrypto.prng);
    final spendIndices = List.filled(numSpends, 0);
    // Requested outputs are numbered plain-first, then changes. Plain
    // outputs are rejected above, so only change indices land here.
    final outputIndices = List.filled(numOutputs, 0);
    final changeSpendIndices = List.filled(numOutputs, 0);
    final preActions = <OrchardActionInfo>[];
    for (var i = 0; i < pairs.length; i++) {
      final (sIndex, cIndex, spend, output) = pairs[i];
      if (sIndex != null) spendIndices[sIndex] = i;
      if (cIndex != null) {
        outputIndices[cIndex] = i;
        changeSpendIndices[cIndex] = i;
      }
      preActions.add(OrchardActionInfo(spend: spend, output: output));
    }
    final valueBalance = preActions.fold<ZAmount>(
      ZAmount.zero(),
      (p, c) => p + c.valueSum(),
    );
    return (
      actions: preActions,
      valueBalance: valueBalance,
      bundleMeta: BundleMetadata(
        outputIndices: outputIndices,
        spendIndices: spendIndices,
        changeSpendIndices: changeSpendIndices,
      ),
    );
  }

  ({
    BundleMetadata bundleMeta,
    List<OrchardActionInfo> actions,
    ZAmount valueBalance,
  })
  _buildUnrestricted() {
    final numSpends = spends.length;
    final numOutputs = outputs.length + changes.length;
    final allOutputs = [...outputs, ...changes.map((e) => e.output)];
    final numActions = bundleType.numActions(
      numSpends: numSpends,
      numOutputs: numOutputs,
    );
    final indexedSpends =
        List.generate(
            numActions,
            (i) =>
                spends.elementAtOrNull(i) ??
                OrchardSpendInfo.dummy(context, noteVersion),
          ).indexed.toList()
          ..shuffle(QuickCrypto.prng);
    final indexedOutputs =
        List.generate(
            numActions,
            (i) =>
                allOutputs.elementAtOrNull(i) ??
                OrchardOutputInfo.dummy(context),
          ).indexed.toList()
          ..shuffle(QuickCrypto.prng);

    final spendIndices = List.filled(numSpends, 0);
    final outputIndices = List.filled(numOutputs, 0);
    final preActions = List.generate(indexedSpends.length, (i) {
      final (sIndex, spend) = indexedSpends.elementAt(i);
      final (oIndex, output) = indexedOutputs.elementAt(i);
      if (sIndex < numSpends) {
        spendIndices[sIndex] = i;
      }
      if (oIndex < numOutputs) {
        outputIndices[oIndex] = i;
      }
      return OrchardActionInfo(spend: spend, output: output);
    });
    final valueBalance = preActions.fold<ZAmount>(
      ZAmount.zero(),
      (p, c) => p + c.valueSum(),
    );
    return (
      actions: preActions,
      valueBalance: valueBalance,
      bundleMeta: BundleMetadata(
        outputIndices: outputIndices,
        spendIndices: spendIndices,
      ),
    );
  }
}
