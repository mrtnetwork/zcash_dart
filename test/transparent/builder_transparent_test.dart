import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:zcash_dart/src/transaction/builders/exception.dart';
import 'package:zcash_dart/zcash.dart';

void main() async {
  await _test();
}

Future<void> _test() async {
  test("Transparent builder", () async {
    final context = DefaultZCashCryptoContext.lazy();
    final account = ZECPrivate.fromHex(
        "8be14936d4857d2f57902dccf8d6e388bfb85a37d9d6e5b69d4efa80ed4af6b5");
    final builder = TransactionBuilder(
        network: ZCashNetwork.mainnet,
        targetHeight: 10000000,
        config: TransactionBuildConfigStandard(),
        context: context);
    await builder.addTransparentSpend(
        TransparentUtxoWithOwner(
            utxo: TransparentUtxo(
                txHash: List<int>.filled(32, 1),
                value: BigInt.from(1000000),
                vout: 1),
            ownerDetails: TransparentUtxoOwner(
                publicKey: account.toPublicKey(),
                address: account.toPublicKey().toAddress())),
        sighash: BitcoinOpCodeConst.sighashAnyoneCanPay);
    await builder.addOutput(
        traget: TransactionOutputTarget.orchard(
            orchardAddress: OrchardAddress.fromBytes([
          ...DiversifierIndex.zero().toBytes(),
          ...PallasNativePoint.random().toBytes(),
        ])),
        amount: ZAmount.from(100000));

    expect(
        () async => await builder.addTransparentSpend(TransparentUtxoWithOwner(
            utxo: TransparentUtxo(
                txHash: List<int>.filled(32, 1),
                value: BigInt.from(2000000),
                vout: 1),
            ownerDetails: TransparentUtxoOwner(
                publicKey: account.toPublicKey(),
                address: account.toPublicKey().toAddress()))),
        throwsA(isA<TransparentBuilderException>()));
    await builder.signTransparent(index: 0, sk: account);
    await builder.addTransparentSpend(TransparentUtxoWithOwner(
        utxo: TransparentUtxo(
            txHash: List<int>.filled(32, 1), value: BigInt.from(200), vout: 3),
        ownerDetails: TransparentUtxoOwner(
            publicKey: account.toPublicKey(),
            address: account.toPublicKey().toAddress())));
    await builder.signTransparent(index: 1, sk: account);
    expect(
        () async => await builder.addTransparentSpend(TransparentUtxoWithOwner(
            utxo: TransparentUtxo(
                txHash: List<int>.filled(32, 1),
                value: BigInt.from(2000000),
                vout: 2),
            ownerDetails: TransparentUtxoOwner(
                publicKey: account.toPublicKey(),
                address: account.toPublicKey().toAddress()))),
        throwsA(isA<TransactionBuilderException>()));
    ZAmount value = builder.valueBalance();
    expect(value,
        ZAmount(BigInt.from(1000000) - BigInt.from(100000) + BigInt.from(200)));
  });

  test("Transparent builder", () async {
    final context = DefaultZCashCryptoContext.lazy();
    final account = ZECPrivate.fromHex(
        "8be14936d4857d2f57902dccf8d6e388bfb85a37d9d6e5b69d4efa80ed4af6b5");
    final builder = TransactionBuilder(
        network: ZCashNetwork.mainnet,
        targetHeight: 10000000,
        config: TransactionBuildConfigStandard(),
        context: context);
    await builder.addTransparentSpend(
      TransparentUtxoWithOwner(
          utxo: TransparentUtxo(
              txHash: List<int>.filled(32, 1),
              value: BigInt.from(1000000),
              vout: 1),
          ownerDetails: TransparentUtxoOwner(
              publicKey: account.toPublicKey(),
              address: account.toPublicKey().toAddress())),
    );
    await builder.addOutput(
        traget: TransactionOutputTarget.orchard(
            orchardAddress: OrchardAddress.fromBytes([
          ...DiversifierIndex.zero().toBytes(),
          ...PallasNativePoint.random().toBytes(),
        ])),
        amount: ZAmount.from(100000));
    final fee = await builder.addChange(
        traget: TransactionOutputTarget.orchard(
            orchardAddress: OrchardAddress.fromBytes([
      ...DiversifierIndex.zero().toBytes(),
      ...PallasNativePoint.random().toBytes(),
    ])));
    ZAmount value = builder.valueBalance();
    final outputs = BigInt.from(1000000) - fee.value;
    expect(value - fee, ZAmount.zero());
    await builder.signTransparent(index: 0, sk: account);
    expect(() async => await builder.extractTransaction(),
        throwsA(isA<TransactionBuilderException>()));
    await builder.setOrchardProof(OrchardProof(List<int>.filled(100, 0)));
    final tx = await builder.extractTransaction(verifyProofs: false);
    expect(tx.transactionData.transparentBundle?.vin.length, 1);
    expect(tx.transactionData.transparentBundle?.vout.length, 0);
    expect(tx.transactionData.orchardBundle?.actions.length, 2);
    expect(tx.transactionData.orchardBundle?.balance, ZAmount(-outputs));
  });
}
