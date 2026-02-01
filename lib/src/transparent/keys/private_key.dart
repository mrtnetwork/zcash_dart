import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/transparent/keys/public_key.dart';

/// Represents an ECDSA private key.
class ZECPrivate {
  final Bip32PrivateKey inner;
  const ZECPrivate._(this.inner);

  /// creates an object from hex
  factory ZECPrivate.fromHex(String keyHex) {
    return ZECPrivate.fromBytes(BytesUtils.fromHexString(keyHex));
  }

  /// creates an object from bip32
  factory ZECPrivate.fromBip32(Bip32PrivateKey bip32) => ZECPrivate._(bip32);

  /// creates an object from raw 32 bytes
  factory ZECPrivate.fromBytes(List<int> keyBytes) {
    final key = Bip32PrivateKey.fromBytes(keyBytes, Bip32KeyData(),
        Bip32Const.mainNetKeyNetVersions, EllipticCurveTypes.secp256k1);
    return ZECPrivate._(key);
  }

  /// returns the corresponding ZECPublic object
  ZECPublic toPublicKey() => ZECPublic.fromBip32(inner.publicKey);

  /// returns the key's raw bytes
  List<int> toBytes() {
    return inner.raw;
  }

  /// returns the key's as hex
  String toHex() {
    return BytesUtils.toHexString(inner.raw);
  }

  /// Signs a message using BIP-137 format for standardized Bitcoin message signing.
  ///
  /// This method produces a compact ECDSA signature with a modified recovery ID
  /// based on the specified BIP-137 signing mode.
  ///
  /// - [message]: The raw message to be signed.
  /// - [messagePrefix]: The prefix used for Bitcoin's message signing
  ///   (default is `BitcoinSignerUtils.signMessagePrefix`).
  /// - [mode]: The BIP-137 mode specifying the key type (e.g., P2PKH uncompressed, compressed, SegWit, etc.).
  /// - [extraEntropy]: Optional extra entropy to modify the signature (default is an empty list).
  ///
  /// The recovery ID (first byte of the signature) is adjusted based on the
  /// BIP-137 mode's header value. The final signature is encoded in Base64.
  String signBip137(
    List<int> message, {
    String messagePrefix = BitcoinSignerUtils.signMessagePrefix,
    BIP137Mode mode = BIP137Mode.p2pkhUncompressed,
    List<int> extraEntropy = const [],
  }) {
    final btcSigner = BitcoinKeySigner.fromKeyBytes(toBytes());
    final signature = btcSigner.signMessageConst(
        message: message,
        messagePrefix: messagePrefix,
        extraEntropy: extraEntropy);
    int rId = signature[0] + mode.header;
    return StringUtils.decode([rId, ...signature.sublist(1)],
        type: StringEncoding.base64);
  }

  /// Signs a message using Bitcoin's message signing format.
  ///
  /// This method produces a compact ECDSA signature for a given message, following
  /// the Bitcoin Signed Message standard.
  ///
  /// - [message]: The raw message to be signed.
  /// - [messagePrefix]: The prefix used for Bitcoin's message signing.
  /// - [extraEntropy]: Optional extra entropy to modify the signature.
  String signMessage(List<int> message,
      {String messagePrefix = BitcoinSignerUtils.signMessagePrefix,
      List<int> extraEntropy = const []}) {
    final btcSigner = BitcoinKeySigner.fromKeyBytes(toBytes());
    final signature = btcSigner.signMessageConst(
        message: message,
        messagePrefix: messagePrefix,
        extraEntropy: extraEntropy);
    return BytesUtils.toHexString(signature.sublist(1));
  }

  /// Signs the given transaction digest using ECDSA (DER-encoded).
  ///
  /// - [txDigest]: The transaction digest (message) to sign.
  /// - [sighash]: The sighash flag to append (default is SIGHASH_ALL).
  List<int> signECDSA(List<int> txDigest,
      {int? sighash = BitcoinOpCodeConst.sighashAll,
      List<int> extraEntropy = const []}) {
    final btcSigner = BitcoinKeySigner.fromKeyBytes(toBytes());
    List<int> signature =
        btcSigner.signECDSADerConst(txDigest, extraEntropy: extraEntropy);
    if (sighash != null) {
      signature = <int>[...signature, sighash];
    }
    return signature;
  }

  factory ZECPrivate.random() {
    final secret = QuickCrypto.generateRandom();
    return ZECPrivate.fromBytes(secret);
  }
}
