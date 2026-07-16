import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/transparent/builder/exception.dart';
import 'package:zcash_dart/src/transparent/pczt/pczt.dart';
import 'package:zcash_dart/src/transparent/pczt/utils.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/transaction/bundle.dart';
import 'package:zcash_dart/src/transparent/transaction/input.dart';
import 'package:zcash_dart/src/transparent/transaction/output.dart';
import 'package:zcash_dart/src/transparent/transaction/utxo.dart';
import 'package:zcash_dart/src/value/value.dart';

class TransparentBuilderConstant {
  static const int maxOpReturn = 80;
}

class TransparentSigningInput {
  final TransparentUtxoWithOwner input;
  final int sighash;
  final int? sequence;
  const TransparentSigningInput({
    required this.input,
    this.sighash = BitcoinOpCodeConst.sighashAll,
    this.sequence,
  });

  TransparentTxInput toInput({Script? scriptSig}) {
    return input.utxo.toInput(sequence: sequence, scriptSig: scriptSig);
  }
}

class TransparentBuilder
    implements
        BundleBuilder<
          TransparentBundle,
          TransparentExtractedBundle,
          TransparentPcztBundle,
          List<TransparentUtxoWithOwner>
        > {
  List<TransparentSigningInput> _inputs;
  List<BaseTransparentOutputInfo> _outputs;
  List<TransparentSigningInput> get inputs => _inputs;
  List<BaseTransparentOutputInfo> get output => _outputs;
  PcztBundleWithMetadata<
    TransparentBundle,
    TransparentExtractedBundle,
    TransparentPcztBundle
  >?
  _cachedPczt;
  TransparentBuilder({
    List<TransparentSigningInput> inputs = const [],
    List<BaseTransparentOutputInfo> outputs = const [],
  }) : _inputs = inputs.immutable,
       _outputs = outputs.immutable;

  int _addInput(TransparentSigningInput input) {
    _inputs = [..._inputs, input].immutable;
    _cachedPczt = null;
    return _inputs.indexOf(input).asPositive;
  }

  int _addOutput(BaseTransparentOutputInfo output) {
    _outputs = [..._outputs, output].immutable;
    _cachedPczt = null;
    return _outputs.indexOf(output).asPositive;
  }

  /// Adds a transparent UTXO as an input.
  int addInput(TransparentSigningInput input) {
    if (input.input.ownerDetails.toAddress() !=
        input.input.ownerDetails.address) {
      throw TransparentBuilderException.operationFailed(
        "addInput",
        reason: "Invalid input address.",
      );
    }
    if (_inputs.any((e) => e.input.utxo == input.input.utxo)) {
      throw TransparentBuilderException.operationFailed(
        "addInput",
        reason: "Duplicate transparent input.",
      );
    }
    return _addInput(input);
  }

  /// Adds a transparent output
  int addOutput(BaseTransparentOutputInfo output) {
    return _addOutput(output);
  }

  @override
  ZAmount valueBalance() {
    final inputs = _inputs.fold<ZAmount>(
      ZAmount.zero(),
      (p, c) => p + c.input.utxo.amount,
    );
    final outputs = _outputs.fold<ZAmount>(
      ZAmount.zero(),
      (p, c) => p + c.value,
    );
    return inputs - outputs;
  }

  /// build bundle. return null if inputs and outputs is ampty.
  @override
  BundleWithMetadata<TransparentBundle, List<TransparentUtxoWithOwner>>?
  build() {
    if (_inputs.isEmpty && _outputs.isEmpty) return null;
    return BundleWithMetadata(
      bundle: TransparentBundle(
        vin: _inputs.map((e) => e.toInput()).toList(),
        vout: _outputs.map((e) => e.toOutput()).toList(),
      ),
      data: _inputs.map((e) => e.input).toList(),
    );
  }

  /// build pczt bundle. return null if inputs and outputs is ampty.
  @override
  PcztBundleWithMetadata<
    TransparentBundle,
    TransparentExtractedBundle,
    TransparentPcztBundle
  >
  toPczt() {
    final pczt =
        _cachedPczt ??= () {
          final inputs =
              _inputs.map((e) {
                return TransparentPcztInput(
                  prevoutTxid: e.input.utxo.txId,
                  prevoutIndex: e.input.utxo.vout,
                  value: e.input.utxo.amount.toI64(),
                  scriptPubkey: e.input.ownerDetails.address.toScriptPubKey(),
                  sequence: e.sequence,
                  redeemScript:
                      e.input.ownerDetails.address.type.isP2sh
                          ? e.input.ownerDetails.reedemScript()
                          : null,
                  sighashType: e.sighash,
                );
              }).toList();
          final outputs =
              _outputs.map((e) {
                final output = e.toOutput();
                return TransparentPcztOutput(
                  value: output.amount,
                  scriptPubkey: output.scriptPubKey,
                );
              }).toList();
          return PcztBundleWithMetadata<
            TransparentBundle,
            TransparentExtractedBundle,
            TransparentPcztBundle
          >(
            metadata: BundleMetadata(
              outputIndices: outputs.indexed.map((e) => e.$1).toList(),
              spendIndices: inputs.indexed.map((e) => e.$1).toList(),
            ),
            bundle: TransparentPcztBundle(inputs: inputs, outputs: outputs),
          );
        }();
    return pczt.clone();
  }

  /// output sizes in binary.
  int outputSizes() => _outputs
      .map((e) => e.toOutput().toSerializeBytes())
      .fold(0, (p, c) => p + c.length);

  /// input sizes in binary.
  int inputSizes() {
    return _inputs
        .map((e) {
          final scriptSig = TransparentPcztUtils.generateScriptSig(
            TransparentPcztInput(
              prevoutTxid: e.input.utxo.txId,
              prevoutIndex: e.input.utxo.vout,
              value: e.input.utxo.amount.toI64(),
              scriptPubkey: e.input.ownerDetails.address.toScriptPubKey(),
              redeemScript:
                  e.input.ownerDetails.address.type.isP2sh
                      ? e.input.ownerDetails.reedemScript()
                      : null,
              sighashType: BitcoinOpCodeConst.sighashAll,
            ),
            fake: true,
          );
          final input = e.toInput(scriptSig: scriptSig);
          return input.toSerializeBytes();
        })
        .fold(0, (p, c) => p + c.length);
  }
}
