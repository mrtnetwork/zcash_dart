import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/message.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/merkle.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/range_constrained.dart';

class DecomposeB {
  final Selector qNotecommitB;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;

  const DecomposeB(
      {required this.qNotecommitB,
      required this.colL,
      required this.colM,
      required this.colR});

  factory DecomposeB.configure(
      ConstraintSystem meta,
      Column<Advice> colL,
      Column<Advice> colM,
      Column<Advice> colR,
      PallasNativeFp twoPow4,
      PallasNativeFp twoPow5,
      PallasNativeFp twoPow6) {
    final qNotecommitB = meta.selector();
    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitB);

      // b has been constrained to 10 bits by the Sinsemilla hash
      final b = meta.queryAdvice(colL, Rotation.cur());

      // b_0 has been constrained to be 4 bits outside this gate
      final b0 = meta.queryAdvice(colM, Rotation.cur());

      // This gate constrains b_1 to be boolean
      final b1 = meta.queryAdvice(colR, Rotation.cur());

      // This gate constrains b_2 to be boolean
      final b2 = meta.queryAdvice(colM, Rotation.next());

      // b_3 has been constrained to 4 bits outside this gate
      final b3 = meta.queryAdvice(colR, Rotation.next());

      // b = b0 + 2^4 * b1 + 2^5 * b2 + 2^6 * b3
      final decompositionCheck =
          b - (b0 + b1 * twoPow4 + b2 * twoPow5 + b3 * twoPow6);

      return Constraints(selector: q, constraints: [
        Halo2Utils.boolCheck(b1),
        Halo2Utils.boolCheck(b2),
        decompositionCheck
      ]);
    });
    return DecomposeB(
        qNotecommitB: qNotecommitB, colL: colL, colM: colM, colR: colR);
  }

  (
    SinsemillaMessagePiece,
    RangeConstrained<AssignedCell<PallasNativeFp>>,
    RangeConstrained<PallasNativeFp?>,
    RangeConstrained<PallasNativeFp?>,
    RangeConstrained<AssignedCell<PallasNativeFp>>,
  ) decompose(
    LookupRangeCheckConfig lookupConfig,
    SinsemillaConfig chip,
    Layouter layouter,
    EccPoint gD,
    EccPoint pkD,
  ) {
    final gdX = gD.getX();
    final gdY = gD.getY();

    // Constrain b_0 to be 4 bits (bits 250..253)
    final b0 = lookupConfig.witnessShort(layouter, gdX.value, 250, 254);

    // b_1, b_2 are boolean-constrained in the gate
    final b1 = RangeConstrained.bitrangeOf(gdX.value, 254, 255);

    final b2 = RangeConstrained.bitrangeOf(gdY.value, 0, 1);
    // Constrain b_3 to be 4 bits (bits 0..3 of pk_d.x)
    final b3 = lookupConfig.witnessShort(layouter, pkD.getX().value, 0, 4);
    final b = SinsemillaMessagePiece.fromSubpieces(
        chip: chip,
        layouter: layouter,
        subpieces: [b0.value(), b1, b2, b3.value()]);
    return (b, b0, b1, b2, b3);
  }

  AssignedCell<PallasNativeFp> assign(
    Layouter layouter,
    SinsemillaMessagePiece b,
    RangeConstrained<AssignedCell<PallasNativeFp>> b0,
    RangeConstrained<PallasNativeFp?> b1,
    RangeConstrained<AssignedCell<PallasNativeFp>> b2,
    RangeConstrained<AssignedCell<PallasNativeFp>> b3,
  ) {
    return layouter.assignRegion(
      (Region region) {
        // Enable selector
        qNotecommitB.enable(region: region, offset: 0);
        // Row 0
        b.cellValue.copyAdvice(region, colL, 0);
        b0.inner.copyAdvice(region, colM, 0);
        final assignedB1 = region.assignAdvice(colR, 0, () => b1.inner);

        b2.inner.copyAdvice(region, colM, 1);

        b3.inner.copyAdvice(region, colR, 1);

        return assignedB1;
      },
    );
  }
}

class DecomposeD {
  final Selector qNotecommitD;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;

  const DecomposeD({
    required this.qNotecommitD,
    required this.colL,
    required this.colM,
    required this.colR,
  });

  factory DecomposeD.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    PallasNativeFp two,
    PallasNativeFp twoPow2,
    PallasNativeFp twoPow10,
  ) {
    final qNotecommitD = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitD);

      // d has been constrained to 60 bits by the Sinsemilla hash
      final d = meta.queryAdvice(colL, Rotation.cur());

      // This gate constrains d_0 to be boolean
      final d0 = meta.queryAdvice(colM, Rotation.cur());

      // This gate constrains d_1 to be boolean
      final d1 = meta.queryAdvice(colR, Rotation.cur());

      // d_2 has been constrained to 8 bits outside this gate
      final d2 = meta.queryAdvice(colM, Rotation.next());

      // d_3 is set to z1_d
      final d3 = meta.queryAdvice(colR, Rotation.next());

      // d = d0 + 2 * d1 + 2^2 * d2 + 2^10 * d3
      final decompositionCheck =
          d - (d0 + d1 * two + d2 * twoPow2 + d3 * twoPow10);

      return Constraints(selector: q, constraints: [
        Halo2Utils.boolCheck(d0),
        Halo2Utils.boolCheck(d1),
        decompositionCheck
      ]);
    });

    return DecomposeD(
        qNotecommitD: qNotecommitD, colL: colL, colM: colM, colR: colR);
  }

  (
    SinsemillaMessagePiece,
    RangeConstrained<PallasNativeFp?>,
    RangeConstrained<PallasNativeFp?>,
    RangeConstrained<AssignedCell<PallasNativeFp>>
  ) decompose(
    LookupRangeCheckConfig lookupConfig,
    SinsemillaConfig chip,
    Layouter layouter,
    EccPoint pkD,
    AssignedCell<PallasNativeFp> value,
  ) {
    // Convert NoteValue to pallas::Base
    final valueVal = value.value;

    // d_0, d_1 will be boolean-constrained in the gate
    final d0 = RangeConstrained.bitrangeOf(pkD.getX().value, 254, 255);
    final d1 = RangeConstrained.bitrangeOf(pkD.getY().value, 0, 1);

    // Constrain d_2 to be 8 bits
    final d2 = lookupConfig.witnessShort(layouter, valueVal, 0, 8);

    // d_3 = z1_d from the SinsemillaHash(d) running sum output
    final d3 = RangeConstrained.bitrangeOf(valueVal, 8, 58);

    // Construct the SinsemillaMessagePiece
    final d = SinsemillaMessagePiece.fromSubpieces(
        chip: chip, layouter: layouter, subpieces: [d0, d1, d2.value(), d3]);

    return (d, d0, d1, d2);
  }

  AssignedCell<PallasNativeFp> assign(
    Layouter layouter,
    SinsemillaMessagePiece d,
    RangeConstrained<PallasNativeFp?> d0,
    RangeConstrained<AssignedCell<PallasNativeFp>> d1,
    RangeConstrained<AssignedCell<PallasNativeFp>> d2,
    AssignedCell<PallasNativeFp> z1D,
  ) {
    return layouter.assignRegion((region) {
      // Enable selector
      qNotecommitD.enable(region: region, offset: 0);

      // Copy d inner value
      d.cellValue.copyAdvice(region, colL, 0);

      // Assign d_0
      final d0Assigned = region.assignAdvice(colM, 0, () => d0.inner);

      // Copy d_1
      d1.inner.copyAdvice(region, colR, 0);

      // Copy d_2
      d2.inner.copyAdvice(region, colM, 1);

      // Copy z1_d as d_3
      z1D.copyAdvice(region, colR, 1);

      return d0Assigned;
    });
  }
}

class DecomposeE {
  final Selector qNotecommitE;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;

  const DecomposeE({
    required this.qNotecommitE,
    required this.colL,
    required this.colM,
    required this.colR,
  });

  factory DecomposeE.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    PallasNativeFp twoPow6,
  ) {
    final qNotecommitE = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitE);

      // e has been constrained to 10 bits by the Sinsemilla hash
      final e = meta.queryAdvice(colL, Rotation.cur());

      // e_0 has been constrained to 6 bits outside this gate
      final e0 = meta.queryAdvice(colM, Rotation.cur());

      // e_1 has been constrained to 4 bits outside this gate
      final e1 = meta.queryAdvice(colR, Rotation.cur());

      // e = e0 + 2^6 * e1
      final decompositionCheck = e - (e0 + e1 * twoPow6);

      return Constraints(selector: q, constraints: [decompositionCheck]);
    });

    return DecomposeE(
        qNotecommitE: qNotecommitE, colL: colL, colM: colM, colR: colR);
  }

  (
    SinsemillaMessagePiece,
    RangeConstrained<AssignedCell<PallasNativeFp>>,
    RangeConstrained<AssignedCell<PallasNativeFp>>,
  ) decompose(
    LookupRangeCheckConfig lookupConfig,
    SinsemillaConfig chip,
    Layouter layouter,
    AssignedCell<PallasNativeFp> value,
    AssignedCell<PallasNativeFp> rho,
  ) {
    final PallasNativeFp? valueVal = value.value;

    // Constrain e_0 to be 6 bits
    final e0 = lookupConfig.witnessShort(layouter, valueVal, 58, 64);

    // Constrain e_1 to be 4 bits
    final e1 = lookupConfig.witnessShort(layouter, rho.value, 0, 4);

    // Compose the NoteCommit piece
    final e = SinsemillaMessagePiece.fromSubpieces(
        chip: chip, layouter: layouter, subpieces: [e0.value(), e1.value()]);

    return (e, e0, e1);
  }

  void assign(
    Layouter layouter,
    SinsemillaMessagePiece e,
    RangeConstrained<AssignedCell<PallasNativeFp>> e0,
    RangeConstrained<AssignedCell<PallasNativeFp>> e1,
  ) {
    layouter.assignRegion(
      (region) {
        // Enable the selector at offset 0
        qNotecommitE.enable(region: region, offset: 0);

        // Copy the SinsemillaMessagePiece and its components into the advice columns
        e.cellValue.copyAdvice(region, colL, 0);
        e0.inner.copyAdvice(region, colM, 0);
        e1.inner.copyAdvice(region, colR, 0);
      },
    );
  }
}

class DecomposeG {
  final Selector qNotecommitG;
  final Column<Advice> colL;
  final Column<Advice> colM;

  const DecomposeG({
    required this.qNotecommitG,
    required this.colL,
    required this.colM,
  });

  factory DecomposeG.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    PallasNativeFp two,
    PallasNativeFp twoPow10,
  ) {
    final qNotecommitG = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitG);

      // g has been constrained to 250 bits by the Sinsemilla hash
      final g = meta.queryAdvice(colL, Rotation.cur());

      // This gate constrains g_0 to be boolean
      final g0 = meta.queryAdvice(colM, Rotation.cur());

      // g_1 has been constrained to 9 bits outside this gate
      final g1 = meta.queryAdvice(colL, Rotation.next());

      // g_2 is set to z1_g
      final g2 = meta.queryAdvice(colM, Rotation.next());

      // g = g0 + 2 * g1 + 2^10 * g2
      final decompositionCheck = g - (g0 + g1 * two + g2 * twoPow10);

      return Constraints(
          selector: q,
          constraints: [Halo2Utils.boolCheck(g0), decompositionCheck]);
    });

    return DecomposeG(
      qNotecommitG: qNotecommitG,
      colL: colL,
      colM: colM,
    );
  }
  (
    SinsemillaMessagePiece,
    RangeConstrained<PallasNativeFp?>,
    RangeConstrained<AssignedCell<PallasNativeFp>>,
  ) decompose(
    LookupRangeCheckConfig lookupConfig,
    SinsemillaConfig chip,
    Layouter layouter,
    AssignedCell<PallasNativeFp> rho,
    AssignedCell<PallasNativeFp> psi,
  ) {
    // g_0 will be boolean-constrained in the gate
    final g0 = RangeConstrained.bitrangeOf(rho.value, 254, 255);

    // Constrain g_1 to be 9 bits
    final g1 = lookupConfig.witnessShort(layouter, psi.value, 0, 9);

    // g_2 = z1_g from the SinsemillaHash(g) running sum output
    final g2 = RangeConstrained.bitrangeOf(psi.value, 9, 249);

    // Construct the SinsemillaMessagePiece g
    final g = SinsemillaMessagePiece.fromSubpieces(
        chip: chip, layouter: layouter, subpieces: [g0, g1.value(), g2]);

    return (g, g0, g1);
  }

  AssignedCell<PallasNativeFp> assign(
    Layouter layouter,
    SinsemillaMessagePiece g,
    RangeConstrained<PallasNativeFp?> g0,
    RangeConstrained<AssignedCell<PallasNativeFp>> g1,
    AssignedCell<PallasNativeFp> z1G,
  ) {
    return layouter.assignRegion(
      (region) {
        // Enable selector
        qNotecommitG.enable(region: region, offset: 0);

        // Copy g into advice column l at row 0
        g.cellValue.copyAdvice(region, colL, 0);

        // Assign g_0 into advice column m at row 0
        final AssignedCell<PallasNativeFp> assignedG0 =
            region.assignAdvice(colM, 0, () => g0.inner);

        // Copy g_1 into advice column l at row 1
        g1.inner.copyAdvice(region, colL, 1);

        // Copy z1_g as g_2 into advice column m at row 1
        z1G.copyAdvice(region, colM, 1);

        return assignedG0;
      },
    );
  }
}

class DecomposeH {
  final Selector qNotecommitH;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;

  const DecomposeH({
    required this.qNotecommitH,
    required this.colL,
    required this.colM,
    required this.colR,
  });

  factory DecomposeH.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    PallasNativeFp twoPow5,
  ) {
    final qNotecommitH = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitH);

      // h has been constrained to 10 bits by the Sinsemilla hash
      final h = meta.queryAdvice(colL, Rotation.cur());

      // h_0 has been constrained to be 5 bits outside this gate
      final h0 = meta.queryAdvice(colM, Rotation.cur());

      // This gate constrains h_1 to be boolean
      final h1 = meta.queryAdvice(colR, Rotation.cur());

      // h = h0 + 2^5 * h1
      final decompositionCheck = h - (h0 + h1 * twoPow5);

      return Constraints(
          selector: q,
          constraints: [Halo2Utils.boolCheck(h1), decompositionCheck]);
    });

    return DecomposeH(
      qNotecommitH: qNotecommitH,
      colL: colL,
      colM: colM,
      colR: colR,
    );
  }

  (
    SinsemillaMessagePiece,
    RangeConstrained<AssignedCell<PallasNativeFp>>,
    RangeConstrained<PallasNativeFp?>,
  ) decompose(
    LookupRangeCheckConfig lookupConfig,
    SinsemillaConfig chip,
    Layouter layouter,
    AssignedCell<PallasNativeFp> psi,
  ) {
    // Constrain h_0 to be 5 bits
    final h0 = lookupConfig.witnessShort(layouter, psi.value, 249, 254);

    // h_1 will be boolean-constrained in the gate
    final h1 = RangeConstrained.bitrangeOf(psi.value, 254, 255);

    // h_2 is 4 zero bits
    final h2 = RangeConstrained.bitrangeOf(PallasNativeFp.zero(), 0, 4);

    // Construct the SinsemillaMessagePiece h
    final h = SinsemillaMessagePiece.fromSubpieces(
        chip: chip, layouter: layouter, subpieces: [h0.value(), h1, h2]);

    return (h, h0, h1);
  }

  AssignedCell<PallasNativeFp> assign(
    Layouter layouter,
    SinsemillaMessagePiece h,
    RangeConstrained<AssignedCell<PallasNativeFp>> h0,
    RangeConstrained<PallasNativeFp?> h1,
  ) {
    return layouter.assignRegion((region) {
      // Enable the selector for this region
      qNotecommitH.enable(region: region, offset: 0);

      // Copy the inner value of h
      h.cellValue.copyAdvice(region, colL, 0);

      // Copy h_0
      h0.inner.copyAdvice(region, colM, 0);

      // Assign h_1
      final assignedH1 = region.assignAdvice(colR, 0, () => h1.inner);

      return assignedH1;
    });
  }
}

class GdCanonicity {
  final Selector qNotecommitGD;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;
  final Column<Advice> colZ;

  const GdCanonicity({
    required this.qNotecommitGD,
    required this.colL,
    required this.colM,
    required this.colR,
    required this.colZ,
  });

  factory GdCanonicity.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    Column<Advice> colZ,
    Expression twoPow130,
    PallasNativeFp twoPow250,
    PallasNativeFp twoPow254,
    Expression tP,
  ) {
    final qNotecommitGD = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitGD);

      final gdX = meta.queryAdvice(colL, Rotation.cur());

      // b_0 has been constrained to be 4 bits outside this gate
      final b0 = meta.queryAdvice(colM, Rotation.cur());
      // b_1 has been constrained to be boolean outside this gate
      final b1 = meta.queryAdvice(colM, Rotation.next());

      // a has been constrained to 250 bits by the Sinsemilla hash
      final a = meta.queryAdvice(colR, Rotation.cur());
      final aPrime = meta.queryAdvice(colR, Rotation.next());

      final z13A = meta.queryAdvice(colZ, Rotation.cur());
      final z13APrime = meta.queryAdvice(colZ, Rotation.next());

      // x(g_d) = a + (2^250)b_0 + (2^254)b_1
      final decompositionCheck = a + b0 * twoPow250 + b1 * twoPow254 - gdX;

      // a_prime = a + 2^130 - t_P
      final aPrimeCheck = a + twoPow130 - tP - aPrime;

      // The gd_x_canonicity_checks are enforced if and only if b1 = 1
      final canonicityChecks = [b1 * b0, b1 * z13A, b1 * z13APrime];

      return Constraints(
        selector: q,
        constraints: [
          decompositionCheck,
          aPrimeCheck,
          ...canonicityChecks,
        ],
      );
    });

    return GdCanonicity(
      qNotecommitGD: qNotecommitGD,
      colL: colL,
      colM: colM,
      colR: colR,
      colZ: colZ,
    );
  }
  void assign(
    Layouter layouter,
    EccPoint gD,
    SinsemillaMessagePiece a,
    RangeConstrained<AssignedCell<PallasNativeFp>> b0,
    AssignedCell<PallasNativeFp> b1,
    AssignedCell<PallasNativeFp> aPrime,
    AssignedCell<PallasNativeFp> z13A,
    AssignedCell<PallasNativeFp> z13APrime,
  ) {
    layouter.assignRegion((region) {
      // Copy g_d.x
      gD.getX().copyAdvice(region, colL, 0);

      // Copy b_0 and b_1
      b0.inner.copyAdvice(region, colM, 0);
      b1.copyAdvice(region, colM, 1);

      // Copy a and a_prime
      a.cellValue.copyAdvice(region, colR, 0);
      aPrime.copyAdvice(region, colR, 1);

      // Copy running sums z13_a and z13_a_prime
      z13A.copyAdvice(region, colZ, 0);
      z13APrime.copyAdvice(region, colZ, 1);

      // Enable the selector
      qNotecommitGD.enable(region: region, offset: 0);
    });
  }
}

class PkdCanonicity {
  final Selector qNotecommitPkD;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;
  final Column<Advice> colZ;

  const PkdCanonicity({
    required this.qNotecommitPkD,
    required this.colL,
    required this.colM,
    required this.colR,
    required this.colZ,
  });

  factory PkdCanonicity.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    Column<Advice> colZ,
    PallasNativeFp twoPow4,
    Expression twoPow140,
    PallasNativeFp twoPow254,
    Expression tP,
  ) {
    final qNotecommitPkD = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitPkD);

      final pkdX = meta.queryAdvice(colL, Rotation.cur());

      // b_3 has been constrained to 4 bits outside this gate
      final b3 = meta.queryAdvice(colM, Rotation.cur());
      // d_0 has been constrained to be boolean outside this gate
      final d0 = meta.queryAdvice(colM, Rotation.next());

      // c has been constrained to 250 bits by the Sinsemilla hash
      final c = meta.queryAdvice(colR, Rotation.cur());
      final b3CPrime = meta.queryAdvice(colR, Rotation.next());

      final z13C = meta.queryAdvice(colZ, Rotation.cur());
      final z14B3CPrime = meta.queryAdvice(colZ, Rotation.next());

      // x(pk_d) = b_3 + (2^4)c + (2^254)d_0
      final decompositionCheck = b3 + c * twoPow4 + d0 * twoPow254 - pkdX;

      // b3_c_prime = b_3 + (2^4)c + 2^140 - t_P
      final b3CPrimeCheck = b3 + (c * twoPow4) + twoPow140 - tP - b3CPrime;

      // Canonicity checks enforced if d_0 = 1
      final canonicityChecks = [d0 * z13C, d0 * z14B3CPrime];

      return Constraints(
        selector: q,
        constraints: [decompositionCheck, b3CPrimeCheck, ...canonicityChecks],
      );
    });

    return PkdCanonicity(
      qNotecommitPkD: qNotecommitPkD,
      colL: colL,
      colM: colM,
      colR: colR,
      colZ: colZ,
    );
  }

  void assign(
    Layouter layouter,
    EccPoint pkD,
    RangeConstrained<AssignedCell<PallasNativeFp>> b3,
    SinsemillaMessagePiece c,
    AssignedCell<PallasNativeFp> d0,
    AssignedCell<PallasNativeFp> b3CPrime,
    AssignedCell<PallasNativeFp> z13C,
    AssignedCell<PallasNativeFp> z14B3CPrime,
  ) {
    layouter.assignRegion((region) {
      // Copy pk_d.x
      pkD.getX().copyAdvice(region, colL, 0);

      // Copy b_3 and d_0
      b3.inner.copyAdvice(region, colM, 0);
      d0.copyAdvice(region, colM, 1);

      // Copy c and b3_c_prime
      c.cellValue.copyAdvice(region, colR, 0);
      b3CPrime.copyAdvice(region, colR, 1);

      // Copy running sums z13_c and z14_b3_c_prime
      z13C.copyAdvice(region, colZ, 0);
      z14B3CPrime.copyAdvice(region, colZ, 1);

      // Enable the selector
      qNotecommitPkD.enable(region: region, offset: 0);
    });
  }
}

class ValueCanonicity {
  final Selector qNotecommitValue;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;
  final Column<Advice> colZ;

  const ValueCanonicity({
    required this.qNotecommitValue,
    required this.colL,
    required this.colM,
    required this.colR,
    required this.colZ,
  });

  factory ValueCanonicity.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    Column<Advice> colZ,
    PallasNativeFp twoPow8,
    PallasNativeFp twoPow58,
  ) {
    final qNotecommitValue = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitValue);

      final value = meta.queryAdvice(colL, Rotation.cur());
      // d_2 has been constrained to 8 bits outside this gate
      final d2 = meta.queryAdvice(colM, Rotation.cur());
      // z1_d has been constrained to 50 bits by the Sinsemilla hash
      final z1D = meta.queryAdvice(colR, Rotation.cur());
      final d3 = z1D;
      // e_0 has been constrained to 6 bits outside this gate
      final e0 = meta.queryAdvice(colZ, Rotation.cur());

      // value = d_2 + (2^8)d_3 + (2^58)e_0
      final valueCheck = d2 + d3 * twoPow8 + e0 * twoPow58 - value;

      return Constraints(selector: q, constraints: [valueCheck]);
    });

    return ValueCanonicity(
      qNotecommitValue: qNotecommitValue,
      colL: colL,
      colM: colM,
      colR: colR,
      colZ: colZ,
    );
  }
  void assign(
    Layouter layouter,
    AssignedCell<PallasNativeFp> value,
    RangeConstrained<AssignedCell<PallasNativeFp>> d2,
    AssignedCell<PallasNativeFp> z1D,
    RangeConstrained<AssignedCell<PallasNativeFp>> e0,
  ) {
    layouter.assignRegion((region) {
      // Copy value
      value.copyAdvice(region, colL, 0);

      // Copy d_2
      d2.inner.copyAdvice(region, colM, 0);

      // Copy z1_d
      z1D.copyAdvice(region, colR, 0);

      // Copy e_0
      e0.inner.copyAdvice(region, colZ, 0);

      // Enable selector
      qNotecommitValue.enable(region: region, offset: 0);
    });
  }
}

class RhoCanonicity {
  final Selector qNotecommitRho;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;
  final Column<Advice> colZ;

  const RhoCanonicity({
    required this.qNotecommitRho,
    required this.colL,
    required this.colM,
    required this.colR,
    required this.colZ,
  });

  factory RhoCanonicity.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    Column<Advice> colZ,
    PallasNativeFp twoPow4,
    Expression twoPow140,
    PallasNativeFp twoPow254,
    Expression tP,
  ) {
    final qNotecommitRho = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitRho);

      final rho = meta.queryAdvice(colL, Rotation.cur());
      // e_1 has been constrained to 4 bits outside this gate
      final e1 = meta.queryAdvice(colM, Rotation.cur());
      final g0 = meta.queryAdvice(colM, Rotation.next());

      // f has been constrained to 250 bits by the Sinsemilla hash
      final f = meta.queryAdvice(colR, Rotation.cur());
      final e1FPrime = meta.queryAdvice(colR, Rotation.next());

      final z13F = meta.queryAdvice(colZ, Rotation.cur());
      final z14E1FPrime = meta.queryAdvice(colZ, Rotation.next());

      // rho = e_1 + (2^4) f + (2^254) g_0
      final decompositionCheck = e1 + f * twoPow4 + g0 * twoPow254 - rho;

      // e1_f_prime = e_1 + (2^4) f + 2^140 - t_P
      final e1FPrimeCheck = e1 + f * twoPow4 + twoPow140 - tP - e1FPrime;

      // The rho canonicity checks are enforced if and only if g_0 = 1
      final canonicityChecks = [g0 * z13F, g0 * z14E1FPrime];

      return Constraints(
        selector: q,
        constraints: [
          decompositionCheck,
          e1FPrimeCheck,
          ...canonicityChecks,
        ],
      );
    });

    return RhoCanonicity(
      qNotecommitRho: qNotecommitRho,
      colL: colL,
      colM: colM,
      colR: colR,
      colZ: colZ,
    );
  }

  void assign(
    Layouter layouter,
    AssignedCell<PallasNativeFp> rho,
    RangeConstrained<AssignedCell<PallasNativeFp>> e1,
    SinsemillaMessagePiece f,
    AssignedCell<PallasNativeFp> g0,
    AssignedCell<PallasNativeFp> e1FPrime,
    AssignedCell<PallasNativeFp> z13F,
    AssignedCell<PallasNativeFp> z14E1FPrime,
  ) {
    layouter.assignRegion((region) {
      // Copy rho
      rho.copyAdvice(region, colL, 0);

      // Copy e_1 and g_0
      e1.inner.copyAdvice(region, colM, 0);
      g0.copyAdvice(region, colM, 1);

      // Copy f and e1_f_prime
      f.cellValue.copyAdvice(region, colR, 0);
      e1FPrime.copyAdvice(region, colR, 1);

      // Copy running sums
      z13F.copyAdvice(region, colZ, 0);
      z14E1FPrime.copyAdvice(region, colZ, 1);

      // Enable selector
      qNotecommitRho.enable(region: region, offset: 0);
    });
  }
}

class PsiCanonicity {
  final Selector qNotecommitPsi;
  final Column<Advice> colL;
  final Column<Advice> colM;
  final Column<Advice> colR;
  final Column<Advice> colZ;

  const PsiCanonicity({
    required this.qNotecommitPsi,
    required this.colL,
    required this.colM,
    required this.colR,
    required this.colZ,
  });

  factory PsiCanonicity.configure(
    ConstraintSystem meta,
    Column<Advice> colL,
    Column<Advice> colM,
    Column<Advice> colR,
    Column<Advice> colZ,
    PallasNativeFp twoPow9,
    Expression twoPow130,
    PallasNativeFp twoPow249,
    PallasNativeFp twoPow254,
    Expression tP,
  ) {
    final qNotecommitPsi = meta.selector();

    meta.createGate((meta) {
      final q = meta.querySelector(qNotecommitPsi);

      // Query in the exact Rust order
      final psi = meta.queryAdvice(colL, Rotation.cur());
      final h0 = meta.queryAdvice(colL, Rotation.next());

      final g1 = meta.queryAdvice(colM, Rotation.cur());
      final h1 = meta.queryAdvice(colM, Rotation.next());

      final z1G = meta.queryAdvice(colR, Rotation.cur());
      final g2 = z1G;
      final g1G2Prime = meta.queryAdvice(colR, Rotation.next());

      final z13G = meta.queryAdvice(colZ, Rotation.cur());
      final z13G1G2Prime = meta.queryAdvice(colZ, Rotation.next());

      // psi = g_1 + (2^9) g_2 + (2^249) h_0 + (2^254) h_1
      final decompositionCheck =
          g1 + g2 * twoPow9 + h0 * twoPow249 + h1 * twoPow254 - psi;

      // g1_g2_prime = g_1 + (2^9) g_2 + 2^130 - t_P
      final g1G2PrimeCheck = g1 + g2 * twoPow9 + twoPow130 - tP - g1G2Prime;

      // psi_canonicity_checks enforced if h_1 = 1
      final canonicityChecks = [
        h1 * h0,
        h1 * z13G,
        h1 * z13G1G2Prime,
      ];

      return Constraints(
        selector: q,
        constraints: [
          decompositionCheck,
          g1G2PrimeCheck,
          ...canonicityChecks,
        ],
      );
    });

    return PsiCanonicity(
      qNotecommitPsi: qNotecommitPsi,
      colL: colL,
      colM: colM,
      colR: colR,
      colZ: colZ,
    );
  }

  void assign(
    Layouter layouter,
    AssignedCell<PallasNativeFp> psi,
    RangeConstrained<AssignedCell<PallasNativeFp>> g1,
    AssignedCell<PallasNativeFp> z1G,
    RangeConstrained<AssignedCell<PallasNativeFp>> h0,
    AssignedCell<PallasNativeFp> h1,
    AssignedCell<PallasNativeFp> g1G2Prime,
    AssignedCell<PallasNativeFp> z13G,
    AssignedCell<PallasNativeFp> z13G1G2Prime,
  ) {
    layouter.assignRegion((region) {
      // Copy psi and h_0
      psi.copyAdvice(region, colL, 0);
      h0.inner.copyAdvice(region, colL, 1);

      // Copy g_1 and h_1
      g1.inner.copyAdvice(region, colM, 0);
      h1.copyAdvice(region, colM, 1);

      // Copy g_2 and g1_g2_prime
      z1G.copyAdvice(region, colR, 0);
      g1G2Prime.copyAdvice(region, colR, 1);

      // Copy running sums
      z13G.copyAdvice(region, colZ, 0);
      z13G1G2Prime.copyAdvice(region, colZ, 1);

      // Enable selector
      qNotecommitPsi.enable(region: region, offset: 0);
    });
  }
}

class YCanonicity {
  final Selector qYCanon;
  final List<Column<Advice>> advices;

  YCanonicity._(this.qYCanon, this.advices);

  factory YCanonicity.configure(
    ConstraintSystem meta,
    List<Column<Advice>> advices,
    PallasNativeFp two,
    PallasNativeFp twoPow10,
    Expression twoPow130,
    PallasNativeFp twoPow250,
    PallasNativeFp twoPow254,
    Expression tP,
  ) {
    final qYCanon = meta.selector();

    meta.createGate((VirtualCells meta) {
      final qy = meta.querySelector(qYCanon);
      // Query all advice columns in the same order as Rust
      final y = meta.queryAdvice(advices[5], Rotation.cur());
      final lsb = meta.queryAdvice(advices[6], Rotation.cur());
      final k0 = meta.queryAdvice(advices[7], Rotation.cur());
      final k2 = meta.queryAdvice(advices[8], Rotation.cur());
      final k3 = meta.queryAdvice(advices[9], Rotation.cur());

      final j = meta.queryAdvice(advices[5], Rotation.next());
      final z1J = meta.queryAdvice(advices[6], Rotation.next());
      final z13J = meta.queryAdvice(advices[7], Rotation.next());

      final jPrime = meta.queryAdvice(advices[8], Rotation.next());
      final z13JPrime = meta.queryAdvice(advices[9], Rotation.next());

      // Decomposition checks
      final k1 = z1J;
      final jCheck = j - (lsb + k0 * two + k1 * twoPow10);
      final yCheck = y - (j + k2 * twoPow250 + k3 * twoPow254);
      final jPrimeCheck = j + twoPow130 - tP - jPrime;
      final k3Check = Halo2Utils.boolCheck(k3);

      final decompositionChecks = [k3Check, jCheck, yCheck, jPrimeCheck];

      // Canonicity checks (enforced only if k3 == 1)
      final canonicityChecks = [k3 * k2, k3 * z13J, k3 * z13JPrime];

      return Constraints(
          selector: qy,
          constraints: [...decompositionChecks, ...canonicityChecks]);
    });

    return YCanonicity._(qYCanon, advices);
  }
  RangeConstrained<AssignedCell<PallasNativeFp>> assign(
    Layouter layouter,
    AssignedCell<PallasNativeFp> y,
    RangeConstrained<PallasNativeFp?> lsb,
    RangeConstrained<AssignedCell<PallasNativeFp>> k0,
    RangeConstrained<AssignedCell<PallasNativeFp>> k2,
    RangeConstrained<PallasNativeFp?> k3,
    AssignedCell<PallasNativeFp> j,
    AssignedCell<PallasNativeFp> z1J,
    AssignedCell<PallasNativeFp> z13J,
    AssignedCell<PallasNativeFp> jPrime,
    AssignedCell<PallasNativeFp> z13JPrime,
  ) {
    return layouter.assignRegion((region) {
      qYCanon.enable(region: region, offset: 0);

      // Offset 0
      final offset0 = 0;

      // Copy y
      y.copyAdvice(region, advices[5], offset0);

      // Witness LSB
      final assignedLSB = region.assignAdvice(
        advices[6],
        offset0,
        () => lsb.inner,
      );
      final lsbAssigned = RangeConstrained(assignedLSB, lsb.numBits);

      // Witness k0
      k0.inner.copyAdvice(region, advices[7], offset0);

      // Copy k2
      k2.inner.copyAdvice(region, advices[8], offset0);

      // Witness k3
      region.assignAdvice(advices[9], offset0, () => k3.inner);

      // Offset 1
      final offset1 = 1;

      // Copy j
      j.copyAdvice(region, advices[5], offset1);
      z1J.copyAdvice(region, advices[6], offset1);
      z13J.copyAdvice(region, advices[7], offset1);
      jPrime.copyAdvice(region, advices[8], offset1);
      z13JPrime.copyAdvice(region, advices[9], offset1);

      return lsbAssigned;
    });
  }
}

class NoteCommitConfig {
  final DecomposeB b;
  final DecomposeD d;
  final DecomposeE e;
  final DecomposeG g;
  final DecomposeH h;
  final GdCanonicity gD;
  final PkdCanonicity pkD;
  final ValueCanonicity value;
  final RhoCanonicity rho;
  final PsiCanonicity psi;
  final YCanonicity yCanon;
  final List<Column<Advice>> advices;
  final SinsemillaConfig sinsemillaConfig;

  NoteCommitConfig({
    required this.b,
    required this.d,
    required this.e,
    required this.g,
    required this.h,
    required this.gD,
    required this.pkD,
    required this.value,
    required this.rho,
    required this.psi,
    required this.yCanon,
    required this.advices,
    required this.sinsemillaConfig,
  });

  factory NoteCommitConfig.configure(
    ConstraintSystem meta,
    List<Column<Advice>> advices,
    SinsemillaConfig sinsemillaConfig,
  ) {
    // Constants
    final two = PallasNativeFp.two();
    final twoPow2 = PallasNativeFp.from(1 << 2);
    final twoPow4 = twoPow2 * twoPow2;
    final twoPow5 = twoPow4 * two;
    final twoPow6 = twoPow5 * two;
    final twoPow8 = twoPow4 * twoPow4;
    final twoPow9 = twoPow8 * two;
    final twoPow10 = twoPow9 * two;
    final twoPow58 = PallasNativeFp(BigInt.one << 58);
    final twoPow130 =
        ExpressionConstant(PallasNativeFp(BigInt.one << 65).square());
    final twoPow140 =
        ExpressionConstant(PallasNativeFp(BigInt.one << 70).square());
    final twoPow249 = PallasNativeFp(BigInt.one << 124) *
        PallasNativeFp(BigInt.one << 124) *
        PallasNativeFp.two();
    final twoPow250 = twoPow249 * two;
    final twoPow254 =
        PallasNativeFp(BigInt.one << 127) * PallasNativeFp(BigInt.one << 127);

    final tP = ExpressionConstant(PallasNativeFp(Halo2Utils.tP));

    // Columns
    final colL = advices[6];
    final colM = advices[7];
    final colR = advices[8];
    final colZ = advices[9];

    final b =
        DecomposeB.configure(meta, colL, colM, colR, twoPow4, twoPow5, twoPow6);
    final d =
        DecomposeD.configure(meta, colL, colM, colR, two, twoPow2, twoPow10);
    final e = DecomposeE.configure(meta, colL, colM, colR, twoPow6);
    final g = DecomposeG.configure(meta, colL, colM, two, twoPow10);
    final h = DecomposeH.configure(meta, colL, colM, colR, twoPow5);

    final gD = GdCanonicity.configure(
        meta, colL, colM, colR, colZ, twoPow130, twoPow250, twoPow254, tP);
    final pkD = PkdCanonicity.configure(
        meta, colL, colM, colR, colZ, twoPow4, twoPow140, twoPow254, tP);
    final value = ValueCanonicity.configure(
        meta, colL, colM, colR, colZ, twoPow8, twoPow58);
    final rho = RhoCanonicity.configure(
        meta, colL, colM, colR, colZ, twoPow4, twoPow140, twoPow254, tP);
    final psi = PsiCanonicity.configure(meta, colL, colM, colR, colZ, twoPow9,
        twoPow130, twoPow249, twoPow254, tP);
    final yCanon = YCanonicity.configure(
        meta, advices, two, twoPow10, twoPow130, twoPow250, twoPow254, tP);

    return NoteCommitConfig(
      b: b,
      d: d,
      e: e,
      g: g,
      h: h,
      gD: gD,
      pkD: pkD,
      value: value,
      rho: rho,
      psi: psi,
      yCanon: yCanon,
      advices: advices,
      sinsemillaConfig: sinsemillaConfig,
    );
  }
}
