import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

void main() {
  test('Exception serialization', () {
    {
      final error = DartZcashPluginException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = ZcashAddressException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = ZcashBlockScannerException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = ZcashCryptoContextException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = MerkleTreeException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = MerkleMergeError.conflict(
        name: "error",
        address: NodeAddress(level: TreeLevel(1), index: 32),
      );
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = MerkleWitnessError.failed(
        name: "error",
        addresses: [NodeAddress(level: TreeLevel(1), index: 32)],
        reason: 'reason',
      );
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = NoteEncryptionException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = OrchardException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = PcztException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = WalletdException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = SaplingException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = TransactionBuilderException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = ZTransactionSerializationError("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = TransparentExceptoion("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }

    {
      final error = ZKLibException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = OrchardPcztException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = SaplingBuilderException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
    {
      final error = SaplingPcztException("error");
      final decode = BaseDartZcashPluginException.deserialize(
        bytes: error.toCbor().encode(),
      );
      expect(decode, error);
    }
  });
}
