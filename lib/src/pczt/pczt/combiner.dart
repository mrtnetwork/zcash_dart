import 'package:zcash_dart/src/pczt/pczt/pczt.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';

abstract mixin class PcztCombiner implements PcztV1 {
  /// Attempts to merge with another; returns null if merging is not possible.
  Pczt? merge(Pczt other) {
    final global = this.global.merge(other.global);
    if (global == null) return null;
    final transparent = this.transparent.merge(
        other: other.transparent, global: global, otherGlobal: other.global);
    if (transparent == null) return null;
    final sapling = this
        .sapling
        .merge(other: other.sapling, global: global, otherGlobal: other.global);
    if (sapling == null) return null;
    final orchard = this
        .orchard
        .merge(other: other.orchard, global: global, otherGlobal: other.global);
    if (orchard == null) return null;
    return Pczt(
        global: global,
        transparent: transparent,
        sapling: sapling,
        orchard: orchard);
  }

  Pczt clone() => Pczt(
      global: global.clone(),
      transparent: transparent.clone(),
      sapling: sapling.clone(),
      orchard: orchard.clone());
}
