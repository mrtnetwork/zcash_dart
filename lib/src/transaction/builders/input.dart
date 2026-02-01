part of 'builder.dart';

mixin TransactionBuilderInputContoller on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller {
  Future<void> addOrchardSpend(
      {required OrchardFullViewingKey fvk,
      required OrchardNote note,
      required OrchardMerklePath merklePath}) async {
    await _modify(
      (shieldedModifiable, inputsModifiable, outputsModifiable) async {
        if (!shieldedModifiable) {
          throw TransactionBuilderException.failed("addOutput",
              reason:
                  "Shielded inputs are marked as unmodifiable by the builder.");
        }
        orchard.addSpend(fvk: fvk, note: note, merklePath: merklePath);
      },
    );
  }

  Future<void> addSaplingSpend(
      {required SaplingFullViewingKey fvk,
      required SaplingNote note,
      required SaplingMerklePath merklePath}) async {
    await _modify(
      (shieldedModifiable, inputsModifiable, outputsModifiable) async {
        if (!shieldedModifiable) {
          throw TransactionBuilderException.failed("addOutput",
              reason:
                  "Shielded inputs are marked as unmodifiable by the builder.");
        }
        sapling.addSpend(fvk: fvk, note: note, merklePath: merklePath);
      },
    );
  }

  Future<void> addTransparentSpend(TransparentUtxoWithOwner input,
      {int? sighash}) async {
    await _modify(
      (shieldedModifiable, inputsModifiable, outputsModifiable) async {
        if (!inputsModifiable) {
          throw TransactionBuilderException.failed("addOutput",
              reason:
                  "transparent inputs are marked as unmodifiable by the builder.");
        }
        transparent.addInput(input, sighash: sighash);
      },
    );
  }
}
