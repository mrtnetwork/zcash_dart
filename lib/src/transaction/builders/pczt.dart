part of 'builder.dart';

mixin TransactionBuilderPcztContoller on BaseTransactionBuilder {
  PcztWithMetadata? _pczt;

  /// Consensus branch for [targetHeight], used for PCZT global and
  /// bundle-version selection.
  ZcashNetworkProtocol get _branch =>
      activationProvider.protocolFromHeight(network, targetHeight);

  /// Suggested transaction version for [_branch].
  TxVersion get _suggestedVersion {
    return TxVersionType.v5.suggestedVersionForBranch(_branch);
  }

  PcztGlobal _buildGlobal() {
    final version = _suggestedVersion;
    return PcztGlobal(
      txVersion: version.type.txVesion,
      versionGroupId: version.type.groupId ?? 0,
      consensusBranchId: _branch.branchId,
      expiryHeight: expiryHeight,
      coinType: network.config().coinIdx,
      txModifiable: PcztConstants.initialTxModifiable,
    );
  }

  /// Places each built Orchard-family PCZT bundle into its pool slot:
  /// the `orchard` slot for the Orchard pool, the trailing `ironwood`
  /// slot for the Ironwood pool. An ironwood builder with no actions
  /// leaves the slot absent.
  ({OrchardPcztBundle orchard, OrchardPcztBundle? ironwood}) _placeSlots(
    OrchardPcztBundle orchardBuilt,
    OrchardPcztBundle ironwoodBuilt,
  ) {
    OrchardPcztBundle? ironwood;
    if (ironwoodBuilt.actions.isNotEmpty) {
      ironwood = ironwoodBuilt;
    }
    return (orchard: orchardBuilt, ironwood: ironwood);
  }

  Pczt toPczt() {
    final slots = _placeSlots(
      orchard.toPczt().bundle,
      ironwood.toPczt().bundle,
    );
    return Pczt(
      global: _buildGlobal(),
      transparent: transparent.toPczt().bundle,
      sapling: sapling.toPczt().bundle,
      orchard: slots.orchard,
      ironwood: slots.ironwood,
    );
  }

  PcztWithMetadata _toPcztInternal() {
    final transparent = this.transparent.toPczt();
    final sapling = this.sapling.toPczt();
    final orchard = this.orchard.toPczt();
    final ironwood = this.ironwood.toPczt();
    final slots = _placeSlots(orchard.bundle, ironwood.bundle);
    final pczt = Pczt(
      global: _buildGlobal(),
      transparent: transparent.bundle,
      sapling: sapling.bundle,
      orchard: slots.orchard,
      ironwood: slots.ironwood,
    );
    // Fail fast on inconsistent version/branch/slot/flag combinations.
    pczt.validate();
    return PcztWithMetadata(
      pczt: pczt,
      orchard: orchard.metadata,
      sapling: sapling.metadata,
      ironwood: ironwood.metadata,
    );
  }

  PcztWithMetadata _getPczt() {
    return _pczt ??= _toPcztInternal();
  }

  Future<T> _modify<T extends Object?>(
    Future<T> Function(
      bool shieldedModifiable,
      bool inputsModifiable,
      bool outputsModifiable,
    )
    updater,
  ) {
    return lock.run(() async {
      try {
        final pczt = _pczt?.pczt;
        if (pczt == null) {
          return await updater(true, true, true);
        }
        final result = await updater(
          pczt.global.shieldedModifiable(),
          pczt.global.inputsModifiable(),
          pczt.global.outputsModifiable(),
        );
        final newPczt = _toPcztInternal();
        final n = pczt.merge(newPczt.pczt);
        if (n == null) {
          throw ZcashErrors.txBuilderFailed("merge");
        }
        _pczt = PcztWithMetadata(
          pczt: n,
          orchard: newPczt.orchard,
          sapling: newPczt.sapling,
          ironwood: newPczt.ironwood,
        );
        return result;
      } on BuError catch (e) {
        if (e.type == ZcashErrorType.pcztFailed ||
            e.type == ZcashErrorType.saplingPcztFailed ||
            e.type == ZcashErrorType.orchardPcztFailed ||
            e.type == ZcashErrorType.transparentPcztFailed) {
          throw BuError(
            ZcashErrorType.txBuilderFailed,
            e.message,
            details: e.details,
          );
        }
        rethrow;
      }
    });
  }

  Future<T> _finalizeIo<T extends Object?>(
    Future<T> Function(PcztWithMetadata pczt) updater,
  ) {
    return lock.run(() async {
      try {
        // bool finalized = _finalized;
        final pczt = _getPczt().clone();
        // if (!finalized) {
        //   await pczt.pczt.finalizeIo(context);
        //   finalized = true;
        // }
        final result = await updater(pczt);
        _pczt = pczt;
        // _finalized = finalized;
        return result;
      } on BuError catch (e) {
        if (e.type == ZcashErrorType.pcztFailed ||
            e.type == ZcashErrorType.saplingPcztFailed ||
            e.type == ZcashErrorType.orchardPcztFailed ||
            e.type == ZcashErrorType.transparentPcztFailed) {
          throw BuError(
            ZcashErrorType.txBuilderFailed,
            e.message,
            details: e.details,
          );
        }
        rethrow;
      }
    });
  }

  Future<T> _finalizeTransparent<T extends Object?>(
    Future<T> Function(Pczt pczt) updater,
  ) {
    return lock.run(() async {
      try {
        final pczt = _getPczt().clone();
        final result = await updater(pczt.pczt);
        _pczt = pczt;
        return result;
      } on BuError catch (e) {
        if (e.type == ZcashErrorType.pcztFailed ||
            e.type == ZcashErrorType.saplingPcztFailed ||
            e.type == ZcashErrorType.orchardPcztFailed ||
            e.type == ZcashErrorType.transparentPcztFailed) {
          throw BuError(
            ZcashErrorType.txBuilderFailed,
            e.message,
            details: e.details,
          );
        }
        rethrow;
      }
    });
  }
}
