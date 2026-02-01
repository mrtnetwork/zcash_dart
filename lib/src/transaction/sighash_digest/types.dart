import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

/// Types of inputs that can be signed in a transaction.
enum SignableInputType {
  shielded,
  transparent;

  /// Returns true if the input type is transparent.
  bool get isTransparent => this == transparent;
}

/// Base class representing an input that can be signed.
sealed class SignableInput {
  final SignableInputType type;

  /// input hash type
  final int hashType;
  const SignableInput({required this.type, required this.hashType});

  T cast<T extends SignableInput>() {
    final c = this;
    if (c is! T) throw CastFailedException<T>(value: this);
    return c;
  }
}

/// Represents a shielded input that can be signed.
class ShieldedSignableInput extends SignableInput {
  const ShieldedSignableInput()
      : super(
            type: SignableInputType.shielded,
            hashType: BitcoinOpCodeConst.sighashAll);
}

/// Represents a transparent input that can be signed, including index, scripts, and amount.
class TransparentSignableInput extends SignableInput {
  /// input index
  final int index;

  /// input P2SH redeem script or P2pkh scriptPubKey
  final Script scriptCode;

  /// input scriptPubKey
  final Script sciptPubKey;

  /// input amount
  final BigInt amount;
  const TransparentSignableInput(
      {required super.hashType,
      required this.index,
      required this.scriptCode,
      required this.sciptPubKey,
      required this.amount})
      : super(type: SignableInputType.transparent);
}

/// Represents the digests of the transparent transaction components for TXID computation.
class TransparentDigest {
  /// Digest of all previous outputs referenced by the transaction inputs.
  final List<int> prevoutsDigest;

  /// Digest of the sequence numbers of all inputs.
  final List<int> sequenceDigest;

  /// Digest of all transaction outputs.
  final List<int> outputsDigest;
  TransparentDigest({
    required List<int> prevoutsDigest,
    required List<int> sequenceDigest,
    required List<int> outputsDigest,
  })  : prevoutsDigest = prevoutsDigest
            .exc(
                length: QuickCrypto.blake2b256DigestSize,
                operation: "TransparentDigest",
                reason: "Invalid prevoutsDigest bytes length.")
            .asImmutableBytes,
        sequenceDigest = sequenceDigest
            .exc(
                length: QuickCrypto.blake2b256DigestSize,
                operation: "TransparentDigest",
                reason: "Invalid sequenceDigest bytes length.")
            .asImmutableBytes,
        outputsDigest = outputsDigest
            .exc(
                length: QuickCrypto.blake2b256DigestSize,
                operation: "TransparentDigest",
                reason: "Invalid outputsDigest bytes length.")
            .asImmutableBytes;
}

/// Represents the digests of all parts of a Zcash transaction (header, transparent, sapling, orchard).
class TxDigestsPart {
  /// Digest of the transaction header (32 bytes).
  final List<int> headerDigest;

  /// Digest of the transparent bundle, or null if absent.
  final TransparentDigest? transparentDigest;

  /// Digest of the Sapling bundle (32 bytes), or null if absent.
  final List<int>? saplingDigest;

  /// Digest of the Orchard bundle (32 bytes), or null if absent.
  final List<int>? orchardDigest;
  TxDigestsPart(
      {required List<int> headerDigest,
      this.transparentDigest,
      List<int>? saplingDigest,
      List<int>? orchardDigest})
      : headerDigest = headerDigest
            .exc(
                length: QuickCrypto.blake2b256DigestSize,
                operation: "TxDigestsPart",
                reason: "Invalid headerDigest bytes length.")
            .asImmutableBytes,
        saplingDigest = saplingDigest
            ?.exc(
                length: QuickCrypto.blake2b256DigestSize,
                operation: "TxDigestsPart",
                reason: "Invalid saplingDigest bytes length.")
            .asImmutableBytes,
        orchardDigest = orchardDigest
            ?.exc(
                length: QuickCrypto.blake2b256DigestSize,
                operation: "TxDigestsPart",
                reason: "Invalid orchardDigest bytes length.")
            .asImmutableBytes;
}

/// Represents a Zcash transaction ID (32-byte hash).
class ZCashTxId with Equality, LayoutSerializable {
  final List<int> txId;
  ZCashTxId(List<int> txId)
      : txId = txId
            .exc(
              length: QuickCrypto.blake2b256DigestSize,
              operation: "ZCashTxId",
              reason: "Invalid txId bytes length.",
            )
            .asImmutableBytes;
  factory ZCashTxId.deserializeJson(Map<String, dynamic> json) =>
      ZCashTxId(json.valueAsBytes("txid"));

  /// Returns the transaction ID as a hex string.
  String toHex() => BytesUtils.toHexString(txId);

  /// Returns the transaction ID as a reversed hex string (for display as txid).
  String toTxId() => BytesUtils.toHexString(txId.reversed.toList());

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([LayoutConst.fixedBlob32(property: "txid")],
        property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"txid": txId};
  }

  @override
  List<dynamic> get variables => [txId];
}
