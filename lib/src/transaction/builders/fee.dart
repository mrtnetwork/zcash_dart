part of 'builder.dart';

mixin TransactionBuilderFeeContoller on BaseTransactionBuilder {
  ZAmount valueBalance() {
    final transparent = this.transparent.valueBalance();
    final orchard = this.orchard.valueBalance();
    final ironwood = this.ironwood.valueBalance();
    final sapling = this.sapling.valueBalance();
    return transparent + orchard + ironwood + sapling;
  }

  int _orchardActions() => orchard.bundleType.numActions(
    numSpends: orchard.spends.length,
    numOutputs: orchard.outputs.length + orchard.changes.length,
    crossAddressEnabled: !orchard.isRestricted,
  );

  int _ironwoodActions() => ironwood.bundleType.numActions(
    numSpends: ironwood.spends.length,
    numOutputs: ironwood.outputs.length + ironwood.changes.length,
    crossAddressEnabled: !ironwood.isRestricted,
  );

  ZAmount getFee() {
    return feeBuilder.feeRequired(
      network: network,
      targetHeight: targetHeight,
      trasparentInputSizes: transparent.inputSizes(),
      transparentOutputSizes: transparent.outputSizes(),
      saplingInputCount: sapling.spends.length,
      saplingOutputCount: sapling.bundleType.numOutputs(
        numSpends: sapling.spends.length,
        numOutputs: sapling.outputs.length,
      ),
      orchardActionCount: _orchardActions(),
      ironwoodActionCount: _ironwoodActions(),
    );
  }
}
