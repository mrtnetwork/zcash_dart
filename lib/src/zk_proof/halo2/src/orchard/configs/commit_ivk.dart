import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/range_constrained.dart';

class CommitIvkConfig {
  final Selector qCommitIvk;
  final List<Column<Advice>> advices;

  const CommitIvkConfig({
    required this.qCommitIvk,
    required this.advices,
  });

  factory CommitIvkConfig.configure(
      ConstraintSystem meta, List<Column<Advice>> advices) {
    final qCommitIvk = meta.selector();
    final config = CommitIvkConfig(qCommitIvk: qCommitIvk, advices: advices);
    // CommitIvk canonicity check
    meta.createGate((meta) {
      final q = meta.querySelector(config.qCommitIvk);

      // Useful constants
      final twoPow4 = PallasNativeFp.from(1 << 4);
      final twoPow5 = PallasNativeFp.from(1 << 5);
      final twoPow9 = twoPow4 * twoPow5;
      final twoPow250 = PallasNativeFp(BigInt.one << 125).square();
      final twoPow254 = twoPow250 * twoPow4;

      final ak = meta.queryAdvice(config.advices[0], Rotation.cur());
      final nk = meta.queryAdvice(config.advices[0], Rotation.next());

      final a = meta.queryAdvice(config.advices[1], Rotation.cur());
      final bWhole = meta.queryAdvice(config.advices[2], Rotation.cur());
      final c = meta.queryAdvice(config.advices[1], Rotation.next());
      final dWhole = meta.queryAdvice(config.advices[2], Rotation.next());

      // b decomposition
      final b0 = meta.queryAdvice(config.advices[3], Rotation.cur());
      final b1 = meta.queryAdvice(config.advices[4], Rotation.cur());
      final b2 = meta.queryAdvice(config.advices[5], Rotation.cur());
      final bDecompositionCheck = bWhole - (b0 + b1 * twoPow4 + b2 * twoPow5);

      // d decomposition
      final d0 = meta.queryAdvice(config.advices[3], Rotation.next());
      final d1 = meta.queryAdvice(config.advices[4], Rotation.next());
      final dDecompositionCheck = dWhole - (d0 + d1 * twoPow9);

      // b1 and d1 are single-bit
      final b1BoolCheck = Halo2Utils.boolCheck(b1);
      final d1BoolCheck = Halo2Utils.boolCheck(d1);

      // ak = a || b0 || b1
      final akDecompositionCheck = a + b0 * twoPow250 + b1 * twoPow254 - ak;

      // nk = b2 || c || d0 || d1
      final twoPow245 = PallasNativeFp(BigInt.one << 49).pow(BigInt.from(5));
      final nkDecompositionCheck =
          b2 + c * twoPow5 + d0 * twoPow245 + d1 * twoPow254 - nk;

      // ak canonicity checks (only if b1 = 1)
      final z13A = meta.queryAdvice(config.advices[6], Rotation.cur());
      final aPrime = meta.queryAdvice(config.advices[7], Rotation.cur());
      final z13APrime = meta.queryAdvice(config.advices[8], Rotation.cur());
      final twoPow130 =
          ExpressionConstant(PallasNativeFp(BigInt.one << 65).square());
      final tP = ExpressionConstant(PallasNativeFp(Halo2Utils.tP));

      final b0CanonCheck = b1 * b0;
      final z13ACheck = b1 * z13A;
      final aPrimeCheck = a + twoPow130 - tP - aPrime;
      final z13APrimeCheck = b1 * z13APrime;

      // nk canonicity checks (only if d1 = 1)
      final z13C = meta.queryAdvice(config.advices[6], Rotation.next());
      final b2CPrime = meta.queryAdvice(config.advices[7], Rotation.next());
      final z14B2CPrime = meta.queryAdvice(config.advices[8], Rotation.next());
      final twoPow140 =
          ExpressionConstant(PallasNativeFp(BigInt.one << 70).square());
      final c0CanonCheck = d1 * d0;
      final z13CCheck = d1 * z13C;
      final b2CPrimeCheck = b2 + c * twoPow5 + twoPow140 - tP - b2CPrime;
      final z14B2CPrimeCheck = d1 * z14B2CPrime;

      return Constraints(selector: q, constraints: [
        b1BoolCheck,
        d1BoolCheck,
        bDecompositionCheck,
        dDecompositionCheck,
        akDecompositionCheck,
        nkDecompositionCheck,
        b0CanonCheck,
        z13ACheck,
        aPrimeCheck,
        z13APrimeCheck,
        c0CanonCheck,
        z13CCheck,
        b2CPrimeCheck,
        z14B2CPrimeCheck,
      ]);
    });

    return config;
  }
  void assignGate(
    Layouter layouter,
    GateCells gateCells,
  ) {
    layouter.assignRegion(
      (Region region) {
        // Enable selector on offset 0
        qCommitIvk.enable(region: region, offset: 0);
        {
          final offset = 0;
          gateCells.ak.copyAdvice(region, advices[0], offset);
          gateCells.a.copyAdvice(region, advices[1], offset);
          gateCells.b.copyAdvice(region, advices[2], offset);
          gateCells.b0.inner.copyAdvice(region, advices[3], offset);
          region.assignAdvice(advices[4], offset, () => gateCells.b1.inner);
          gateCells.b2.inner.copyAdvice(region, advices[5], offset);
          gateCells.z13A.copyAdvice(region, advices[6], offset);
          gateCells.aPrime.copyAdvice(region, advices[7], offset);
          gateCells.z13APrime.copyAdvice(region, advices[8], offset);
        }
        {
          final offset = 1;
          gateCells.nk.copyAdvice(region, advices[0], offset);
          gateCells.c.copyAdvice(region, advices[1], offset);
          gateCells.d.copyAdvice(region, advices[2], offset);
          gateCells.d0.inner.copyAdvice(region, advices[3], offset);
          region.assignAdvice(advices[4], offset, () => gateCells.d1.inner);
          gateCells.z13C.copyAdvice(region, advices[6], offset);
          gateCells.b2CPrime.copyAdvice(region, advices[7], offset);
          gateCells.z14B2CPrime.copyAdvice(region, advices[8], offset);
        }
      },
    );
  }
}

class GateCells {
  final AssignedCell<PallasNativeFp> a;
  final AssignedCell<PallasNativeFp> b;
  final AssignedCell<PallasNativeFp> c;
  final AssignedCell<PallasNativeFp> d;
  final AssignedCell<PallasNativeFp> ak;
  final AssignedCell<PallasNativeFp> nk;
  final RangeConstrained<AssignedCell<PallasNativeFp>> b0;
  final RangeConstrained<PallasNativeFp?> b1;
  final RangeConstrained<AssignedCell<PallasNativeFp>> b2;
  final RangeConstrained<AssignedCell<PallasNativeFp>> d0;
  final RangeConstrained<PallasNativeFp?> d1;
  final AssignedCell<PallasNativeFp> z13A;
  final AssignedCell<PallasNativeFp> aPrime;
  final AssignedCell<PallasNativeFp> z13APrime;
  final AssignedCell<PallasNativeFp> z13C;
  final AssignedCell<PallasNativeFp> b2CPrime;
  final AssignedCell<PallasNativeFp> z14B2CPrime;

  const GateCells({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.ak,
    required this.nk,
    required this.b0,
    required this.b1,
    required this.b2,
    required this.d0,
    required this.d1,
    required this.z13A,
    required this.aPrime,
    required this.z13APrime,
    required this.z13C,
    required this.b2CPrime,
    required this.z14B2CPrime,
  });
}
