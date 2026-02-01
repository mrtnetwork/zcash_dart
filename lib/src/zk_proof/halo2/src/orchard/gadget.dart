import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poseidon/poseidon.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/sinsemilla.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/message.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/configs/add.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/configs/commit_ivk.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/constants/fixed_bases.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/configs/note_commit.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/merkle.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/range_constrained.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';

class OrchardGadget {
  static EccPointWithConfig valueCommitOrchard(Layouter layouter,
      EccConfig chip, EccScalarFixedShort v, EccScalarFixed rcv) {
    final (p, scalar) = chip.mulFixedShort(
        layouter: layouter, scalar: v, base: OrchardFixedBasesValueCommitV());
    final commitment = EccPointWithConfig(chip, p);
    final blind = EccPointWithConfig(
        chip,
        chip
            .mulFixed(
                layouter: layouter,
                scalar: rcv,
                base: OrchardFixedBasesFull.valueCommitR)
            .$1);
    // FixedPointWithEccChip(chip, OrchardFixedBasesFull.valueCommitR);
    // final blind = valueCommitR.mul(layouter, rcv).$1;
    return commitment.add(layouter, blind);
  }

  static AssignedCell<PallasNativeFp> deriveNullifier(
      Layouter layouter,
      Pow5Config poseidonChip,
      OrchardAddConfig addChip,
      EccConfig chip,
      AssignedCell<PallasNativeFp> rho,
      AssignedCell<PallasNativeFp> psi,
      EccPointWithConfig cm,
      AssignedCell<PallasNativeFp> nk) {
    final hash = () {
      final messages = [nk, rho];
      final hasher = HaloPoseidonHash.init(layouter, poseidonChip);
      return hasher.hash(layouter, messages);
    }();
    final scalar = addChip.add(layouter, hash, psi);
    final mul = chip.mulFixedBaseFieldElem(
        layouter: layouter,
        baseFieldElem: scalar,
        base: OrchardFixedBasesNullifierK());
    return cm.add(layouter, EccPointWithConfig(chip, mul)).extractP();
  }

  static AssignedCell<PallasNativeFp> commitIvk(
      SinsemillaConfig sinsemillaChip,
      EccConfig eccChip,
      CommitIvkConfig commitIvkChip,
      Layouter layouter,
      AssignedCell<PallasNativeFp> ak,
      AssignedCell<PallasNativeFp> nk,
      EccScalarFixed rivk,
      ZCashCryptoContext context) {
    final lookupConfig = sinsemillaChip.lookupConfig;

    // a = bits 0..=249 of ak
    final a = SinsemillaMessagePiece.fromSubpieces(
        chip: sinsemillaChip,
        layouter: layouter,
        subpieces: [RangeConstrained.bitrangeOf(ak.value, 0, 250)]);

    // b = b0 || b1 || b2
    final RangeConstrainedAssigned b0;
    final RangeConstrained<PallasNativeFp?> b1;
    final RangeConstrainedAssigned b2;
    final SinsemillaMessagePiece b;

    {
      b0 = sinsemillaChip.lookupConfig
          .witnessShort(layouter, ak.value, 250, 254);
      b1 = RangeConstrained.bitrangeOf(ak.value, 254, 255);
      b2 = sinsemillaChip.lookupConfig.witnessShort(layouter, nk.value, 0, 5);
      b = SinsemillaMessagePiece.fromSubpieces(
          chip: sinsemillaChip,
          layouter: layouter,
          subpieces: [b0.value(), b1, b2.value()]);
    }
    final c = SinsemillaMessagePiece.fromSubpieces(
        chip: sinsemillaChip,
        layouter: layouter,
        subpieces: [RangeConstrained.bitrangeOf(nk.value, 5, 245)]);
    final RangeConstrainedAssigned d0;
    final RangeConstrained<PallasNativeFp?> d1;
    final SinsemillaMessagePiece d;
    {
      d0 = sinsemillaChip.lookupConfig
          .witnessShort(layouter, nk.value, 245, 254);
      d1 = RangeConstrained.bitrangeOf(nk.value, 254, 255);
      d = SinsemillaMessagePiece.fromSubpieces(
          chip: sinsemillaChip,
          layouter: layouter,
          subpieces: [d0.value(), d1]);
    }

    // Hash ak || nk
    final SinsemillaMessage message = SinsemillaMessage([a, b, c, d]);

    final domain = HaloCommitDomains.init(
        eccChip,
        sinsemillaChip,
        context.getDomainPoint("z.cash:Orchard-CommitIvk"),
        OrchardFixedBasesFull.commitIvkR);

    final (ivk, zs) = domain.shortCommit(layouter, message, rivk);

    // Extract running sums for canonicity
    final z13a = zs[0][13];
    final z13c = zs[2][13];

    final akCanon = akCanonicity(lookupConfig, layouter, a.cellValue);

    final nkCanon = nkCanonicity(lookupConfig, layouter, b2, c.cellValue);

    final gateCells = GateCells(
        a: a.cellValue,
        b: b.cellValue,
        c: c.cellValue,
        d: d.cellValue,
        ak: ak,
        nk: nk,
        b0: b0,
        b1: b1,
        b2: b2,
        d0: d0,
        d1: d1,
        z13A: z13a,
        aPrime: akCanon.$1,
        z13APrime: akCanon.$2,
        z13C: z13c,
        b2CPrime: nkCanon.$1,
        z14B2CPrime: nkCanon.$2);
    commitIvkChip.assignGate(layouter, gateCells);

    return ivk;
  }

  /// Witnesses and decomposes the `b2c'` value needed to check canonicity of `nk`.
  ///
  /// Spec:
  /// https://p.z.cash/orchard-0.1:commit-ivk-canonicity-nk?partial
  ///
  /// Returns:
  ///  - b2cPrime : AssignedCell
  ///  - z14     : AssignedCell (running sum after 140 bits)
  static (
    AssignedCell<PallasNativeFp>,
    AssignedCell<PallasNativeFp>,
  ) nkCanonicity(
    LookupRangeCheckConfig lookupConfig,
    Layouter layouter,
    RangeConstrained<AssignedCell<PallasNativeFp>> b2,
    AssignedCell<PallasNativeFp> c,
  ) {
    PallasNativeFp? b2cPrimeValue;
    if (b2.inner.hasValue && c.hasValue) {
      b2cPrimeValue = b2.inner.getValue() +
          c.getValue() * PallasNativeFp.from(1 << 5) +
          PallasNativeFp(BigInt.one << 70).square() -
          PallasNativeFp(Halo2Utils.tP);
    }
    // Decompose low 140 bits (14 × 10-bit lookups)
    final List<AssignedCell<PallasNativeFp>> zs =
        lookupConfig.witnessCheck(layouter, b2cPrimeValue, 14, false);

    if (zs.length != 15) {
      throw Halo2Exception.operationFailed("nkCanonicity",
          reason: "Invalid running sums length.");
    }

    final AssignedCell<PallasNativeFp> b2cPrime = zs[0];
    final AssignedCell<PallasNativeFp> z14 = zs[14];

    return (b2cPrime, z14);
  }

  /// Witnesses and decomposes the `a'` value needed to check canonicity of `ak`.
  ///
  /// Spec:
  /// https://p.z.cash/orchard-0.1:commit-ivk-canonicity-ak?partial
  ///
  /// Returns:
  ///  - aPrime  : AssignedCell
  ///  - z13     : AssignedCell (running sum after 130 bits)
  static (
    AssignedCell<PallasNativeFp>,
    AssignedCell<PallasNativeFp>,
  ) akCanonicity(
    LookupRangeCheckConfig lookupConfig,
    Layouter layouter,
    AssignedCell<PallasNativeFp> a,
  ) {
    PallasNativeFp? aPrimeValue;
    if (a.hasValue) {
      aPrimeValue = a.getValue() +
          PallasNativeFp(BigInt.one << 65).square() -
          PallasNativeFp(Halo2Utils.tP);
    }

    // Decompose low 130 bits (13 × 10-bit lookups)
    final List<AssignedCell<PallasNativeFp>> zs =
        lookupConfig.witnessCheck(layouter, aPrimeValue, 13, false);

    if (zs.length != 14) {
      throw Halo2Exception.operationFailed("akCanonicity",
          reason: "Invalid running sums length.");
    }

    final AssignedCell<PallasNativeFp> aPrime = zs[0];
    final AssignedCell<PallasNativeFp> z13 = zs[13];

    return (aPrime, z13);
  }

  static EccPointWithConfig noteCommit(
      Layouter layouter,
      SinsemillaConfig chip,
      EccConfig eccChip,
      NoteCommitConfig noteCommitChip,
      EccPoint gD,
      EccPoint pkD,
      AssignedCell<PallasNativeFp> value,
      AssignedCell<PallasNativeFp> rho,
      AssignedCell<PallasNativeFp> psi,
      EccScalarFixed rcm,
      ZCashCryptoContext context) {
    final lookupConfig = chip.lookupConfig;

    // a = bits 0..=249 of x(g_d)
    final a = SinsemillaMessagePiece.fromSubpieces(
        chip: chip,
        layouter: layouter,
        subpieces: [
          RangeConstrained.bitrangeOf(gD.getX().value, 0, 250),
        ]);

    // b decomposition
    final (b, b0, b1, b2, b3) = noteCommitChip.b.decompose(
      lookupConfig,
      chip,
      layouter,
      gD,
      pkD,
    );
    // c = bits 4..=253 of pk★_d
    final c = SinsemillaMessagePiece.fromSubpieces(
      chip: chip,
      layouter: layouter,
      subpieces: [
        RangeConstrained.bitrangeOf(pkD.getX().value, 4, 254),
      ],
    );

    // d decomposition
    final (d, d0, d1, d2) = noteCommitChip.d.decompose(
      lookupConfig,
      chip,
      layouter,
      pkD,
      value,
    );

    // e decomposition
    final (e, e0, e1) = noteCommitChip.e.decompose(
      lookupConfig,
      chip,
      layouter,
      value,
      rho,
    );

    // f = bits 4..=253 of rho
    final f = SinsemillaMessagePiece.fromSubpieces(
      chip: chip,
      layouter: layouter,
      subpieces: [
        RangeConstrained.bitrangeOf(rho.value, 4, 254),
      ],
    );

    // g decomposition
    final (g, g0, g1) = noteCommitChip.g.decompose(
      lookupConfig,
      chip,
      layouter,
      rho,
      psi,
    );

    // h decomposition
    final (h, h0, h1) = noteCommitChip.h.decompose(
      lookupConfig,
      chip,
      layouter,
      psi,
    );

    // y-coordinate canonicity checks
    final b2Checked = yCanonicity(
      lookupConfig,
      noteCommitChip.yCanon,
      layouter,
      gD.getY(),
      b2,
    );

    final d1Checked = yCanonicity(
      lookupConfig,
      noteCommitChip.yCanon,
      layouter,
      pkD.getY(),
      d1,
    );

    // Commit
    final message = SinsemillaMessage([a, b, c, d, e, f, g, h]);

    final domain = HaloCommitDomains.init(
        eccChip,
        chip,
        context.getDomainPoint("z.cash:Orchard-NoteCommit"),
        OrchardFixedBasesFull.noteCommitR);

    final (cm, zs) = domain.commit(
      layouter,
      message,
      rcm,
    );

    // Extract running sums
    final z13a = zs[0][13];
    final z13c = zs[2][13];
    final z1d = zs[3][1];
    final z13f = zs[5][13];
    final z1g = zs[6][1];
    final g2 = z1g;
    final z13g = zs[6][13];

    // Canonicity witnesses
    final canonA = canonBitshift130(lookupConfig, layouter, a.cellValue);

    final canonPk = pkdXCanonicity(lookupConfig, layouter, b3, c.cellValue);

    final canonRho = rhoCanonicity(lookupConfig, layouter, e1, f.cellValue);

    final canonPsi = psiCanonicity(lookupConfig, layouter, g1, g2);

    // Final gate assignments
    final cfg = noteCommitChip;

    final b1Assigned = cfg.b.assign(layouter, b, b0, b1, b2Checked, b3);

    final d0Assigned = cfg.d.assign(layouter, d, d0, d1Checked, d2, z1d);

    cfg.e.assign(layouter, e, e0, e1);

    final g0Assigned = cfg.g.assign(layouter, g, g0, g1, z1g);

    final h1Assigned = cfg.h.assign(layouter, h, h0, h1);

    cfg.gD.assign(
      layouter,
      gD,
      a,
      b0,
      b1Assigned,
      canonA.$1,
      z13a,
      canonA.$2,
    );

    cfg.pkD.assign(
      layouter,
      pkD,
      b3,
      c,
      d0Assigned,
      canonPk.$1,
      z13c,
      canonPk.$2,
    );

    cfg.value.assign(layouter, value, d2, z1d, e0);

    cfg.rho.assign(
      layouter,
      rho,
      e1,
      f,
      g0Assigned,
      canonRho.$1,
      z13f,
      canonRho.$2,
    );

    cfg.psi.assign(
      layouter,
      psi,
      g1,
      z1g,
      h0,
      h1Assigned,
      canonPsi.$1,
      z13g,
      canonPsi.$2,
    );

    return cm;
  }

  static (AssignedCell<PallasNativeFp>, AssignedCell<PallasNativeFp>)
      canonBitshift130(LookupRangeCheckConfig lookupConfig, Layouter layouter,
          AssignedCell<PallasNativeFp> a) {
    final PallasNativeFp? aPrime = () {
      if (!a.hasValue) {
        return null;
      }
      final twoPow130 = PallasNativeFp(BigInt.one << 65).square();
      final tp = PallasNativeFp(Halo2Utils.tP);
      return a.getValue() + twoPow130 - tp;
    }();
    final zs = lookupConfig.witnessCheck(layouter, aPrime, 13, false);
    final aPrime_ = zs[0];
    assert(zs.length == 14);
    return (aPrime_, zs[13]);
  }

  static RangeConstrained<AssignedCell<PallasNativeFp>> yCanonicity(
    LookupRangeCheckConfig lookupConfig,
    YCanonicity yCanon,
    Layouter layouter,
    AssignedCell<PallasNativeFp> y,
    RangeConstrained<PallasNativeFp?> lsb,
  ) {
    // Range-constrain k_0 to be 9 bits
    final k0 = lookupConfig.witnessShort(layouter, y.value, 1, 10);

    // k_1 will be constrained by decomposition of j
    final k1 = RangeConstrained.bitrangeOf(y.value, 10, 250);

    // Range-constrain k_2 to be 4 bits
    final k2 = lookupConfig.witnessShort(layouter, y.value, 250, 254);

    // k_3 will be boolean-constrained in the gate
    final k3 = RangeConstrained.bitrangeOf(y.value, 254, 255);
    // Decompose j = LSB + 2 * k0 + 2^10 * k1 using 25 ten-bit lookups
    final PallasNativeFp? jValue = () {
      if (lsb.inner != null && k0.inner.hasValue && k1.inner != null) {
        final two = PallasNativeFp.from(2);
        final twoPow10 = PallasNativeFp.from(1 << 10);
        return lsb.inner! + two * k0.inner.value! + twoPow10 * k1.inner!;
      }

      return null;
    }();

    final zs = lookupConfig.witnessCheck(layouter, jValue, 25, true);

    final j = zs[0];
    final z1J = zs[1];
    final z13J = zs[13];

    // Decompose j_prime = j + 2^130 - t_P using 13 ten-bit lookups
    final (jPrime, z13JPrime) = canonBitshift130(lookupConfig, layouter, j);

    return yCanon.assign(
      layouter,
      y,
      lsb,
      k0,
      k2,
      k3,
      j,
      z1J,
      z13J,
      jPrime,
      z13JPrime,
    );
  }

  static (AssignedCell<PallasNativeFp>, AssignedCell<PallasNativeFp>)
      pkdXCanonicity(
    LookupRangeCheckConfig lookupConfig,
    Layouter layouter,
    RangeConstrained<AssignedCell<PallasNativeFp>> b3,
    AssignedCell<PallasNativeFp> c,
  ) {
    // `x(pk_d)` = `b_3 (4 bits) || c (250 bits) || d_0 (1 bit)`
    // - d_0 = 1 => b_3 + 2^4 c < t_P
    //     - 0 ≤ b_3 + 2^4 c < 2^134
    //     - 0 ≤ b_3 + 2^4 c + 2^140 - t_P < 2^140

    // Constants

    // b3_c_prime = b_3 + 2^4 c + 2^140 - t_P
    final PallasNativeFp? b3CPrimeValue = () {
      if (b3.inner.hasValue && c.hasValue) {
        final twoPow4 = PallasNativeFp.from(1 << 4);
        final twoPow140 = PallasNativeFp(BigInt.one << 70).square();
        final tP = PallasNativeFp(Halo2Utils.tP);
        return b3.inner.getValue() + (twoPow4 * c.getValue()) + twoPow140 - tP;
      }
      return null;
    }();

    // Decompose the low 140 bits using 14 ten-bit lookups
    final zs = lookupConfig.witnessCheck(layouter, b3CPrimeValue, 14, false);

    assert(zs.length == 15); // [z_0, z_1, ..., z_13, z_14]

    final b3CPrimeLow = zs[0];
    final runningSum = zs[14];

    return (b3CPrimeLow, runningSum);
  }

  static (AssignedCell<PallasNativeFp>, AssignedCell<PallasNativeFp>)
      rhoCanonicity(
    LookupRangeCheckConfig lookupConfig,
    Layouter layouter,
    RangeConstrained<AssignedCell<PallasNativeFp>> e1,
    AssignedCell<PallasNativeFp> f,
  ) {
    // `rho` = `e_1 (4 bits) || f (250 bits) || g_0 (1 bit)`
    // - g_0 = 1 => e_1 + 2^4 f < t_P
    // - 0 ≤ e_1 + 2^4 f < 2^134
    //     - e_1 is part of the Sinsemilla message piece
    //       e = e_0 (56 bits) || e_1 (4 bits)
    //     - e_1 is individually constrained to be 4 bits.
    //     - z_13 of SinsemillaHash(f) == 0 constrains bits 4..=253 of rho
    //       to 130 bits. z13_f == 0 is directly checked in the gate.
    // - 0 ≤ e_1 + 2^4 f + 2^140 - t_P < 2^140 (14 ten-bit lookups)

    // e1_f_prime = e_1 + 2^4 f + 2^140 - t_P
    final PallasNativeFp? e1FPrimeValue = () {
      if (e1.inner.hasValue && f.hasValue) {
        final twoPow4 = PallasNativeFp.from(1 << 4);
        final twoPow140 = PallasNativeFp(BigInt.one << 70).square();
        final tP = PallasNativeFp(Halo2Utils.tP);
        return e1.inner.getValue() + (twoPow4 * f.getValue()) + twoPow140 - tP;
      }
      return null;
    }();

    // Decompose the low 140 bits of e1_f_prime
    final zs = lookupConfig.witnessCheck(layouter, e1FPrimeValue, 14, false);

    assert(zs.length == 15); // [z_0, z_1, ..., z_13, z_14]

    final e1FPrimeLow = zs[0];
    final runningSum = zs[14];

    return (e1FPrimeLow, runningSum);
  }

  /// Check canonicity of `psi` encoding.
  ///
  /// Specification:
  /// https://p.z.cash/orchard-0.1:note-commit-canonicity-psi?partial
  static (AssignedCell<PallasNativeFp>, AssignedCell<PallasNativeFp>)
      psiCanonicity(
    LookupRangeCheckConfig lookupConfig,
    Layouter layouter,
    RangeConstrained<AssignedCell<PallasNativeFp>> g1,
    AssignedCell<PallasNativeFp> g2,
  ) {
    // `psi` = `g_1 (9 bits) || g_2 (240 bits) || h_0 (5 bits) || h_1 (1 bit)`
    // - h_1 = 1 => (h_0 = 0) ∧ (g_1 + 2^9 g_2 < t_P)
    // - 0 ≤ g_1 + 2^9 g_2 < 2^130
    //     - g_1 is individually constrained to be 9 bits
    //     - z_13 of SinsemillaHash(g) == 0 constrains bits 0..=248 of psi
    //       to 130 bits. z13_g == 0 is directly checked in the gate.
    // - 0 ≤ g_1 + (2^9)g_2 + 2^130 - t_P < 2^130 (13 ten-bit lookups)

    // g1_g2_prime = g_1 + (2^9)g_2 + 2^130 - t_P
    final PallasNativeFp? g1G2PrimeValue = () {
      if (g1.inner.hasValue && g2.hasValue) {
        final twoPow9 = PallasNativeFp.from(1 << 9);
        final twoPow130 = PallasNativeFp(BigInt.one << 65).square();
        final tP = PallasNativeFp(Halo2Utils.tP);

        return g1.inner.getValue() + (twoPow9 * g2.getValue()) + twoPow130 - tP;
      }
      return null;
    }();

    // Decompose the low 130 bits of g1_g2_prime
    final zs = lookupConfig.witnessCheck(
      layouter,
      g1G2PrimeValue,
      13,
      false,
    );

    assert(zs.length == 14); // [z_0, z_1, ..., z_13]

    final g1G2PrimeLow = zs[0];
    final runningSum = zs[13];

    return (g1G2PrimeLow, runningSum);
  }
}
