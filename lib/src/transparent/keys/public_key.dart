import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/address.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';

class ZECPublic with Equality {
  final Secp256k1PublicKey publicKey;
  const ZECPublic._(this.publicKey);

  factory ZECPublic.fromBip32(Bip32PublicKey publicKey) {
    if (publicKey.curveType != EllipticCurveTypes.secp256k1) {
      throw TransparentExceptoion.operationFailed("fromBip32",
          reason: 'invalid public key curve for bitcoin');
    }
    return ZECPublic._(publicKey.pubKey as Secp256k1PublicKey);
  }

  /// Constructs an ZECPublic key from a byte representation.
  factory ZECPublic.fromBytes(List<int> keyBytes) {
    final publicKey = Secp256k1PublicKey.fromBytes(keyBytes);
    return ZECPublic._(publicKey);
  }

  /// Constructs an ZECPublic key from hex representation.
  factory ZECPublic.fromHex(String keyHex) {
    return ZECPublic.fromBytes(BytesUtils.fromHexString(keyHex));
  }

  /// toHex converts the ZECPublic key to a hex-encoded string.
  /// If 'compressed' is true, the key is in compressed format.
  String toHex({PublicKeyType mode = PublicKeyType.compressed}) {
    return BytesUtils.toHexString(toBytes(mode: mode));
  }

  /// toHash160 computes the RIPEMD160 hash of the ZECPublic key.
  /// If 'compressed' is true, the key is in compressed format.
  List<int> toHash160({PublicKeyType mode = PublicKeyType.compressed}) {
    final bytes = BytesUtils.fromHexString(toHex(mode: mode));
    return QuickCrypto.hash160(bytes);
  }

  /// toAddress generates a P2PKH (Pay-to-Public-Key-Hash) address from the ZECPublic key.
  /// If 'compressed' is true, the key is in compressed format.
  ZCashP2pkhAddress toAddress(
      {PublicKeyType mode = PublicKeyType.compressed,
      ZCashNetwork network = ZCashNetwork.mainnet}) {
    final h160 = toHash160(mode: mode);
    return ZCashP2pkhAddress.fromBytes(bytes: h160, network: network);
  }

  /// toRedeemScript generates a redeem script from the ZECPublic key.
  /// If 'compressed' is true, the key is in compressed format.
  Script toP2pkRedeemScript({PublicKeyType mode = PublicKeyType.compressed}) {
    return Script(script: [toHex(mode: mode), BitcoinOpcode.opCheckSig]);
  }

  /// toP2pkhInP2sh generates a P2SH (Pay-to-Script-Hash) address
  /// wrapping a P2PK (Pay-to-Public-Key) script derived from the ZECPublic key.
  /// If 'compressed' is true, the key is in compressed format.
  ZCashP2shAddress toP2pkhInP2sh(
      {PublicKeyType mode = PublicKeyType.compressed,
      ZCashNetwork network = ZCashNetwork.mainnet}) {
    final addr = toAddress(mode: mode);
    final script = addr.toScriptPubKey();
    final toBytes = script.toBytes();
    final h160 = QuickCrypto.hash160(toBytes);
    return ZCashP2shAddress.fromBytes(
        bytes: h160, type: P2shAddressType.p2pkhInP2sh, network: network);
  }

  /// toP2pkInP2sh generates a P2SH (Pay-to-Script-Hash) address
  /// wrapping a P2PK (Pay-to-Public-Key) script derived from the ZECPublic key.
  /// If 'compressed' is true, the key is in compressed format.
  ZCashP2shAddress toP2pkInP2sh(
      {PublicKeyType mode = PublicKeyType.compressed,
      ZCashNetwork network = ZCashNetwork.mainnet}) {
    final script = toP2pkRedeemScript(mode: mode);
    final toBytes = script.toBytes();
    final h160 = QuickCrypto.hash160(toBytes);
    return ZCashP2shAddress.fromBytes(
        bytes: h160, type: P2shAddressType.p2pkInP2sh, network: network);
  }

  List<int> toBytes({PubKeyModes mode = PubKeyModes.uncompressed}) {
    switch (mode) {
      case PubKeyModes.uncompressed:
        return publicKey.uncompressed;
      case PubKeyModes.compressed:
        return publicKey.compressed;
    }
  }

  /// Verifies a Bitcoin signed message using the provided signature.
  ///
  /// This method checks if the given signature is valid for the specified message,
  /// following Bitcoin's message signing format.
  ///
  /// - [message]: The original message that was signed.
  /// - [signature]: The compact ECDSA signature to verify.
  /// - [messagePrefix]: The prefix used in Bitcoin's message signing.
  bool verify(
      {required List<int> message,
      required List<int> signature,
      String messagePrefix = BitcoinSignerUtils.signMessagePrefix}) {
    final verifyKey = BitcoinSignatureVerifier.fromKeyBytes(toBytes());
    return verifyKey.verifyMessageSignature(
        message: message, messagePrefix: messagePrefix, signature: signature);
  }

  /// Recovers the BIP-137 public key from a signed message and signature.
  ///
  /// This method extracts the public key from a Bitcoin-signed message using the
  /// BIP-137 standard, which allows for signature-based public key recovery.
  ///
  /// - [message]: The original message that was signed.
  /// - [signature]: The Base64-encoded signature.
  /// - [messagePrefix]: The prefix used in Bitcoin's message signing.
  ZECPublic getBip137PublicKey(
      {required List<int> message,
      required String signature,
      String messagePrefix = BitcoinSignerUtils.signMessagePrefix}) {
    final signatureBytes =
        StringUtils.encode(signature, type: StringEncoding.base64);
    final ecdsaPubKey = BitcoinSignatureVerifier.recoverPublicKey(
        message: message,
        signature: signatureBytes,
        messagePrefix: messagePrefix);
    return ZECPublic.fromBytes(ecdsaPubKey.toBytes());
  }

  /// Recovers the BIP-137 address from a signed message and signature.
  ///
  /// This method extracts the public key from a Bitcoin-signed message using the
  /// BIP-137 standard, and then derives the appropriate Bitcoin address based on
  /// the signature's recovery mode (e.g., P2PKH, P2WPKH, P2SH-P2WPKH).
  ///
  /// - [message]: The original message that was signed.
  /// - [signature]: The Base64-encoded signature.
  /// - [messagePrefix]: The prefix used in Bitcoin's message signing
  ///   (default is `BitcoinSignerUtils.signMessagePrefix`).
  ///
  /// Returns the corresponding Bitcoin address derived from the recovered public key.
  /// The address type is determined by the recovery mode of the signature (e.g.,
  /// uncompressed, compressed, SegWit, or P2SH-wrapped SegWit).
  ZCashTransparentAddress? getBip137Address(
      {required List<int> message,
      required String signature,
      String messagePrefix = BitcoinSignerUtils.signMessagePrefix}) {
    final signatureBytes =
        StringUtils.encode(signature, type: StringEncoding.base64);
    final ecdsaPubKey = BitcoinSignatureVerifier.recoverPublicKey(
        message: message,
        signature: signatureBytes,
        messagePrefix: messagePrefix);
    final publicKey = ZECPublic.fromBytes(ecdsaPubKey.toBytes());
    final mode = BIP137Mode.findMode(signatureBytes[0]);
    return switch (mode) {
      BIP137Mode.p2pkhUncompressed =>
        publicKey.toAddress(mode: PubKeyModes.uncompressed),
      BIP137Mode.p2pkhCompressed => publicKey.toAddress(),
      _ => null
    };
  }

  /// Verifies that a BIP-137 signature matches the expected Bitcoin address.
  ///
  /// This method checks whether the address derived from the BIP-137 signature
  /// matches the provided address by comparing the corresponding scriptPubKey.
  ///
  /// - [message]: The original message that was signed.
  /// - [signature]: The Base64-encoded signature to verify.
  /// - [address]: The expected Bitcoin address to compare against.
  /// - [messagePrefix]: The prefix used in Bitcoin's message signing
  bool verifyBip137Address(
      {required List<int> message,
      required String signature,
      required ZCashTransparentAddress address,
      String messagePrefix = BitcoinSignerUtils.signMessagePrefix}) {
    final signerAddress = getBip137Address(
        message: message, signature: signature, messagePrefix: messagePrefix);
    return address.toScriptPubKey() == signerAddress?.toScriptPubKey();
  }

  /// Verifies an ECDSA DER-encoded signature against a given digest.
  ///
  /// This method checks whether the provided DER-encoded signature is valid for
  /// the given digest using the public key.
  ///
  /// - [digest]: The hash or message digest that was signed.
  /// - [signature]: The DER-encoded ECDSA signature to verify.
  ///
  /// Returns `true` if the signature is valid for the given digest, otherwise `false`.
  bool verifyDerSignature(
      {required List<int> digest, required List<int> signature}) {
    final verifyKey = BitcoinSignatureVerifier.fromKeyBytes(toBytes());
    return verifyKey.verifyECDSADerSignature(
        digest: digest, signature: signature);
  }

  @override
  List<dynamic> get variables => [publicKey];
}
