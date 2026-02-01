import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/sapling/builder/exception.dart';
import 'package:zcash_dart/src/sapling/pczt/pczt.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transaction/builders/types.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/circuit.dart';

sealed class SaplingBundleType {
  const SaplingBundleType();

  factory SaplingBundleType.defaultBundle() =>
      SaplingBundleTypeTransactional(false);
  int numSpends(int numSpends);
  int numOutputs({required int numSpends, required int numOutputs});
}

class SaplingBundleTypeTransactional implements SaplingBundleType {
  final bool bundleRequired;
  const SaplingBundleTypeTransactional(this.bundleRequired);

  @override
  int numOutputs({required int numSpends, required int numOutputs}) {
    if (bundleRequired || numSpends > 0 || numOutputs > 0) {
      return IntUtils.max(numOutputs, 2);
    }
    return 0;
  }

  @override
  int numSpends(int numSpends) {
    if (bundleRequired || numSpends > 0) {
      return IntUtils.max(numSpends, 1);
    }
    return 0;
  }
}

class SaplingBundleTypeCoinbase implements SaplingBundleType {
  const SaplingBundleTypeCoinbase();

  @override
  int numOutputs({required int numSpends, required int numOutputs}) {
    if (numSpends != 0) {
      throw SaplingBuilderException.operationFailed("numOutputs",
          reason: "Spends not allowed in coinbase bundles.");
    }
    return numOutputs;
  }

  @override
  int numSpends(int numSpends) {
    if (numSpends != 0) {
      throw SaplingBuilderException.operationFailed("numSpends",
          reason: "Spends not allowed in coinbase bundles.");
    }
    return 0;
  }
}

class SaplingSpendInfoInner {
  final SaplingFullViewingKey fvk;
  final SaplingNote note;
  final SaplingMerklePath merklePath;
  final SaplingExpandedSpendingKey? dummyExpsk;
  final SaplingProofGenerationKey? generationKey;
  SaplingSpendInfoInner._(
      {required this.fvk,
      required this.note,
      required this.merklePath,
      this.generationKey,
      this.dummyExpsk});
  ZAmount value() => note.value;

  factory SaplingSpendInfoInner.dummy() {
    final dummyNote = SaplingNote.dummy();
    final merklePath = SaplingMerklePath.random();
    return SaplingSpendInfoInner._(
        fvk: dummyNote.fvk,
        note: dummyNote.note,
        merklePath: merklePath,
        dummyExpsk: dummyNote.sk);
  }
  SaplingSpendInfoInner copyWith({SaplingProofGenerationKey? generationKey}) {
    return SaplingSpendInfoInner._(
        fvk: fvk,
        note: note,
        merklePath: merklePath,
        dummyExpsk: dummyExpsk,
        generationKey: generationKey);
  }

  bool hasMatchingAnchor(SaplingAnchor anchor, ZCashCryptoContext context) {
    if (note.value.isZero()) return true;
    final node = SaplingNode(note.cmu(context).inner);
    return merklePath.root(node, context.saplingHashable()) == anchor;
  }

  SaplingSpendInfo prepare() => SaplingSpendInfo._(
      fvk: fvk,
      note: note,
      merklePath: merklePath,
      rcv: SaplingValueCommitTrapdoor.random(),
      dummyExpsk: dummyExpsk,
      generationKey: generationKey);
}

class SaplingSpendInfo {
  final SaplingFullViewingKey fvk;
  final SaplingNote note;
  final SaplingMerklePath merklePath;
  final SaplingValueCommitTrapdoor rcv;
  final SaplingExpandedSpendingKey? dummyExpsk;
  final SaplingProofGenerationKey? generationKey;
  const SaplingSpendInfo._(
      {required this.fvk,
      required this.note,
      required this.merklePath,
      required this.rcv,
      this.dummyExpsk,
      this.generationKey});
  ({
    SaplingValueCommitment cv,
    SaplingNullifier nullifier,
    JubJubNativeFr alpha,
    SaplingSpendVerificationKey rk
  }) _build(ZCashCryptoContext context) {
    final alpha = JubJubNativeFr.random();
    final cv = SaplingValueCommitment.derive(value: note.value, rcv: rcv);
    final ak = fvk.vk.ak;
    final rk = ak.randomize(alpha);
    final nullifier = note.nullifier(
        nk: fvk.vk.nk,
        position: merklePath.position.position,
        context: context);
    return (cv: cv, alpha: alpha, nullifier: nullifier, rk: rk);
  }

  ({
    SaplingSpend spend,
    SaplingSpendDescription description,
    JubJubNativeFr alpha,
    SaplingSpendAuthorizingKey? expsk,
    SaplingSpendVerificationKey ak,
  }) build(ZCashCryptoContext context,
      {SaplingProofGenerationKey? proofGenerationKey}) {
    final dummyExpsk = this.dummyExpsk;
    if (proofGenerationKey != null && dummyExpsk != null) {
      throw SaplingBuilderException.operationFailed("build",
          reason: "Invalid spending key.");
    }
    if (proofGenerationKey == null && dummyExpsk == null) {
      throw SaplingBuilderException.operationFailed("build",
          reason: "Missing spending key.");
    }
    proofGenerationKey ??=
        SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(dummyExpsk!);
    final vk = proofGenerationKey.toViewingKey();
    if (vk != fvk.vk) {
      throw SaplingBuilderException.operationFailed("build",
          reason: "Invalid spending key.");
    }
    final b = _build(context);
    final node = SaplingNode(note.cmu(context).inner);
    final anchor = merklePath.root(node, context.saplingHashable());
    final ak = fvk.vk.ak;
    final s = SaplingSpend.build(
        proofGenerationKey: proofGenerationKey,
        diversifier: note.recipient.diversifier,
        rseed: note.rseed,
        value: note.value,
        alpha: b.alpha,
        rcv: rcv,
        anchor: anchor,
        merklePath: merklePath);
    final description = SaplingSpendDescription(
        cv: b.cv, anchor: anchor, nullifier: b.nullifier, rk: b.rk);
    return (
      description: description,
      spend: s,
      ak: ak,
      alpha: b.alpha,
      expsk: dummyExpsk?.ask,
    );
  }

  SaplingPcztSpend toPczt(ZCashCryptoContext context) {
    final b = _build(context);
    final dummyExpsk = this.dummyExpsk;
    SaplingProofGenerationKey? proofGenerationKey;
    if (dummyExpsk != null) {
      proofGenerationKey =
          SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(dummyExpsk);
    }
    return SaplingPcztSpend(
      nullifier: b.nullifier,
      rk: b.rk,
      cv: b.cv,
      recipient: note.recipient,
      value: note.value,
      rseed: note.rseed,
      rcv: rcv,
      proofGenerationKey: proofGenerationKey,
      alpha: b.alpha,
      dummySk: dummyExpsk?.ask,
      witness: merklePath,
    );
  }
}

class SaplingOutputInfoInner {
  final SaplingOutgoingViewingKey? ovk;
  final SaplingPaymentAddress to;
  final ZAmount value;
  final List<int> memo;
  SaplingOutputInfoInner(
      {this.ovk,
      required this.to,
      required this.value,
      required List<int> memo})
      : memo = memo.exc(
            length: NoteEncryptionConst.memoLength,
            operation: "SaplingOutputInfoInner",
            reason: "Invalid memo bytes length.");
  factory SaplingOutputInfoInner.dummy() {
    SaplingPaymentAddress to;
    while (true) {
      final d = Diversifier(QuickCrypto.generateRandom(11));
      final dummyIvk = SaplingIvk(JubJubNativeFr.random());
      try {
        to = dummyIvk.toPaymentAddress(d);
        break;
      } on SaplingKeyError catch (_) {}
    }
    return SaplingOutputInfoInner(
        to: to,
        value: ZAmount.zero(),
        memo: List.filled(NoteEncryptionConst.memoLength, 0));
  }
  SaplingOutputInfo prepare() {
    final rseed = SaplingRSeedAfterZip212.random();
    return SaplingOutputInfo._(
        note: SaplingNote(recipient: to, value: value, rseed: rseed),
        rcv: SaplingValueCommitTrapdoor.random(),
        memo: memo,
        ovk: ovk);
  }
}

class SaplingOutputInfo {
  final SaplingOutgoingViewingKey? ovk;
  final SaplingNote note;
  final SaplingValueCommitTrapdoor rcv;
  final List<int> memo;
  SaplingOutputInfo._(
      {this.ovk, required this.note, required this.rcv, required this.memo});

  ({
    SaplingValueCommitment cv,
    SaplingExtractedNoteCommitment cmu,
    EphemeralKeyBytes epk,
    List<int> encCiphertext,
    List<int> outCipherText,
    JubJubNativeFr esk
  }) _build(ZCashCryptoContext context) {
    final domain = SaplingDomainNative(context);
    final encryptor = domain.createNote(note: note, memo: memo, ovk: ovk);
    final cv = SaplingValueCommitment.derive(value: note.value, rcv: rcv);
    final cmu = note.cmu(context);
    final encCiphertext = domain.encryptNotePlaintext(encryptor);
    final outCipherText = domain.encryptOutgoingPlaintext(
        encryotedNote: encryptor, cm: cmu, cv: cv);
    final epk = encryptor.epk;
    final esk = encryptor.esk;
    return (
      cv: cv,
      cmu: cmu,
      epk: EphemeralKeyBytes(epk.toBytes()),
      encCiphertext: encCiphertext,
      outCipherText: outCipherText,
      esk: esk
    );
  }

  ({SaplingOutputDescription description, SaplingOutput output}) build(
      ZCashCryptoContext context) {
    final b = _build(context);
    final output = SaplingOutput.build(
        esk: b.esk,
        paymentAddress: note.recipient,
        rcm: note.rseed.rcm(),
        value: note.value,
        rcv: rcv);
    final outputDescription = SaplingOutputDescription(
      cv: b.cv,
      cmu: b.cmu,
      ephemeralKey: b.epk,
      encCiphertext: b.encCiphertext,
      outCiphertext: b.outCipherText,
    );
    return (description: outputDescription, output: output);
  }

  SaplingPcztOutput toPczt(ZCashCryptoContext context) {
    final b = _build(context);
    return SaplingPcztOutput(
      cv: b.cv,
      cmu: b.cmu,
      ephemeralKey: b.epk,
      encCiphertext: b.encCiphertext,
      outCiphertext: b.outCipherText,
      rcv: rcv,
      value: note.value,
      recipient: note.recipient,
      rseed: note.rseed.toBytes(),
    );
  }
}

class SaplingBuilder
    implements
        BundleBuilder<SaplingBundle, SaplingExtractedBundle, SaplingPcztBundle,
            SaplingBindingAuthorizingKey> {
  // ZAmount _valueBalance;
  List<SaplingSpendInfoInner> _spends;
  List<SaplingSpendInfoInner> get spends => _spends;
  List<SaplingOutputInfoInner> _outputs;
  List<SaplingOutputInfoInner> get outputs => _outputs;
  final SaplingBundleType bundleType;
  final SaplingAnchor anchor;
  final ZCashCryptoContext context;
  PcztBundleWithMetadata<SaplingBundle, SaplingExtractedBundle,
      SaplingPcztBundle>? _cachedPczt;
  SaplingBuilder(
      {required this.anchor,
      required this.bundleType,
      required this.context,
      ZAmount? balance,
      List<SaplingSpendInfoInner> spends = const [],
      List<SaplingOutputInfoInner> outputs = const []})
      : _spends = spends.immutable,
        _outputs = outputs.immutable;

  void _addSpend(SaplingSpendInfoInner spend) {
    _spends = [..._spends, spend].toImutableList;
    _cachedPczt = null;
  }

  void _addOutput(SaplingOutputInfoInner output) {
    _outputs = [..._outputs, output].toImutableList;
    _cachedPczt = null;
  }

  @override
  ZAmount valueBalance() =>
      spends.fold<ZAmount>(ZAmount.zero(), (p, c) => p + c.value()) -
      outputs.fold<ZAmount>(ZAmount.zero(), (p, c) => p + c.value);

  void addSpend({
    required SaplingFullViewingKey fvk,
    required SaplingNote note,
    required SaplingMerklePath merklePath,
    SaplingProofGenerationKey? proofGenerationKey,
  }) {
    final spend = SaplingSpendInfoInner._(
        fvk: fvk,
        note: note,
        merklePath: merklePath,
        generationKey: proofGenerationKey);
    switch (bundleType) {
      case SaplingBundleTypeTransactional():
        if (!spend.hasMatchingAnchor(anchor, context)) {
          throw SaplingBuilderException.operationFailed("addSpend",
              reason: "Anchor mismatch.");
        }
        break;
      default:
        throw SaplingBuilderException.operationFailed("addSpend",
            reason: "Unsupported bundle type.");
    }
    _addSpend(spend);
  }

  void setGenerationKey(
      {required int index,
      required SaplingProofGenerationKey proofGenerationKey}) {
    final spend = _spends.elementAtOrNull(index);
    if (spend == null) {
      throw SaplingBuilderException.operationFailed("setGenerationKey",
          reason: "Index out of range.");
    }
    if (proofGenerationKey.toViewingKey() != spend.fvk.vk) {
      throw SaplingBuilderException.operationFailed("setGenerationKey",
          reason: "Invalid proof generation key.");
    }
    final dummyExpsk = spend.dummyExpsk;
    if (dummyExpsk != null) {
      throw SaplingBuilderException.operationFailed("build",
          reason: "Invalid spending key.");
    }
    _cachedPczt ??= toPczt();
    final spends = _spends.clone();
    spends[index] = spend.copyWith(generationKey: proofGenerationKey);
    _spends = spends.immutable;
    final cachedPczt = _cachedPczt;
    if (cachedPczt != null) {
      index = cachedPczt.metadata.spendIndices[index];
      final pczt = _cachedPczt?.bundle.spends.elementAt(index);
      pczt?.setProofGenerationKey(proofGenerationKey);
    }
  }

  void addOutput(
      {SaplingOutgoingViewingKey? ovk,
      required SaplingPaymentAddress recipient,
      required ZAmount value,
      required List<int> memo}) {
    final output =
        SaplingOutputInfoInner(to: recipient, value: value, memo: memo);
    _addOutput(output);
  }

  @override
  BundleWithMetadata<SaplingBundle, SaplingBindingAuthorizingKey> build(
      [List<SaplingExtendedSpendingKey> extsks = const []]) {
    final bundle = _buildBundle();
    final valueBalance = bundle.value.asI64();
    final bsk = (bundle.spends.fold<SaplingTrapdoorSum>(
                SaplingTrapdoorSum.zero(), (p, c) => p + c.rcv) -
            bundle.outputs.fold<SaplingTrapdoorSum>(
                SaplingTrapdoorSum.zero(), (p, c) => p + c.rcv))
        .toBsk();
    final spends = bundle.spends.map((e) {
      SaplingProofGenerationKey? proofGenerationKey;
      final dummyExpsk = e.dummyExpsk;
      if (e.generationKey != null && dummyExpsk == null) {
        final key = extsks.firstWhereNullable((k) =>
            k.toExtendedFvk().toDiversifiableFullViewingKey().fvk == e.fvk);
        if (key != null) {
          proofGenerationKey =
              SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(key.sk);
        }
      }
      return e.build(context, proofGenerationKey: proofGenerationKey);
    });
    final outputs = bundle.outputs.map((e) => e.build(context)).toList();

    final bvk = (spends.fold(
                SaplingCommitmentSum.zero(), (p, c) => p + c.description.cv) -
            outputs.fold(
                SaplingCommitmentSum.zero(), (p, c) => p + c.description.cv))
        .toBvk(bundle.value);
    assert(bvk == bsk.toVerificationKey());
    final sBunle = SaplingBundle(
        shieldedSpends: spends.map((e) => e.description).toList(),
        shieldedOutputs: outputs.map((e) => e.description).toList(),
        valueBalance: valueBalance);
    return BundleWithMetadata(
        bundle: sBunle, data: bsk, metadata: bundle.metadata);
  }

  ({
    List<SaplingSpendInfo> spends,
    List<SaplingOutputInfo> outputs,
    ZAmount value,
    BundleMetadata metadata
  }) _buildBundle() {
    switch (bundleType) {
      case SaplingBundleTypeTransactional():
        for (final i in spends) {
          if (!i.hasMatchingAnchor(anchor, context)) {
            throw SaplingBuilderException.operationFailed("buildBundle",
                reason: "Anchor mismatch.");
          }
        }
        break;
      default:
        if (_spends.isNotEmpty) {
          throw SaplingBuilderException.operationFailed("buildBundle",
              reason: "Unsupported bundle type.");
        }
    }

    final numSpends = spends.length;
    final numOutputs = outputs.length;
    final bundleSpend = bundleType.numSpends(numSpends);
    final bundleOutput =
        bundleType.numOutputs(numSpends: numSpends, numOutputs: numOutputs);
    assert(numOutputs <= bundleOutput);
    final List<int> spendIndices = List.filled(spends.length, 0);
    final List<int> outputIndices = List.filled(outputs.length, 0);
    final indexedSpends = List.generate(bundleSpend,
            (i) => spends.elementAtOrNull(i) ?? SaplingSpendInfoInner.dummy())
        .indexed
        .toList()
      ..shuffle(QuickCrypto.prng);
    final indexedOutputs = List.generate(bundleOutput,
            (i) => outputs.elementAtOrNull(i) ?? SaplingOutputInfoInner.dummy())
        .indexed
        .toList()
      ..shuffle(QuickCrypto.prng);
    final spendsInfo = List.generate(indexedSpends.length, (i) {
      final (pos, spend) = indexedSpends.elementAt(i);
      if (pos < spends.length) {
        spendIndices[pos] = i;
      }
      return spend.prepare();
    });
    final outputsInfo = List.generate(indexedOutputs.length, (i) {
      final (pos, output) = indexedOutputs.elementAt(i);
      if (pos < outputs.length) {
        outputIndices[pos] = i;
      }
      return output.prepare();
    });
    final totalInput =
        spendsInfo.fold(ZAmount.zero(), (p, c) => p + c.note.value);
    final valueBalance =
        outputsInfo.fold(totalInput, (p, c) => p - c.note.value);
    return (
      spends: spendsInfo,
      outputs: outputsInfo,
      value: valueBalance,
      metadata: BundleMetadata(
          outputIndices: outputIndices, spendIndices: spendIndices)
    );
  }

  @override
  PcztBundleWithMetadata<SaplingBundle, SaplingExtractedBundle,
      SaplingPcztBundle> toPczt() {
    final pczt = _cachedPczt ??= () {
      final bundle = _buildBundle();
      final spends = bundle.spends.map((e) => e.toPczt(context)).toList();
      final outputs = bundle.outputs.map((e) => e.toPczt(context)).toList();
      final pczt = SaplingPcztBundle(
          spends: spends,
          outputs: outputs,
          valueSum: bundle.value,
          anchor: anchor);
      return PcztBundleWithMetadata<SaplingBundle, SaplingExtractedBundle,
          SaplingPcztBundle>(bundle: pczt, metadata: bundle.metadata);
    }();
    return pczt.clone();
  }
}
