part of 'builder.dart';

mixin TransactionBuilderExtractor on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller {
  Future<ZcashTransaction> extractTransaction({
    bool verifyProofs = true,
    bool verifySignatures = true,
  }) async {
    return lock.run(() async {
      try {
        final pczt = _getPczt().clone();
        await pczt.pczt.finalizeIo(context);
        pczt.pczt.finalizeSpends();
        final extract = await pczt.pczt.extract(
          context,
          verifyProofs: verifyProofs,
          verifySignatures: verifySignatures,
        );
        return extract;
      } on PcztException catch (e) {
        throw TransactionBuilderException(e.message, details: e.details);
      }
    });
  }

  Future<ZcashTxId> extractAndSendTransaction(
    ZcashWalletdProvider provider, {
    bool verifyProofs = true,
    bool verifySignatures = true,
  }) async {
    final tx = await extractTransaction(
      verifyProofs: verifyProofs,
      verifySignatures: verifySignatures,
    );
    final txBytes = tx.transactionData.toSerializeBytes();
    final result = await provider.request(
      ZcashGrpcRequestMessage(
        request: ZWalletdSendTransaction(
          sendTransaction: ZWalletdRawTransaction(data: txBytes),
        ),
      ),
    );
    if (result.errorCode != 0) {
      throw TransactionBuilderException.failed(
        "extractAndSendTransaction",
        reason: result.errorMessage,
        details: {"code": result.errorCode.toString()},
      );
    }
    final message = result.errorMessage;
    assert(
      message == null ||
          !StringUtils.isHexBytes(message) ||
          StringUtils.hexEqual(message, tx.txId.txId),
    );
    return tx.txId;
  }
}
