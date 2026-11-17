// import 'package:bitcoin_base/bitcoin_base.dart';
// import 'package:blockchain_utils/blockchain_utils.dart';
// import 'package:test/expect.dart';
// import 'package:test/scaffolding.dart';
// import 'package:zcash_dart/zcash.dart';

// import '../utils.dart';
// void builderTransparentTest() {
//   test("Transparent builder", () async {
//     final context = DefaultZcashCryptoContext.lazy();
//     final account = ZECPrivate.fromHex(
//       "8be14936d4857d2f57902dccf8d6e388bfb85a37d9d6e5b69d4efa80ed4af6b5",
//     );
//     final builder = TransactionBuilder(
//       network: ZcashNetwork.mainnet,
//       targetHeight: 10000000,
//       config: TransactionBuildConfigStandard(),
//       context: context,
//     );
//     await builder.addTransparentSpend(
//       TransparentSigningInput(
//         input: TransparentUtxoWithOwner(
//           utxo: TransparentUtxo(
//             txHash: ZcashTxId(List<int>.filled(32, 1)),
//             value: BigInt.from(1000000),
//             vout: 1,
//             blockHeight: 0,
//           ),
//           ownerDetails: TransparentUtxoOwner(
//             publicKey: account.toPublicKey(),
//             address: account.toPublicKey().toAddress(),
//           ),
//         ),
//         sighash: BitcoinOpCodeConst.sighashAnyoneCanPay,
//       ),
//     );
//     await builder.addOutput(
//       target: TransactionOutputTarget.orchard(
//         orchardAddress: OrchardAddress.fromBytes([
//           ...DiversifierIndex.zero().toBytes(),
//           ...PallasPoint.random().toBytes(),
//         ]),
//       ),
//       amount: ZAmount.from(100000),
//     );

//     expect(
//       () async => await builder.addTransparentSpend(
//         TransparentSigningInput(
//           input: TransparentUtxoWithOwner(
//             utxo: TransparentUtxo(
//               txHash: ZcashTxId(List<int>.filled(32, 1)),
//               value: BigInt.from(2000000),
//               vout: 1,
//               blockHeight: 0,
//             ),
//             ownerDetails: TransparentUtxoOwner(
//               publicKey: account.toPublicKey(),
//               address: account.toPublicKey().toAddress(),
//             ),
//           ),
//         ),
//       ),
//       throwsA(isA<BuError>()),
//     );
//     await builder.signTransparent(index: 0, sk: account);
//     await builder.addTransparentSpend(
//       TransparentSigningInput(
//         input: TransparentUtxoWithOwner(
//           utxo: TransparentUtxo(
//             txHash: ZcashTxId(List<int>.filled(32, 1)),
//             value: BigInt.from(200),
//             vout: 3,
//             blockHeight: 0,
//           ),
//           ownerDetails: TransparentUtxoOwner(
//             publicKey: account.toPublicKey(),
//             address: account.toPublicKey().toAddress(),
//           ),
//         ),
//       ),
//     );
//     await builder.signTransparent(index: 1, sk: account);
//     expect(
//       () async => await builder.addTransparentSpend(
//         TransparentSigningInput(
//           input: TransparentUtxoWithOwner(
//             utxo: TransparentUtxo(
//               txHash: ZcashTxId(List<int>.filled(32, 1)),
//               value: BigInt.from(2000000),
//               vout: 2,
//               blockHeight: 0,
//             ),
//             ownerDetails: TransparentUtxoOwner(
//               publicKey: account.toPublicKey(),
//               address: account.toPublicKey().toAddress(),
//             ),
//           ),
//         ),
//       ),
//       throwsA(isA<BuError>()),
//     );
//     ZAmount value = builder.valueBalance();
//     expect(
//       value,
//       ZAmount(BigInt.from(1000000) - BigInt.from(100000) + BigInt.from(200)),
//     );
//   });

//   test("Transparent builder", () async {
//     final context = DefaultZcashCryptoContext.lazy();
//     final account = ZECPrivate.fromHex(
//       "8be14936d4857d2f57902dccf8d6e388bfb85a37d9d6e5b69d4efa80ed4af6b5",
//     );
//     final builder = TransactionBuilder(
//       network: ZcashNetwork.mainnet,
//       targetHeight: 10000000,
//       config: TransactionBuildConfigStandard(),
//       context: context,
//     );
//     await builder.addTransparentSpend(
//       TransparentSigningInput(
//         input: TransparentUtxoWithOwner(
//           utxo: TransparentUtxo(
//             txHash: ZcashTxId(List<int>.filled(32, 1)),
//             value: BigInt.from(1000000),
//             vout: 1,
//             blockHeight: 0,
//           ),
//           ownerDetails: TransparentUtxoOwner(
//             publicKey: account.toPublicKey(),
//             address: account.toPublicKey().toAddress(),
//           ),
//         ),
//       ),
//     );
//     await builder.addOutput(
//       target: TransactionOutputTarget.orchard(
//         orchardAddress: OrchardAddress.fromBytes([
//           ...DiversifierIndex.zero().toBytes(),
//           ...PallasPoint.random().toBytes(),
//         ]),
//       ),
//       amount: ZAmount.from(100000),
//     );
//     final fee = await builder.addChange(
//       target: TransactionOutputTarget.orchard(
//         orchardAddress: OrchardAddress.fromBytes([
//           ...DiversifierIndex.zero().toBytes(),
//           ...PallasPoint.random().toBytes(),
//         ]),
//       ),
//     );
//     ZAmount value = builder.valueBalance();
//     final outputs = BigInt.from(1000000) - fee.value;
//     expect(value - fee, ZAmount.zero());
//     await builder.signTransparent(index: 0, sk: account);
//     expect(
//       () async => await builder.extractTransaction(),
//       throwsA(isA<BuError>()),
//     );
//     await builder.setOrchardProof(OrchardProof(List<int>.filled(100, 0)));
//     final tx = await builder.extractTransaction(verifyProofs: false);
//     expect(tx.transactionData.transparentBundle?.vin.length, 1);
//     expect(tx.transactionData.transparentBundle?.vout.length, 0);
//     expect(tx.transactionData.orchardBundle?.actions.length, 2);
//     expect(tx.transactionData.orchardBundle?.balance, ZAmount(-outputs));
//   });
// }

// void main() {
//   ZcashTestApi.runTest(builderTransparentTest, "Builder Transparent");
// }
