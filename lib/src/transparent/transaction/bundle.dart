import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/transaction/types/bundle.dart';
import 'package:zcash_dart/src/transparent/transaction/input.dart';
import 'package:zcash_dart/src/transparent/transaction/output.dart';

class TransparentBundle
    with LayoutSerializable
    implements Bundle<TransparentBundle> {
  factory TransparentBundle.empty() => TransparentBundle();
  final List<TransparentTxInput> vin;
  final List<TransparentTxOutput> vout;
  TransparentBundle({
    List<TransparentTxInput> vin = const [],
    List<TransparentTxOutput> vout = const [],
  })  : vin = vin.immutable,
        vout = vout.immutable;

  factory TransparentBundle.deserializeJson(Map<String, dynamic> json) {
    final vin = json.valueEnsureAsList<Map<String, dynamic>>("vin");
    final vout = json.valueEnsureAsList<Map<String, dynamic>>("vout");
    return TransparentBundle(
        vin: vin.map((e) => TransparentTxInput.deserializeJson(e)).toList(),
        vout: vout.map((e) => TransparentTxOutput.deserializeJson(e)).toList());
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.varintVector(TransparentTxInput.layout(), property: "vin"),
      LayoutConst.varintVector(TransparentTxOutput.layout(), property: "vout"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "vout": vout.map((e) => e.toSerializeJson()).toList(),
      "vin": vin.map((e) => e.toSerializeJson()).toList()
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}
