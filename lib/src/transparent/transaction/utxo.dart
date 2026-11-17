import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';
import 'package:zcash_dart/src/transaction/sighash_digest/types.dart';
import 'package:zcash_dart/src/transparent/keys/public_key.dart';
import 'package:zcash_dart/src/transparent/keys/multisig.dart';
import 'package:zcash_dart/src/transparent/transaction/input.dart';
import 'package:zcash_dart/src/value/value.dart';

/// TransparentUtxo represents an unspent transaction output (UTXO) on the zcash blockchain.
/// It includes details such as the transaction hash (TxHash), the amount of transparent (Value),
/// the output index (Vout), the script type (ScriptType), and the block height at which the UTXO
/// was confirmed (BlockHeight).
class TransparentUtxo with PartialEquality, LayoutSerializable {
  /// TxHash is the unique identifier of the transaction containing this UTXO.
  final ZcashTxId txId;

  final ZAmount amount;

  /// Vout is the output index within the transaction that corresponds to this UTXO.
  final int vout;

  /// BlockHeight represents the block height at which this UTXO was confirmed.
  final int blockHeight;

  TransparentUtxo._({
    required this.txId,
    required this.amount,
    required this.vout,
    required this.blockHeight,
  });

  factory TransparentUtxo({
    required ZcashTxId txHash,
    required BigInt value,
    required int vout,
    required int blockHeight,
  }) {
    return TransparentUtxo._(
      txId: txHash,
      amount: ZAmount(value),
      blockHeight: blockHeight,
      vout: vout,
    );
  }

  factory TransparentUtxo.dummy({BigInt? amount}) {
    return TransparentUtxo(
      txHash: ZcashTxId(
        QuickCrypto.generateRandom(length: QuickCrypto.blake2b256DigestSize),
      ),
      value: amount ?? BigInt.zero,
      vout: QuickCrypto.generateRandomInt(BinaryOps.mask8),
      blockHeight: 0,
    );
  }
  factory TransparentUtxo.deserialize(List<int> bytes) {
    return TransparentUtxo.deserializeJson(
      LayoutSerializable.deserialize(bytes: bytes, layout: layout()),
    );
  }
  factory TransparentUtxo.deserializeJson(Map<String, dynamic> json) {
    return TransparentUtxo(
      txHash: ZcashTxId(json.valueAsBytes("tx_hash")),
      value: json.valueAsBigInt("amount"),
      vout: json.valueAs("vout"),
      blockHeight: json.valueAs("block_height"),
    );
  }

  TransparentTxInput toInput({int? sequence, Script? scriptSig}) {
    return TransparentTxInput(
      txId: txId,
      txIndex: vout,
      scriptSig: scriptSig,
      sequance: sequence,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "tx_hash": txId.hash,
      "value": amount.toString(),
      "vout": vout,
      "block_height": blockHeight,
    };
  }

  @override
  List<dynamic> get variables => [txId, vout, amount, blockHeight];

  @override
  List<dynamic> get parts => [txId, vout];

  String get identifier => "${txId.txId}_$vout";
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(
        QuickCrypto.blake2b256DigestSize,
        property: "tx_hash",
      ),
      LayoutConst.lebU32(property: "vout"),
      LayoutConst.lebU64(property: "amount"),
      LayoutConst.optional(LayoutConst.lebU32(), property: "block_height"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "tx_hash": txId.hash,
      "vout": vout,
      "amount": amount.value,
      "block_height": blockHeight,
    };
  }
}

class TransparentUtxoOwner {
  /// PublicKey is the public key associated with the UTXO owner.
  final ZECPublic? publicKey;

  final CryptoKeyEncoding keyType;

  /// Address is the Bitcoin address associated with the UTXO owner.
  final ZcashTransparentAddress address;

  /// MultiSigAddress is a pointer to a MultiSignaturAddress instance representing a multi-signature address
  /// associated with the UTXO owner. It may be null if the UTXO owner is not using a multi-signature scheme.
  final TransparentMultiSignatureAddress? _multiSigAddress;

  final Script? p2shRedeemScript;

  TransparentUtxoOwner._({
    required this.publicKey,
    required this.address,
    required this.keyType,
    required this.p2shRedeemScript,
  }) : _multiSigAddress = null;
  factory TransparentUtxoOwner({
    required ZECPublic publicKey,
    required ZcashTransparentAddress address,
    CryptoKeyEncoding mode = CryptoKeyEncoding.base,
  }) {
    return TransparentUtxoOwner._(
      publicKey: publicKey,
      address: address,
      p2shRedeemScript: null,
      keyType: mode,
    );
  }
  factory TransparentUtxoOwner.nonStandardP2sh({
    required Script redeemScript,
    required ZcashP2shAddress address,
  }) {
    if (P2shAddress.fromScript(script: redeemScript).toScriptPubKey() !=
        address.toScriptPubKey()) {
      throw ZcashErrors.transparentFailed(
        "nonStandardP2sh",
        reason: "Invalid redeem script.",
      );
    }

    return TransparentUtxoOwner._(
      publicKey: null,
      address: address,
      p2shRedeemScript: redeemScript,
      keyType: CryptoKeyEncoding.base,
    );
  }

  TransparentUtxoOwner.multiSigAddress({
    required TransparentMultiSignatureAddress multiSigAddress,
    required this.address,
  }) : publicKey = null,
       _multiSigAddress = multiSigAddress,
       keyType = CryptoKeyEncoding.base,
       p2shRedeemScript = null;

  TransparentUtxoOwner.watchOnly(this.address)
    : publicKey = null,
      _multiSigAddress = null,
      keyType = CryptoKeyEncoding.base,
      p2shRedeemScript = null;

  Script reedemScript() {
    final msig = _multiSigAddress;
    if (msig != null) {
      return msig.multiSigScript;
    }
    if (address.type == P2pkhAddressType.p2pkh) {
      return address.toScriptPubKey();
    }
    final redeemScript = p2shRedeemScript;
    if (redeemScript != null) return redeemScript;

    final pk = publicKey;
    if (pk == null) {
      throw ZcashErrors.transparentFailed(
        "reedemScript",
        reason: "Cannot access public key in watch only address.",
      );
    }
    switch (address.type) {
      case P2shAddressType.p2pkInP2sh:
        return pk.toP2pkRedeemScript(mode: keyType);
      case P2shAddressType.p2pkhInP2sh:
        return pk.toAddress(mode: keyType).toScriptPubKey();
      default:
        throw ZcashErrors.transparentFailed(
          "reedemScript",
          reason: "Unsupported redeem script.",
        );
    }
  }

  ZcashAddress toAddress() {
    switch (address.type) {
      case P2pkhAddressType.p2pkh:
        return address;
      default:
        return ZcashP2shAddress.fromScript(
          script: reedemScript(),
          network: address.network,
        );
    }
  }

  Script scriptPubKey() => address.toScriptPubKey();
}

/// TransparentUtxoWithOwner represents an unspent transaction output (UTXO) along with its associated owner details.
/// It combines information about the UTXO itself (BitcoinUtxo) and the ownership details (TransparentUtxoOwner).
class TransparentUtxoWithOwner {
  /// Utxo is a BitcoinUtxo instance representing the unspent transaction output.
  final TransparentUtxo utxo;

  /// OwnerDetails is a TransparentUtxoOwner instance containing information about the UTXO owner.
  final TransparentUtxoOwner ownerDetails;

  const TransparentUtxoWithOwner._({
    required this.utxo,
    required this.ownerDetails,
  });
  factory TransparentUtxoWithOwner({
    required TransparentUtxo utxo,
    required TransparentUtxoOwner ownerDetails,
  }) {
    return TransparentUtxoWithOwner._(utxo: utxo, ownerDetails: ownerDetails);
  }

  ZECPublic getPublicKey() {
    if (isMultiSig()) {
      throw ZcashErrors.transparentFailed(
        "getPublicKey",
        reason: "Cannot access public key in multi-signature address.",
      );
    }
    final publicKey = ownerDetails.publicKey;
    if (publicKey == null) {
      throw ZcashErrors.transparentFailed(
        "getPublicKey",
        reason: "Cannot access public key in watch only address.",
      );
    }
    return publicKey;
  }

  bool isMultiSig() {
    return ownerDetails._multiSigAddress != null;
  }

  TransparentMultiSignatureAddress get multiSigAddress =>
      isMultiSig()
          ? ownerDetails._multiSigAddress!
          : throw ZcashErrors.transparentFailed(
            "getPublicKey",
            reason:
                "The address is not associated with a multi-signature setup.",
          );
}
