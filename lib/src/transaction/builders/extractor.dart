part of 'builder.dart';

mixin TransactionBuilderExtractor on BaseTransactionBuilder
    implements TransactionBuilderPcztContoller {
  Future<ZCashTransaction> extractTransaction(
      {bool verifyProofs = true}) async {
    return lock.run(() async {
      try {
        final pczt = _getPczt().clone();
        await pczt.pczt.finalizeIo(context);
        pczt.pczt.finalizeSpends();
        final extract =
            await pczt.pczt.extract(context, verifyProofs: verifyProofs);
        return extract;
      } on PcztException catch (e) {
        throw TransactionBuilderException(e.message, details: e.details);
      }
    });
  }

  Future<ZCashTxId> extractAndSendTransaction(
      ZCashWalletdProvider provider) async {
    final tx = await extractTransaction();
    final txBytes = tx.transactionData.toSerializeBytes();
    final result = await provider.request(
        ZWalletdRequestSendTransaction(WalletdRawTransaction(data: txBytes)));
    if (result.errorCode != 0) {
      throw TransactionBuilderException.failed("extractAndSendTransaction",
          reason: result.message, details: {"code": result.errorCode});
    }
    final message = result.message;

    assert(message == null || StringUtils.hexEqual(message, tx.txId.toTxId()));
    return tx.txId;
  }
}
