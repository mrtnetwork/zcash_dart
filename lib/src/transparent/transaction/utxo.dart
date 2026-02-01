import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';
import 'package:zcash_dart/src/transparent/keys/public_key.dart';
import 'package:zcash_dart/src/transparent/keys/multisig.dart';
import 'package:zcash_dart/src/transparent/transaction/input.dart';

/// TransparentUtxo represents an unspent transaction output (UTXO) on the zcash blockchain.
/// It includes details such as the transaction hash (TxHash), the amount of transparent (Value),
/// the output index (Vout), the script type (ScriptType), and the block height at which the UTXO
/// was confirmed (BlockHeight).
class TransparentUtxo with PartialEquality {
  /// TxHash is the unique identifier of the transaction containing this UTXO.
  final List<int> txHash;

  /// Value is a pointer to a BigInt representing the amount of transparent associated with this UTXO.
  final BigInt value;

  /// Vout is the output index within the transaction that corresponds to this UTXO.
  final int vout;

  /// BlockHeight represents the block height at which this UTXO was confirmed.
  final int? blockHeight;

  final bool coinbase;

  TransparentUtxo._({
    required List<int> txHash,
    required this.value,
    required this.vout,
    this.blockHeight,
    required this.coinbase,
  }) : txHash = txHash.exc(
         length: 32,
         operation: "TransparentUtxo",
         reason: "Invalid transaction hash bytes length.",
       );

  factory TransparentUtxo({
    required List<int> txHash,
    required BigInt value,
    required int vout,
    int? blockHeight,
  }) {
    return TransparentUtxo._(
      txHash: txHash,
      value: value,
      blockHeight: blockHeight,
      vout: vout,
      coinbase: txHash.every((e) => e == 0),
    );
  }

  TransparentTxInput toInput({int? sequence, Script? scriptSig}) {
    return TransparentTxInput(
      txId: txHash,
      txIndex: vout,
      scriptSig: scriptSig,
      sequance: sequence,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "tx_hash": txHash,
      "value": value.toString(),
      "vout": vout,
      "block_height": blockHeight,
    };
  }

  @override
  List<dynamic> get variables => [txHash, vout, value, blockHeight];

  @override
  List<dynamic> get parts => [txHash, vout];
}

class TransparentUtxoOwner {
  /// PublicKey is the public key associated with the UTXO owner.
  final ZECPublic? publicKey;

  final PubKeyModes keyType;

  /// Address is the Bitcoin address associated with the UTXO owner.
  final ZCashTransparentAddress address;

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
    required ZCashTransparentAddress address,
    PubKeyModes mode = PubKeyModes.compressed,
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
    required ZCashP2shAddress address,
  }) {
    if (P2shAddress.fromScript(script: redeemScript).toScriptPubKey() !=
        address.toScriptPubKey()) {
      throw TransparentExceptoion.operationFailed(
        "nonStandardP2sh",
        reason: "Invalid redeem script.",
      );
    }

    return TransparentUtxoOwner._(
      publicKey: null,
      address: address,
      p2shRedeemScript: redeemScript,
      keyType: PubKeyModes.compressed,
    );
  }

  TransparentUtxoOwner.multiSigAddress({
    required TransparentMultiSignatureAddress multiSigAddress,
    required this.address,
  }) : publicKey = null,
       _multiSigAddress = multiSigAddress,
       keyType = PubKeyModes.compressed,
       p2shRedeemScript = null;

  TransparentUtxoOwner.watchOnly(this.address)
    : publicKey = null,
      _multiSigAddress = null,
      keyType = PubKeyModes.compressed,
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
      throw TransparentExceptoion.operationFailed(
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
        throw TransparentExceptoion.operationFailed(
          "reedemScript",
          reason: "Unsupported redeem script.",
        );
    }
  }

  ZCashAddress toAddress() {
    switch (address.type) {
      case P2pkhAddressType.p2pkh:
        return address;
      default:
        return ZCashP2shAddress.fromScript(
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
      throw TransparentExceptoion.operationFailed(
        "getPublicKey",
        reason: "Cannot access public key in multi-signature address.",
      );
    }
    final publicKey = ownerDetails.publicKey;
    if (publicKey == null) {
      throw TransparentExceptoion.operationFailed(
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
          : throw TransparentExceptoion.operationFailed(
            "getPublicKey",
            reason:
                "The address is not associated with a multi-signature setup.",
          );
}
