import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:blockchain_utils/encoding/encoding.dart';
import 'package:blockchain_utils/utils/utils.dart';
import 'package:zcash_dart/src/transaction/sighash_digest/types.dart';

/// Represents a transparent transaction input.
class TransparentTxInput with LayoutSerializable {
  /// the transaction id.
  final ZcashTxId txId;

  /// the index of the UTXO that we want to spend
  final int txIndex;
  final bool coinbase;

  /// the script that satisfies the locking conditions
  final Script scriptSig;

  /// the input sequence (for timelocks, RBF, etc.)
  final int sequence;

  TransparentTxInput._({
    required this.txId,
    required this.txIndex,
    required this.coinbase,
    Script? scriptSig,
    int? sequance,
  }) : sequence = sequance ?? BinaryOps.maxUint32,
       scriptSig = scriptSig ?? Script(script: []);
  factory TransparentTxInput.deserializeJson(Map<String, dynamic> json) {
    return TransparentTxInput(
      txId: ZcashTxId(json.valueAsBytes("tx_id")),
      txIndex: json.valueAs("index"),
      scriptSig: Script.deserialize(bytes: json.valueAsBytes("script")),
      sequance: json.valueAs<int>("sequence"),
    );
  }
  factory TransparentTxInput({
    required ZcashTxId txId,
    required int txIndex,
    Script? scriptSig,
    int? sequance,
  }) {
    if (sequance != null &&
        (sequance.isNegative || sequance > BinaryOps.maxUint32)) {
      throw ZcashErrors.transparentFailed(
        "TransparentTxInput",
        reason: "Invalid transaction sequance.",
      );
    }
    return TransparentTxInput._(
      txId: txId,
      txIndex: txIndex,
      sequance: sequance,
      scriptSig: scriptSig,
      coinbase: txId.hash.every((e) => e == 0),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "tx_id"),
      LayoutConst.u32(property: "index"),
      LayoutConst.varintVector(LayoutConst.u8(), property: "script"),
      LayoutConst.u32(property: "sequence"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "tx_id": txId.hash,
      "index": txIndex,
      "script": scriptSig.toBytes(),
      "sequence": sequence,
    };
  }
}
