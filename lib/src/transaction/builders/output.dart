part of 'builder.dart';

mixin TransactionBuilderOutputContoller on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller, TransactionBuilderFeeContoller {
  List<int> _getMemo(List<int>? memo) {
    if (memo == null) return List.filled(NoteEncryptionConst.memoLength, 0);
    if (memo.length > NoteEncryptionConst.memoLength) {
      throw ZcashErrors.txBuilderFailed("addOutput", reason: "");
    }
    if (memo.length == NoteEncryptionConst.memoLength) {
      return memo;
    }
    final m = List.filled(NoteEncryptionConst.memoLength, 0);
    m.setAll(0, memo);
    return m;
  }

  void _validateOutputParams({
    required TransactionOutputTarget target,
    required bool shieldedModifiable,
    required bool inputsModifiable,
    required bool outputsModifiable,
    List<int>? shieldMemo,
  }) {
    switch (target) {
      case TransparentOutputTarget _:
        if (!outputsModifiable) {
          throw ZcashErrors.txBuilderFailed(
            "addOutput",
            reason:
                "Transparent outputs are marked as unmodifiable by the builder.",
          );
        }
        if (shieldMemo != null) {
          throw ZcashErrors.txBuilderFailed(
            "addOutput",
            reason: "Memo not allowed in transparent output.",
          );
        }
        break;
      case SaplingOutputTarget _:
        if (!shieldedModifiable) {
          throw ZcashErrors.txBuilderFailed(
            "addOutput",
            reason:
                "Shielded outputs are marked as unmodifiable by the builder.",
          );
        }
        break;
      case OrchardOutputTarget _:
        if (!shieldedModifiable) {
          throw ZcashErrors.txBuilderFailed(
            "addOutput",
            reason:
                "Shielded outputs are marked as unmodifiable by the builder.",
          );
        }
        break;
      case IronwoodOutputTarget _:
        if (!shieldedModifiable) {
          throw ZcashErrors.txBuilderFailed(
            "addOutput",
            reason:
                "Shielded outputs are marked as unmodifiable by the builder.",
          );
        }
        break;
    }
  }

  Future<int> _addOutput({
    required TransactionOutputTarget target,
    required ZAmount amount,
    required bool shieldedModifiable,
    required bool inputsModifiable,
    required bool outputsModifiable,
    List<int>? shieldMemo,
  }) async {
    _validateOutputParams(
      target: target,
      shieldedModifiable: shieldedModifiable,
      inputsModifiable: inputsModifiable,
      outputsModifiable: outputsModifiable,
    );
    switch (target) {
      case TransparentOutputTarget target:
        final receipt = target.recipient;
        if (receipt case TransparentNullDataOutput _) {
          if (!amount.isZero()) {
            throw ZcashErrors.txBuilderFailed(
              "addOutput",
              reason: "Value for null data output must be zero.",
            );
          }
          return transparent.addOutput(receipt);
        }
        if (receipt case TransparentSpendableOutput output) {
          return transparent.addOutput(
            TransparentSpendableOutput(
              address: output.address,
              value: amount.toZatoshi(),
            ),
          );
        }
        throw ZcashErrors.txBuilderFailed(
          "addOutput",
          reason: "Invalid transport output target.",
        );
      case SaplingOutputTarget target:
        return sapling.addOutput(
          recipient: target.recipient,
          value: amount.asZatoshi(),
          memo: _getMemo(shieldMemo),
        );
      case OrchardOutputTarget target:
        return orchard.addOutput(
          recipient: target.recipient,
          value: amount.asZatoshi(),
          memo: _getMemo(shieldMemo),
        );
      case IronwoodOutputTarget target:
        return ironwood.addOutput(
          recipient: target.recipient,
          value: amount.asZatoshi(),
          memo: _getMemo(shieldMemo),
        );
    }
  }

  Future<int> addOutput({
    required TransactionOutputTarget target,
    required ZAmount amount,
    List<int>? shieldMemo,
  }) async {
    return await _modify(
      (shieldedModifiable, inputsModifiable, outputsModifiable) => _addOutput(
        target: target,
        amount: amount,
        shieldedModifiable: shieldedModifiable,
        inputsModifiable: inputsModifiable,
        outputsModifiable: outputsModifiable,
        shieldMemo: shieldMemo,
      ),
    );
  }

  Future<bool> _addChangeOutput({
    required OrchardBuilder builder,
    required OrchardFullViewingKey fvk,
    required OrchardAddress recipient,
    required ZAmount amount,
    Bip44Changes? scope,
    List<int>? shieldMemo,
  }) async {
    return await _modify((
      shieldedModifiable,
      inputsModifiable,
      outputsModifiable,
    ) async {
      if (!shieldedModifiable) {
        throw ZcashErrors.txBuilderFailed(
          "addChangeOutput",
          reason: "Shielded outputs are marked as unmodifiable by the builder.",
        );
      }
      return builder.addChangeOutput(
        fvk: fvk,
        recipient: recipient,
        value: amount.asZatoshi(),
        memo: _getMemo(shieldMemo),
        scope: scope,
      );
    });
  }

  /// Adds a wallet-controlled Orchard change output. Required for
  /// retaining Orchard funds under NU6.3, where plain outputs are
  /// rejected in cross-address-restricted bundles. Returns whether the
  /// change was recorded (`false` when skipped as zero-valued).
  Future<bool> addOrchardChangeOutput({
    required OrchardFullViewingKey fvk,
    required OrchardAddress recipient,
    required ZAmount amount,
    Bip44Changes? scope,
    List<int>? shieldMemo,
  }) => _addChangeOutput(
    builder: orchard,
    fvk: fvk,
    recipient: recipient,
    amount: amount,
    scope: scope,
    shieldMemo: shieldMemo,
  );

  /// Adds a wallet-controlled Ironwood change output. Returns whether
  /// the change was recorded (`false` when skipped as zero-valued).
  Future<bool> addIronwoodChangeOutput({
    required OrchardFullViewingKey fvk,
    required OrchardAddress recipient,
    required ZAmount amount,
    Bip44Changes? scope,
    List<int>? shieldMemo,
  }) => _addChangeOutput(
    builder: ironwood,
    fvk: fvk,
    recipient: recipient,
    amount: amount,
    scope: scope,
    shieldMemo: shieldMemo,
  );

  Future<ZAmount> addChange({
    required TransactionOutputTarget target,
    List<int>? shieldMemo,
  }) async {
    return await _modify((
      shieldedModifiable,
      inputsModifiable,
      outputsModifiable,
    ) async {
      ZAmount value = valueBalance();
      if (value.value <= BigInt.zero) {
        throw ZcashErrors.txBuilderFailed(
          "addChange",
          reason: "No positive change is available to add.",
        );
      }
      int saplingOutput = sapling.outputs.length;
      int orchardOutput = orchard.outputs.length + orchard.changes.length;
      int ironwoodOutput = ironwood.outputs.length + ironwood.changes.length;
      int transparentOutput = transparent.outputSizes();
      switch (target) {
        case TransparentOutputTarget target:
          transparentOutput +=
              target.recipient.toOutput().toSerializeBytes().length;
          break;
        case SaplingOutputTarget _:
          saplingOutput += 1;

          break;
        case OrchardOutputTarget _:
          orchardOutput += 1;
          break;
        case IronwoodOutputTarget _:
          ironwoodOutput += 1;
          break;
      }
      final numOrchardActions = orchard.bundleType.numActions(
        numSpends: orchard.spends.length,
        numOutputs: orchardOutput,
        crossAddressEnabled: !orchard.isRestricted,
      );
      final numIronwoodActions = ironwood.bundleType.numActions(
        numSpends: ironwood.spends.length,
        numOutputs: ironwoodOutput,
        crossAddressEnabled: !ironwood.isRestricted,
      );
      final fee = feeBuilder.feeRequired(
        network: network,
        targetHeight: targetHeight,
        trasparentInputSizes: transparent.inputSizes(),
        transparentOutputSizes: transparentOutput,
        saplingInputCount: sapling.spends.length,
        saplingOutputCount: sapling.bundleType.numOutputs(
          numSpends: sapling.spends.length,
          numOutputs: saplingOutput,
        ),
        orchardActionCount: numOrchardActions,
        ironwoodActionCount: numIronwoodActions,
      );
      value -= fee;
      if (value.isNegative()) {
        throw ZcashErrors.txBuilderFailed(
          "addChange",
          reason: "Insufficient balance to cover the required transaction fee.",
          details: {"requiredFee": fee.toString()},
        );
      }
      if (value.isZero()) return fee;
      await _addOutput(
        target: target,
        amount: value,
        shieldedModifiable: shieldedModifiable,
        inputsModifiable: inputsModifiable,
        outputsModifiable: outputsModifiable,
        shieldMemo: shieldMemo,
      );
      value = valueBalance() - fee;
      if (!value.isZero()) {
        throw ZcashErrors.txBuilderFailed(
          "addChange",
          reason:
              "Internal builder invariant violated: change was not fully consumed.",
        );
      }
      return fee;
    });
  }
}
