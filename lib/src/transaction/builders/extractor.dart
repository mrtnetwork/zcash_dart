part of 'builder.dart';

mixin TransactionBuilderExtractor on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller {
  Future<ZcashTransaction> extractTransaction({
    bool verifyProofs = true,
    bool verifySignatures = true,
    // required int orchardVersion,
    // bool disableCrossAddress = false,
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
      } on BuError catch (e) {
        if (e.type == ZcashErrorType.pcztFailed ||
            e.type == ZcashErrorType.saplingPcztFailed ||
            e.type == ZcashErrorType.orchardPcztFailed ||
            e.type == ZcashErrorType.transparentPcztFailed) {
          throw BuError(
            ZcashErrorType.txBuilderFailed,
            e.message,
            details: e.details,
          );
        }
        rethrow;
      }
    });
  }

  Future<ZcashTxId> extractAndSendTransaction(
    ZcashWalletdProvider provider, {
    bool verifyProofs = true,
    bool verifySignatures = true,
    // required int orchardVersion,
    // bool disableCrossAddress = false,
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
    // A successful send returns error_code 0 and the txid in error_message.
    // Proto3 does not put default (zero) values on the wire, so a successful
    // reply deserializes error_code as null: treat null as 0.
    final errorCode = result.errorCode ?? 0;
    if (errorCode != 0) {
      throw ZcashErrors.txBuilderFailed(
        "extractAndSendTransaction",
        reason: result.errorMessage,
        details: {"code": errorCode.toString()},
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
