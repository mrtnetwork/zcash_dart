import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';
import 'package:zcash_dart/src/transparent/builder/builder.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';

/// Represents a transparent transaction output.
class TransparentTxOutput with Equality, LayoutSerializable {
  /// the amount of output
  final BigInt amount;

  /// script of output
  final Script scriptPubKey;
  const TransparentTxOutput._(
      {required this.amount, required this.scriptPubKey});
  factory TransparentTxOutput(
      {required BigInt amount, required Script scriptPubKey}) {
    try {
      return TransparentTxOutput._(
        amount: amount.asI64,
        scriptPubKey: scriptPubKey,
      );
    } catch (_) {
      throw TransparentExceptoion.operationFailed("TransparentTxOutput",
          reason: "Invalid output amount.");
    }
  }
  factory TransparentTxOutput.deserializeJson(Map<String, dynamic> json) {
    return TransparentTxOutput(
        amount: json.valueAsBigInt("amount"),
        scriptPubKey: Script.deserialize(bytes: json.valueAsBytes("script")));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.u64(property: "amount"),
      LayoutConst.varintVector(LayoutConst.u8(), property: "script"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"amount": amount, "script": scriptPubKey.toBytes()};
  }

  @override
  List<dynamic> get variables => [scriptPubKey, amount];
}

/// Abstract base class representing a generic Bitcoin output.
abstract class BaseTransparentOutputInfo {
  const BaseTransparentOutputInfo();

  /// Convert the output to a TransparentTxOutput, a generic representation of a transaction output.
  TransparentTxOutput toOutput();

  BigInt get value;
}

/// TransparentSpendableOutput represents details about a Bitcoin transaction output, including
/// the recipient address and the value of bitcoins sent to that address.
class TransparentSpendableOutput implements BaseTransparentOutputInfo {
  /// Address is a Bitcoin address representing the recipient of the transaction output.
  final ZCashTransparentAddress address;

  /// Value is a pointer to a BigInt representing the amount of bitcoins sent to the recipient.
  @override
  final BigInt value;
  // final CashToken? token;
  TransparentSpendableOutput({required this.address, required this.value});

  @override
  TransparentTxOutput toOutput() => TransparentTxOutput(
      amount: value, scriptPubKey: address.toScriptPubKey());
}

/// TransparentSpendableOutput represents details about a Bitcoin transaction output, including
/// the recipient address and the value of bitcoins sent to that address.
class TransparentNullDataOutput implements BaseTransparentOutputInfo {
  /// Address is a Bitcoin address representing the recipient of the transaction output.
  final Script opReturn;

  /// Value is a pointer to a BigInt representing the amount of bitcoins sent to the recipient.
  @override
  final BigInt value = BigInt.zero;
  // final CashToken? token;
  TransparentNullDataOutput._(this.opReturn);

  factory TransparentNullDataOutput(List<int> data) {
    if (data.length > TransparentBuilderConstant.maxOpReturn) {
      throw TransparentExceptoion.operationFailed("TransparentNullDataOutput",
          reason: "Data is to long.");
    }
    return TransparentNullDataOutput._(
        BitcoinScriptUtils.buildOpReturn([data]));
  }

  @override
  TransparentTxOutput toOutput() =>
      TransparentTxOutput(amount: value, scriptPubKey: opReturn);
}
