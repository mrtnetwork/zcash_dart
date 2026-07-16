part of 'builder.dart';

mixin TransactionBuilderOutputContoller on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller, TransactionBuilderFeeContoller {
  List<int> _getMemo(List<int>? memo) {
    if (memo == null) return List.filled(NoteEncryptionConst.memoLength, 0);
    if (memo.length > NoteEncryptionConst.memoLength) {
      throw TransactionBuilderException.failed("addOutput", reason: "");
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
          throw TransactionBuilderException.failed(
            "addOutput",
            reason:
                "Transparent outputs are marked as unmodifiable by the builder.",
          );
        }
        if (shieldMemo != null) {
          throw TransactionBuilderException.failed(
            "addOutput",
            reason: "Memo not allowed in transparent output.",
          );
        }
        break;
      case SaplingOutputTarget _:
        if (!shieldedModifiable) {
          throw TransactionBuilderException.failed(
            "addOutput",
            reason:
                "Shielded outputs are marked as unmodifiable by the builder.",
          );
        }
        break;
      case OrchardOutputTarget _:
        if (!shieldedModifiable) {
          throw TransactionBuilderException.failed(
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
            throw TransactionBuilderException.failed(
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
        throw TransactionBuilderException.failed(
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
        throw TransactionBuilderException.failed(
          "addChange",
          reason: "No positive change is available to add.",
        );
      }
      int saplingOutput = sapling.outputs.length;
      int orchardOutput = orchard.outputs.length;
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
      }
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
        orchardActionCount: orchard.bundleType.numActions(
          numSpends: orchard.spends.length,
          numOutputs: orchardOutput,
        ),
      );
      value -= fee;
      if (value.isNegative()) {
        throw TransactionBuilderException.failed(
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
        throw TransactionBuilderException.failed(
          "addChange",
          reason:
              "Internal builder invariant violated: change was not fully consumed.",
        );
      }
      return fee;
    });
  }
}
