part of 'builder.dart';

mixin TransactionBuilderPcztContoller on BaseTransactionBuilder {
  PcztWithMetadata? _pczt;

  Pczt toPczt() {
    return Pczt(
      global: PcztGlobal.defaultGlobal(network, expiryHeight),
      transparent: transparent.toPczt().bundle,
      sapling: sapling.toPczt().bundle,
      orchard: orchard.toPczt().bundle,
    );
  }

  PcztWithMetadata _toPcztInternal() {
    final transparent = this.transparent.toPczt();
    final sapling = this.sapling.toPczt();
    final orchard = this.orchard.toPczt();
    final pczt = Pczt(
      global: PcztGlobal.defaultGlobal(network, expiryHeight),
      transparent: transparent.bundle,
      sapling: sapling.bundle,
      orchard: orchard.bundle,
    );
    return PcztWithMetadata(
      pczt: pczt,
      orchard: orchard.metadata,
      sapling: sapling.metadata,
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
          return updater(true, true, true);
        }
        final result = await updater(
          pczt.global.shieldedModifiable(),
          pczt.global.inputsModifiable(),
          pczt.global.outputsModifiable(),
        );
        final newPczt = _toPcztInternal();
        final n = pczt.merge(newPczt.pczt);
        if (n == null) {
          throw TransactionBuilderException.failed("merge");
        }
        _pczt = PcztWithMetadata(
          pczt: n,
          orchard: newPczt.orchard,
          sapling: newPczt.sapling,
        );
        return result;
      } on PcztException catch (e) {
        throw TransactionBuilderException(e.message, details: e.details);
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
      } on PcztException catch (e) {
        throw TransactionBuilderException(e.message, details: e.details);
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
      } on PcztException catch (e) {
        throw TransactionBuilderException(e.message, details: e.details);
      }
    });
  }
}
