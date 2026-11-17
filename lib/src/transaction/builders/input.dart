part of 'builder.dart';

mixin TransactionBuilderInputContoller on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller {
  Future<int> addOrchardSpend({
    required OrchardFullViewingKey fvk,
    required OrchardNote note,
    required OrchardMerklePath merklePath,
  }) async {
    return await _modify((
      shieldedModifiable,
      inputsModifiable,
      outputsModifiable,
    ) async {
      if (!shieldedModifiable) {
        throw ZcashErrors.txBuilderFailed(
          "addOutput",
          reason: "Shielded inputs are marked as unmodifiable by the builder.",
        );
      }
      return orchard.addSpend(fvk: fvk, note: note, merklePath: merklePath);
    });
  }

  /// Adds an Ironwood-pool spend (NU6.3). Same key and note types as the
  /// Orchard pool; pool membership is selected by this method. Cross-pool
  /// spends (Ironwood notes) cannot go through [addOrchardSpend].
  Future<int> addIronwoodSpend({
    required OrchardFullViewingKey fvk,
    required OrchardNote note,
    required OrchardMerklePath merklePath,
  }) async {
    return await _modify((
      shieldedModifiable,
      inputsModifiable,
      outputsModifiable,
    ) async {
      if (!shieldedModifiable) {
        throw ZcashErrors.txBuilderFailed(
          "addOutput",
          reason: "Shielded inputs are marked as unmodifiable by the builder.",
        );
      }
      return ironwood.addSpend(fvk: fvk, note: note, merklePath: merklePath);
    });
  }

  Future<int> addSaplingSpend({
    required SaplingFullViewingKey fvk,
    required SaplingNote note,
    required SaplingMerklePath merklePath,
    SaplingProofGenerationKey? proofGenerationKey,
  }) async {
    return await _modify((
      shieldedModifiable,
      inputsModifiable,
      outputsModifiable,
    ) async {
      if (!shieldedModifiable) {
        throw ZcashErrors.txBuilderFailed(
          "addOutput",
          reason: "Shielded inputs are marked as unmodifiable by the builder.",
        );
      }
      return sapling.addSpend(
        fvk: fvk,
        note: note,
        merklePath: merklePath,
        proofGenerationKey: proofGenerationKey,
      );
    });
  }

  Future<int> addTransparentSpend(TransparentSigningInput input) async {
    return await _modify((
      shieldedModifiable,
      inputsModifiable,
      outputsModifiable,
    ) async {
      if (!inputsModifiable) {
        throw ZcashErrors.txBuilderFailed(
          "addOutput",
          reason:
              "transparent inputs are marked as unmodifiable by the builder.",
        );
      }
      return transparent.addInput(input);
    });
  }
}
