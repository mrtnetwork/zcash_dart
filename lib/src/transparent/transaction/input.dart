import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/layout/layout.dart';
import 'package:blockchain_utils/utils/utils.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';

/// Represents a transparent transaction input.
class TransparentTxInput with LayoutSerializable {
  /// the transaction id.
  final List<int> txId;

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
  })  : sequence = sequance ?? BinaryOps.maxUint32,
        scriptSig = scriptSig ?? Script(script: []);
  factory TransparentTxInput.deserializeJson(Map<String, dynamic> json) {
    return TransparentTxInput(
        txId: json.valueAsBytes("tx_id"),
        txIndex: json.valueAs("index"),
        scriptSig: Script.deserialize(bytes: json.valueAsBytes("script")),
        sequance: json.valueAs<int>("sequence"));
  }
  factory TransparentTxInput({
    required List<int> txId,
    required int txIndex,
    Script? scriptSig,
    int? sequance,
  }) {
    if (sequance != null &&
        (sequance.isNegative || sequance > BinaryOps.maxUint32)) {
      throw TransparentExceptoion.operationFailed("TransparentTxInput",
          reason: "Invalid transaction sequance.");
    }
    return TransparentTxInput._(
        txId: txId,
        txIndex: txIndex,
        sequance: sequance,
        scriptSig: scriptSig,
        coinbase: txId.every((e) => e == 0));
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
      "tx_id": txId,
      "index": txIndex,
      "script": scriptSig.toBytes(),
      "sequence": sequence
    };
  }
}
