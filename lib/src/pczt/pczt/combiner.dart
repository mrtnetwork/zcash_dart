import 'package:zcash_dart/src/orchard/pczt/pczt.dart';
import 'package:zcash_dart/src/pczt/pczt/pczt.dart';
import 'package:zcash_dart/src/pczt/types/global.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';

abstract mixin class PcztCombiner implements PcztV1 {
  /// Attempts to merge with another; returns null if merging is not possible.
  Pczt? merge(Pczt other) {
    final global = this.global.merge(other.global);
    if (global == null) return null;
    final transparent = this.transparent.merge(
      other: other.transparent,
      global: global,
      otherGlobal: other.global,
    );
    if (transparent == null) return null;
    final sapling = this.sapling.merge(
      other: other.sapling,
      global: global,
      otherGlobal: other.global,
    );
    if (sapling == null) return null;
    final orchard = this.orchard.merge(
      other: other.orchard,
      global: global,
      otherGlobal: other.global,
    );
    if (orchard == null) return null;
    final ironwood = mergeIronwoodBundles(
      this.ironwood,
      other.ironwood,
      global: global,
      otherGlobal: other.global,
    );
    if (this.ironwood != null && ironwood == null) return null;
    if (other.ironwood != null && ironwood == null) return null;
    return Pczt(
      global: global,
      transparent: transparent,
      sapling: sapling,
      orchard: orchard,
      ironwood: ironwood,
    );
  }

  Pczt clone() => Pczt(
    global: global.clone(),
    transparent: transparent.clone(),
    sapling: sapling.clone(),
    orchard: orchard.clone(),
    ironwood: ironwood?.clone(),
  );
}

/// Merges two optional Ironwood bundles. Null merges with anything;
/// two non-null bundles use the Orchard merge rules.
OrchardPcztBundle? mergeIronwoodBundles(
  OrchardPcztBundle? a,
  OrchardPcztBundle? b, {
  required PcztGlobal global,
  required PcztGlobal otherGlobal,
}) {
  if (a == null) return b?.clone();
  if (b == null) return a.clone();
  return a.merge(other: b, global: global, otherGlobal: otherGlobal);
}
