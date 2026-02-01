part of 'builder.dart';

mixin TransactionBuilderFeeContoller on BaseTransactionBuilder {
  ZAmount valueBalance() {
    final transparent = this.transparent.valueBalance();
    final orchard = this.orchard.valueBalance();
    final sapling = this.sapling.valueBalance();
    return transparent + orchard + sapling;
  }

  ZAmount getFee() {
    return feeBuilder.feeRequired(
        network: network,
        targetHeight: targetHeight,
        trasparentInputSizes: transparent.inputSizes(),
        transparentOutputSizes: transparent.outputSizes(),
        saplingInputCount: sapling.spends.length,
        saplingOutputCount: sapling.bundleType.numOutputs(
            numSpends: sapling.spends.length,
            numOutputs: sapling.outputs.length),
        orchardActionCount: orchard.bundleType.numActions(
            numSpends: orchard.spends.length,
            numOutputs: orchard.outputs.length));
  }
}
