part of 'builder.dart';

mixin TransactionBuilderSignerContoller on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller {
  Future<void> proofSapling() async {
    await _finalizeIo((pczt) async {
      await pczt.pczt.createSaplingProofs(context);
    });
  }

  Future<void> proofOrchard() async {
    await _finalizeIo((pczt) async {
      await pczt.pczt.createOrchardProof(
        context: context,
        version: pczt.pczt.orchard.bundleVersion.protocolVersion,
      );
    });
  }

  /// Pproves the trailing Ironwood bundle. The Ironwood
  /// pool exists only as V3, so the version is fixed here instead of
  /// being a caller parameter. No-op when no Ironwood spends/outputs
  /// were added.
  Future<void> proofIronwood() async {
    await _finalizeIo((pczt) async {
      await pczt.pczt.createIronwoodProof(
        context: context,
        version: OrchardProtocolVersion.v3,
      );
    });
  }

  Future<void> setOrchardProof(OrchardProof proof) async {
    await _finalizeIo((pczt) async {
      pczt.pczt.setOrchardProof(proof);
    });
  }

  Future<void> setSaplingSpendProof(int index, GrothProofBytes proof) async {
    await _finalizeIo((pczt) async {
      pczt.pczt.setSaplingSpendProof(pczt.sapling.spendIndices[index], proof);
    });
  }

  Future<void> setSaplingOutputProof(int index, GrothProofBytes proof) async {
    await _finalizeIo((pczt) async {
      pczt.pczt.setSaplingOutputProof(pczt.sapling.outputIndices[index], proof);
    });
  }

  Future<void> signSapling({
    required int index,
    required RedJubJubSpendPrivateKey ask,
  }) async {
    await _finalizeIo((pczt) {
      index = pczt.sapling.spendIndices[index];
      final spend = pczt.pczt.sapling.spends.elementAtOrNull(index);
      if (spend == null) {
        throw ZcashErrors.pcztFailed(
          "signSapling",
          reason: "Index out of range.",
          details: {"index": index.toString()},
        );
      }
      if (spend.spendAuthSig != null) {
        throw ZcashErrors.txBuilderFailed(
          "signSapling",
          reason: "Index already signed",
        );
      }
      return pczt.pczt.signSapling(index: index, ask: ask, context: context);
    });
  }

  Future<void> signTransparent({
    required int index,
    required ZECPrivate sk,
  }) async {
    await _finalizeTransparent((pczt) {
      return pczt.signTransparent(index: index, sk: sk, context: context);
    });
  }

  Future<void> signOrchard({
    required int index,
    required RedPallasSpendPrivateKey ask,
  }) async {
    await _finalizeIo((pczt) {
      index = pczt.orchard.spendIndices[index];
      final action = pczt.pczt.orchard.actions.elementAtOrNull(index);
      if (action == null) {
        throw ZcashErrors.pcztFailed(
          "signSapling",
          reason: "Index out of range.",
          details: {"index": index.toString()},
        );
      }
      if (action.spend.spendAuthSig != null) {
        throw ZcashErrors.txBuilderFailed(
          "signOrchard",
          reason: "Index already signed",
        );
      }
      return pczt.pczt.signOrchard(index: index, ask: ask, context: context);
    });
  }

  /// signs the wallet-controlled fabricated spend paired
  /// with change output [changeIndex] (restricted Orchard pool: retained
  /// value must arrive as change, and the paired zero spend carries no
  /// dummy key — only the change account's key can authorize it).
  /// [changeIndex] is the insertion order of `addOrchardChangeOutput`
  /// calls. Throws when the pool has no such fabricated spend.
  Future<void> signOrchardChange({
    required int changeIndex,
    required RedPallasSpendPrivateKey ask,
  }) async {
    await _finalizeIo((pczt) {
      final mapped = pczt.orchard.changeSpendIndices.elementAtOrNull(
        changeIndex,
      );
      if (mapped == null) {
        throw ZcashErrors.pcztFailed(
          "signOrchardChange",
          reason: "No fabricated spend for change index.",
          details: {"index": changeIndex.toString()},
        );
      }
      final action = pczt.pczt.orchard.actions.elementAtOrNull(mapped);
      if (action == null) {
        throw ZcashErrors.pcztFailed(
          "signOrchardChange",
          reason: "Index out of range.",
          details: {"index": mapped.toString()},
        );
      }
      if (action.spend.spendAuthSig != null) {
        throw ZcashErrors.txBuilderFailed(
          "signOrchardChange",
          reason: "Index already signed",
        );
      }
      return pczt.pczt.signOrchard(index: mapped, ask: ask, context: context);
    });
  }

  /// Signs one Ironwood-pool spend (trailing PCZT slot).
  /// Same key types as the Orchard pool — pool membership is selected by
  /// this method, mirroring [addIronwoodSpend] on the input side.
  Future<void> signIronwood({
    required int index,
    required RedPallasSpendPrivateKey ask,
  }) async {
    await _finalizeIo((pczt) {
      index = pczt.ironwood.spendIndices[index];
      final action = pczt.pczt.ironwood?.actions.elementAtOrNull(index);
      if (action == null) {
        throw ZcashErrors.pcztFailed(
          "signIronwood",
          reason: "Index out of range.",
          details: {"index": index.toString()},
        );
      }
      if (action.spend.spendAuthSig != null) {
        throw ZcashErrors.txBuilderFailed(
          "signIronwood",
          reason: "Index already signed",
        );
      }
      return pczt.pczt.signIronwood(index: index, ask: ask, context: context);
    });
  }

  Future<void> setSaplingProofGenerationKey({
    required int index,
    SaplingProofGenerationKey? proofGenerationKey,
    SaplingExpandedSpendingKey? expsk,
  }) async {
    if (proofGenerationKey == null && expsk == null) {
      throw ZcashErrors.txBuilderFailed(
        "setSaplingProofGenerationKey",
        reason: "Missing proof generation key.",
      );
    }
    final pgk =
        proofGenerationKey ??=
            SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(expsk!);
    await _modify((
      shieldedModifiable,
      inputsModifiable,
      outputsModifiable,
    ) async {
      sapling.setGenerationKey(index: index, proofGenerationKey: pgk);
    });
  }
}
