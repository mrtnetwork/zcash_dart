part of 'builder.dart';

mixin TransactionBuilderSignerContoller on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller {
  Future<void> proofSapling() async {
    await _finalizeIo(
      (pczt) async {
        await pczt.pczt.createSaplingProofs(context);
      },
    );
  }

  Future<void> proofOrchard() async {
    await _finalizeIo(
      (pczt) async {
        await pczt.pczt.createOrchardProof(context);
      },
    );
  }

  Future<void> setOrchardProof(OrchardProof proof) async {
    await _finalizeIo(
      (pczt) async {
        pczt.pczt.setOrchardProof(proof);
      },
    );
  }

  Future<void> setSaplingSpendProof(int index, GrothProofBytes proof) async {
    await _finalizeIo(
      (pczt) async {
        pczt.pczt.setSaplingSpendProof(pczt.sapling.spendIndices[index], proof);
      },
    );
  }

  Future<void> setSaplingOutputProof(int index, GrothProofBytes proof) async {
    await _finalizeIo(
      (pczt) async {
        pczt.pczt
            .setSaplingOutputProof(pczt.sapling.outputIndices[index], proof);
      },
    );
  }

  Future<void> signSapling(
      {required int index, required SaplingSpendAuthorizingKey ask}) async {
    await _finalizeIo((pczt) {
      index = pczt.sapling.spendIndices[index];
      final spend = pczt.pczt.sapling.spends.elementAtOrNull(index);
      if (spend == null) {
        throw PcztException.failed("signSapling",
            reason: "Index out of range.", details: {"index": index});
      }
      if (spend.spendAuthSig != null) {
        throw TransactionBuilderException.failed("signSapling",
            reason: "Index already signed");
      }
      return pczt.pczt.signSapling(index: index, ask: ask, context: context);
    });
  }

  Future<void> signTransparent(
      {required int index, required ZECPrivate sk}) async {
    await _finalizeTransparent(
      (pczt) {
        return pczt.signTransparent(index: index, sk: sk, context: context);
      },
    );
  }

  Future<void> signOrchard(
      {required int index, required OrchardSpendAuthorizingKey ask}) async {
    await _finalizeIo((pczt) {
      index = pczt.orchard.spendIndices[index];
      final action = pczt.pczt.orchard.actions.elementAtOrNull(index);
      if (action == null) {
        throw PcztException.failed("signSapling",
            reason: "Index out of range.", details: {"index": index});
      }
      if (action.spend.spendAuthSig != null) {
        throw TransactionBuilderException.failed("signOrchard",
            reason: "Index already signed");
      }
      return pczt.pczt.signOrchard(index: index, ask: ask, context: context);
    });
  }

  Future<void> setSaplingProofGenerationKey(
      {required int index,
      SaplingProofGenerationKey? proofGenerationKey,
      SaplingExpandedSpendingKey? expsk}) async {
    if (proofGenerationKey == null && expsk == null) {
      throw TransactionBuilderException.failed("setSaplingProofGenerationKey",
          reason: "Missing proof generation key.");
    }
    final pgk = proofGenerationKey ??=
        SaplingProofGenerationKey.fromSaplingExpandedSpendingKey(expsk!);
    await _modify(
      (shieldedModifiable, inputsModifiable, outputsModifiable) async {
        sapling.setGenerationKey(index: index, proofGenerationKey: pgk);
      },
    );
  }
}
