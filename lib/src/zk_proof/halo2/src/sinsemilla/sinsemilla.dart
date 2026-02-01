import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/message.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/constants/fixed_bases.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/merkle.dart';

class HaloHashDomain {
  final SinsemillaConfig chip;
  final EccConfig eccChip;
  final PallasAffineNativePoint q;
  const HaloHashDomain(this.chip, this.eccChip, this.q);

  (EccPointWithConfig, List<List<AssignedCell<PallasNativeFp>>>) hashToPoint(
      Layouter layouter, SinsemillaMessage message) {
    final (p, r) = chip.hashToPoint(layouter, q, message);
    return (EccPointWithConfig(eccChip, p), r);
  }

  (EccPoint, List<List<AssignedCell<PallasNativeFp>>>)
      hashToPointWithPrivateInit(
              Layouter layouter, EccPoint q, SinsemillaMessage message) =>
          chip.hashToPointWithPrivateInit(layouter, q, message);

  (AssignedCell<PallasNativeFp>, List<List<AssignedCell<PallasNativeFp>>>) hash(
      Layouter layouter, SinsemillaMessage message) {
    final (pint, runningSums) = chip.hashToPoint(layouter, q, message);
    return (pint.getY(), runningSums);
  }
}

class HaloCommitDomains {
  final HaloHashDomain m;
  final OrchardFixedBasesFull r;
  const HaloCommitDomains(this.m, this.r);
  factory HaloCommitDomains.init(
      EccConfig chip,
      SinsemillaConfig sinsemillaChip,
      PallasAffineNativePoint q,
      OrchardFixedBasesFull r) {
    return HaloCommitDomains(HaloHashDomain(sinsemillaChip, chip, q), r);
  }

  (EccPointWithConfig, List<List<AssignedCell<PallasNativeFp>>>) commit(
      Layouter layouter, SinsemillaMessage message, EccScalarFixed r) {
    final EccPointWithConfig blind = EccPointWithConfig(m.eccChip,
        m.eccChip.mulFixed(layouter: layouter, scalar: r, base: this.r).$1);
    final (p, zs) = m.hashToPoint(layouter, message);
    final commitment = p.add(layouter, blind);
    return (commitment, zs);
  }

  (AssignedCell<PallasNativeFp>, List<List<AssignedCell<PallasNativeFp>>>)
      shortCommit(
          Layouter layouter, SinsemillaMessage message, EccScalarFixed r) {
    final (p, z) = commit(layouter, message, r);
    return (p.extractP(), z);
  }
}
