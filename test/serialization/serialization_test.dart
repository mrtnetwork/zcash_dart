import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

import '../utils.dart';

void _expectRoundTrip(BuError error) {
  final decode = BuErrorCodec.decode(bytes: error.toCborBytes());
  expect(decode.type, error.type);
  expect(decode.message, error.message);
  expect(decode.details, error.details);
}

void serializationSerializationTest() {
  test('Exception serialization', () {
    BuErrorCodec.registerTypes(ZcashErrorType.values);
    _expectRoundTrip(const BuError(ZcashErrorType.plugin, "error"));
    _expectRoundTrip(
      const BuError(ZcashErrorType.invalidUnifiedReceivers, "error"),
    );
    _expectRoundTrip(
      ZcashErrors.mismatchNetwork(
        network: ZcashNetwork.mainnet,
        expected: ZcashNetwork.testnet,
      ),
    );
    _expectRoundTrip(ZcashErrors.scannerFailed("sync", reason: "timeout"));
    _expectRoundTrip(
      ZcashErrors.scannerInvalidCompact("block", reason: "bad data"),
    );
    _expectRoundTrip(const BuError(ZcashErrorType.cryptoContext, "error"));
    _expectRoundTrip(ZcashErrors.merkleFailed("error", reason: "reason"));
    _expectRoundTrip(
      ZcashErrors.merkleMergeConflict(
        name: "error",
        address: NodeAddress(level: TreeLevel(1), index: 32),
      ),
    );
    _expectRoundTrip(
      ZcashErrors.merkleWitnessFailed(
        name: "error",
        addresses: [NodeAddress(level: TreeLevel(1), index: 32)],
        reason: 'reason',
      ),
    );
    _expectRoundTrip(ZcashErrors.noteFailed("encrypt", reason: "reason"));
    _expectRoundTrip(ZcashErrors.orchardFailed("prove", reason: "reason"));
    _expectRoundTrip(ZcashErrors.pcztFailed("merge", reason: "reason"));
    _expectRoundTrip(ZcashErrors.walletdFailed("sync", reason: "reason"));
    _expectRoundTrip(ZcashErrors.saplingFailed("prove", reason: "reason"));
    _expectRoundTrip(ZcashErrors.txBuilderFailed("build", reason: "reason"));
    _expectRoundTrip(ZcashErrors.txSerializationFailed("proof"));
    _expectRoundTrip(ZcashErrors.txSerializationUnexpected);
    _expectRoundTrip(
      ZcashErrors.transparentFailed("transfer", reason: "reason"),
    );
    _expectRoundTrip(ZcashErrors.transparentMultisigFailed("setup"));
    _expectRoundTrip(ZcashErrors.merkleInsertionFailed(name: "t", reason: "r"));
    _expectRoundTrip(ZcashErrors.merkleFrontierFailed(name: "t", reason: "r"));
    _expectRoundTrip(ZcashErrors.orchardBuilderFailed("build", reason: "r"));
    _expectRoundTrip(ZcashErrors.saplingBuilderFailed("build", reason: "r"));
    {
      final ids = ZcashErrorType.values.map((e) => e.id);
      expect(ids.toSet().length, ZcashErrorType.values.length);
      for (final id in ids) {
        expect(id > 258, equals(true));
      }
    }
  });
}

void serializationTest() {
  ZcashTestApi.runTest(serializationSerializationTest, "Serialization");
}

void main() {
  ZcashTestApi.runTest(serializationTest, "Serialization");
}
