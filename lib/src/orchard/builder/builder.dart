import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/builder/exception.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/orchard/pczt/pczt.dart';
import 'package:zcash_dart/src/transaction/builders/types.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/orchard.dart';

sealed class OrchardBundleType {
  const OrchardBundleType();
  OrchardBundleFlags get flags;

  factory OrchardBundleType.defaultBundle() => OrchardBundleTypeTransactional(
      flags: OrchardBundleFlags.enabled, bundleRequired: false);
  factory OrchardBundleType.disabled() => OrchardBundleTypeTransactional(
      flags: OrchardBundleFlags(spendsEnabled: false, outputsEnabled: false),
      bundleRequired: false);
  int numActions({required int numSpends, required int numOutputs});
}

class OrchardBundleTypeTransactional extends OrchardBundleType {
  @override
  final OrchardBundleFlags flags;
  final bool bundleRequired;
  const OrchardBundleTypeTransactional(
      {required this.flags, required this.bundleRequired});

  @override
  int numActions({required int numSpends, required int numOutputs}) {
    if (!flags.spendsEnabled && numSpends > 0) {
      throw OrchardBuilderException.operationFailed("numActions",
          reason: "Spends are disabled.");
    }
    if (!flags.outputsEnabled && numOutputs > 0) {
      throw OrchardBuilderException.operationFailed(
          reason: "numActions", "Outputs are disabled.");
    }
    const int minActions = 2;
    final rActions = IntUtils.max(numSpends, numOutputs);
    if (bundleRequired || rActions > 0) {
      return IntUtils.max(rActions, minActions);
    }
    return 0;
  }
}

class OrchardBundleTypeCoinbase extends OrchardBundleType {
  const OrchardBundleTypeCoinbase();

  @override
  int numActions({required int numSpends, required int numOutputs}) {
    if (numSpends > 0) {
      throw OrchardBuilderException.operationFailed("numActions",
          reason: "Coinbase bundles have spends disabled.");
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
  const OrchardSpendInfo(
      {this.dummySk,
      required this.fvk,
      this.scope,
      required this.note,
      required this.merklePath});
  factory OrchardSpendInfo.dummy(ZCashCryptoContext context) {
    final (sk, fvk, note) = OrchardNote.dummy(context);
    final merklePath = OrchardMerklePath.dummy();
    return OrchardSpendInfo(
        dummySk: sk,
        fvk: fvk,
        note: note,
        merklePath: merklePath,
        scope: Bip44Changes.chainExt);
  }

  Bip44Changes getScope(ZCryptoContext context) {
    final scope = this.scope ??
        fvk.scopeForAddress(address: note.recipient, context: context);
    if (scope == null) {
      throw OrchardBuilderException.operationFailed("getScope",
          reason: "Invalid full view key for note.");
    }
    return scope;
  }

  bool hasMatchingAnchor(ZCashCryptoContext context, OrchardAnchor anchor) {
    if (note.value.isZero()) {
      return true;
    }
    final cm = note.commitment(context);
    final pathRoot = merklePath.root(
        cmx: cm.toExtractedNoteCommitment(),
        hashContext: context.orchardHashable());
    return pathRoot == anchor;
  }

  ({
    OrchardNullifier nullifier,
    OrchardSpendValidatingKey ak,
    VestaNativeFq alpha,
    OrchardSpendVerificationKey rk
  }) build(ZCashCryptoContext context) {
    final nfOld = note.nullifier(context: context, fvk: fvk);
    final ak = fvk.ak;
    final alpha = VestaNativeFq.random();
    final rk = ak.key.randomize(alpha);
    return (nullifier: nfOld, ak: ak, alpha: alpha, rk: rk);
  }

  OrchardPcztSpend toPczt(ZCashCryptoContext context) {
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
        value: note.value);
  }
}

class OrchardOutputInfo {
  final OrchardOutgoingViewingKey? ovk;
  final OrchardAddress recipient;
  final ZAmount value;
  final List<int> memo;
  OrchardOutputInfo(
      {this.ovk,
      required this.recipient,
      required this.value,
      required List<int> memo})
      : memo = memo.exc(
            length: NoteEncryptionConst.memoLength,
            operation: "OrchardOutputInfo",
            reason: "Invalid memo bytes length.");
  factory OrchardOutputInfo.dummy(ZCryptoContext context) {
    final dummy = OrchardUtils.createDummySpendKey();
    return OrchardOutputInfo(
        recipient: dummy.fvk.addressAt(
            context: context,
            j: DiversifierIndex.zero(),
            scope: Bip44Changes.chainExt),
        value: ZAmount.zero(),
        memo: List<int>.filled(NoteEncryptionConst.memoLength, 0));
  }

  ({
    OrchardNote note,
    OrchardExtractedNoteCommitment cmx,
    OrchardTransmittedNoteCiphertext encryotedNote
  }) build(
      {required OrchardValueCommitment cvNet,
      required OrchardNullifier nfOld,
      required ZCashCryptoContext context}) {
    final rho = OrchardRho(nfOld.inner);
    final note = OrchardNote.build(
        recipient: recipient,
        value: value,
        rseed: OrchardNoteRandomSeed.random(rho),
        rho: rho,
        context: context);
    final cmNew = note.commitment(context);
    final cmx = cmNew.toExtractedNoteCommitment();
    final domain = OrchardDomainNative(context);
    final encryptor = domain.createNote(note: note, memo: memo, ovk: ovk);
    final encryptedNote = OrchardTransmittedNoteCiphertext(
        epkBytes: encryptor.epk.toBytes(),
        encCiphertext: domain.encryptNotePlaintext(encryptor),
        outCiphertext: domain.encryptOutgoingPlaintext(
            encryotedNote: encryptor, cv: cvNet, cm: cmx));
    return (note: note, cmx: cmx, encryotedNote: encryptedNote);
  }

  OrchardPcztOutput toPczt(
      {required OrchardValueCommitment cvNet,
      required OrchardNullifier nfOld,
      required ZCashCryptoContext context}) {
    final build = this.build(context: context, cvNet: cvNet, nfOld: nfOld);
    return OrchardPcztOutput(
        cmx: build.cmx,
        encryptedNote: build.encryotedNote,
        recipient: recipient,
        value: value,
        rseed: build.note.rseed);
  }
}

class OrchardActionInfo {
  final OrchardSpendInfo spend;
  final OrchardOutputInfo output;
  final OrchardValueCommitTrapdoor rcv;
  OrchardActionInfo(
      {required this.spend,
      required this.output,
      OrchardValueCommitTrapdoor? rcv})
      : rcv = rcv ?? OrchardValueCommitTrapdoor.random();
  ZAmount valueSum() => spend.note.value - output.value;

  ({
    OrchardTransfableCircuit circuit,
    OrchardAction action,
    OrchardSpendingKey? dummySk,
    OrchardSpendValidatingKey ak,
    VestaNativeFq alpha
  }) build(ZCashCryptoContext context) {
    final vNet = valueSum();
    final cvNet = OrchardValueCommitment.derive(value: vNet, rcv: rcv);
    this.spend.dummySk;
    final spend = this.spend.build(context);
    final output = this
        .output
        .build(context: context, cvNet: cvNet, nfOld: spend.nullifier);
    final action = OrchardAction(
        nf: spend.nullifier,
        rk: spend.rk,
        cmx: output.cmx,
        encryptedNote: output.encryotedNote,
        cvNet: cvNet);
    final circuit = OrchardTransfableCircuit.fromActionContext(
        spend: this.spend,
        outputNote: output.note,
        alpha: spend.alpha,
        context: context,
        rcv: rcv);
    return (
      circuit: circuit,
      action: action,
      dummySk: this.spend.dummySk,
      ak: spend.ak,
      alpha: spend.alpha
    );
  }

  OrchardPcztAction toPczt(ZCashCryptoContext context) {
    final vNet = valueSum();
    final cvNet = OrchardValueCommitment.derive(value: vNet, rcv: rcv);
    final spend = this.spend.toPczt(context);
    final output = this
        .output
        .toPczt(context: context, cvNet: cvNet, nfOld: spend.nullifier);
    return OrchardPcztAction(
        cvNet: cvNet, spend: spend, output: output, rcv: rcv);
  }
}

class OrchardBuilder
    implements
        BundleBuilder<OrchardBundle, OrchardExtractedBundle, OrchardPcztBundle,
            OrchardBindingAuthorizingKey> {
  List<OrchardSpendInfo> _spends;
  List<OrchardSpendInfo> get spends => _spends;
  List<OrchardOutputInfo> _outputs;
  List<OrchardOutputInfo> get outputs => _outputs;
  final OrchardBundleType bundleType;
  final OrchardAnchor anchor;
  final ZCashCryptoContext context;
  PcztBundleWithMetadata<OrchardBundle, OrchardExtractedBundle,
      OrchardPcztBundle>? _cachedPczt;
  OrchardBuilder(
      {List<OrchardSpendInfo> spends = const [],
      List<OrchardOutputInfo> outputs = const [],
      required this.bundleType,
      required this.anchor,
      required this.context})
      : _spends = spends.immutable,
        _outputs = outputs.immutable;
  void _addSpend(OrchardSpendInfo spend) {
    _spends = [..._spends, spend].toImutableList;
    _cachedPczt = null;
  }

  void _addOutput(OrchardOutputInfo output) {
    _outputs = [..._outputs, output].toImutableList;
    _cachedPczt = null;
  }

  void addSpend(
      {required OrchardFullViewingKey fvk,
      required OrchardNote note,
      required OrchardMerklePath merklePath}) {
    if (!bundleType.flags.spendsEnabled) {
      throw OrchardBuilderException.operationFailed("addSpend",
          reason: "Spends disabled.");
    }
    final spend =
        OrchardSpendInfo(fvk: fvk, merklePath: merklePath, note: note);
    if (!spend.hasMatchingAnchor(context, anchor)) {
      throw OrchardBuilderException.operationFailed("addSpend",
          reason: "Anchor mismatch.");
    }
    _addSpend(spend);
  }

  void addOutput({
    required OrchardAddress recipient,
    required ZAmount value,
    required List<int> memo,
    OrchardOutgoingViewingKey? ovk,
  }) {
    if (!bundleType.flags.outputsEnabled) {
      throw OrchardBuilderException.operationFailed("addOutput",
          reason: "Outputs disabled.");
    }
    final output = OrchardOutputInfo(
        recipient: recipient, value: value, memo: memo, ovk: ovk);
    _addOutput(output);
  }

  @override
  ZAmount valueBalance() {
    final value = spends
        .map((e) => e.note.value - ZAmount.zero())
        .followedBy(outputs.map((e) => ZAmount.zero() - e.value))
        .fold<ZAmount>(ZAmount.zero(), (p, c) => p + c);
    return value.asI64();
  }

  @override
  BundleWithMetadata<OrchardBundle, OrchardBindingAuthorizingKey> build() {
    final bundle = _buildBundle();
    final valueBalance = bundle.valueBalance.asI64();
    final bsk = bundle.actions
        .fold<OrchardValueCommitTrapdoor>(
            OrchardValueCommitTrapdoor.zero(), (p, c) => p + c.rcv)
        .toBsk();
    final actionWithCircuit =
        bundle.actions.map((e) => e.build(context)).toList();
    final actions = actionWithCircuit.map((e) => e.action).toList();
    final bvk =
        (OrchardValueCommitment.from(actions.map((e) => e.cvNet).toList()) -
                OrchardValueCommitment.derive(
                    value: valueBalance,
                    rcv: OrchardValueCommitTrapdoor.zero()))
            .toBvk();
    assert(bsk.toVerificationKey() == bvk);
    return BundleWithMetadata(
        bundle: OrchardBundle(
            actions: actions,
            flags: bundleType.flags,
            balance: valueBalance,
            anchor: anchor,
            authorization: null),
        data: bsk,
        metadata: bundle.bundleMeta);
  }

  @override
  PcztBundleWithMetadata<OrchardBundle, OrchardExtractedBundle,
      OrchardPcztBundle> toPczt() {
    final pczt = _cachedPczt ??= () {
      final bundle = _buildBundle();
      final actions = bundle.actions.map((e) => e.toPczt(context)).toList();
      final pczt = OrchardPcztBundle(
          actions: actions,
          flags: bundleType.flags,
          valueSum: bundle.valueBalance,
          anchor: anchor);
      return PcztBundleWithMetadata<OrchardBundle, OrchardExtractedBundle,
          OrchardPcztBundle>(bundle: pczt, metadata: bundle.bundleMeta);
    }();
    return pczt.clone();
  }

  ({
    BundleMetadata bundleMeta,
    List<OrchardActionInfo> actions,
    ZAmount valueBalance
  }) _buildBundle() {
    if (!bundleType.flags.spendsEnabled && spends.isNotEmpty) {
      throw OrchardBuilderException.operationFailed("buildBundle",
          reason: "Spends disabled");
    }
    if (!bundleType.flags.outputsEnabled && outputs.isNotEmpty) {
      throw OrchardBuilderException.operationFailed("buildBundle",
          reason: "Outputs disabled");
    }
    final numSpends = spends.length;
    final numOutputs = outputs.length;
    final numActions =
        bundleType.numActions(numSpends: numSpends, numOutputs: numOutputs);
    final indexedSpends = List.generate(numActions,
            (i) => spends.elementAtOrNull(i) ?? OrchardSpendInfo.dummy(context))
        .indexed
        .toList()
      ..shuffle(QuickCrypto.prng);
    final indexedOutputs = List.generate(
            numActions,
            (i) =>
                outputs.elementAtOrNull(i) ?? OrchardOutputInfo.dummy(context))
        .indexed
        .toList()
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
    final valueBalance =
        preActions.fold<ZAmount>(ZAmount.zero(), (p, c) => p + c.valueSum());
    return (
      actions: preActions,
      valueBalance: valueBalance,
      bundleMeta: BundleMetadata(
          outputIndices: outputIndices, spendIndices: spendIndices)
    );
  }
}
