import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/exception/exception.dart';
import 'package:zcash_dart/src/block_processor/src/exception.dart';
import 'package:zcash_dart/src/crypto/src/exception.dart';
import 'package:zcash_dart/src/exception/exception.dart';
import 'package:zcash_dart/src/merkle/exception/exception.dart';
import 'package:zcash_dart/src/note/src/exception.dart';
import 'package:zcash_dart/src/orchard/builder/exception.dart';
import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/orchard/pczt/exception.dart';
import 'package:zcash_dart/src/pczt/exception/exception.dart';
import 'package:zcash_dart/src/provider/walletd/exception/exception.dart';
import 'package:zcash_dart/src/sapling/builder/exception.dart';
import 'package:zcash_dart/src/sapling/exception/exception.dart';
import 'package:zcash_dart/src/sapling/pczt/exception.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/transaction/builders/exception.dart';
import 'package:zcash_dart/src/transaction/exception/exception.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/lib/exception/exception.dart';

abstract class BaseDartZcashPluginException extends IException {
  const BaseDartZcashPluginException(super.message, {super.details});
  factory BaseDartZcashPluginException.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final decode = CborTagSerializable.decodeTaggedValueWithInfo(
      expectedTags: ZcashSerializationIdentifier.values,
      cborBytes: bytes,
      cborObject: obj,
    );
    final identifier = decode.identifier;
    return switch (identifier) {
      ZcashSerializationIdentifier.zcashPluginError =>
        DartZcashPluginException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.zcashAddressError =>
        ZcashAddressException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.blockScannerError =>
        ZcashBlockScannerException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.cryptoError =>
        ZcashCryptoContextException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.merkleError =>
        MerkleTreeException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.noteError =>
        NoteEncryptionException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.orchardError => OrchardException.deserialize(
        obj: decode.tag,
      ),
      ZcashSerializationIdentifier.pcztError => PcztException.deserialize(
        obj: decode.tag,
      ),
      ZcashSerializationIdentifier.walletdError => WalletdException.deserialize(
        obj: decode.tag,
      ),
      ZcashSerializationIdentifier.saplingError => SaplingException.deserialize(
        obj: decode.tag,
      ),
      ZcashSerializationIdentifier.transactionError =>
        TransactionBuilderException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.transactionSerializationError =>
        ZTransactionSerializationError.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.transparentError =>
        TransparentExceptoion.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.zklibError => ZKLibException.deserialize(
        obj: decode.tag,
      ),
      ZcashSerializationIdentifier.orchardBuilderError =>
        OrchardBuilderException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.orchardPcztError =>
        OrchardPcztException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.saplingBuilderError =>
        SaplingBuilderException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.saplingPcztError =>
        SaplingPcztException.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.merkleMergeError =>
        MerkleMergeError.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.merkleFrontierError =>
        MerkleFrontierError.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.merkleWitnessError =>
        MerkleWitnessError.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.merkleInsertionError =>
        MerkleInsertionError.deserialize(obj: decode.tag),
      ZcashSerializationIdentifier.merkleBuilderError =>
        MerkleBuilderException.deserialize(obj: decode.tag),
      _ =>
        throw CborSerializableException.incorrectTagValue(tag: decode.tag.tags),
    };
  }
  @override
  ZcashSerializationIdentifier get serializationIdentifier;

  @override
  BlockchainNetwork get relatedNetwork => BlockchainNetwork.zcash;
}
