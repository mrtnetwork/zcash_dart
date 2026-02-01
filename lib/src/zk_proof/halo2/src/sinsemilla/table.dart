import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/merkle.dart';

class GeneratorTableConfig {
  final TableColumn tableIdx;
  final TableColumn tableX;
  final TableColumn tableY;

  const GeneratorTableConfig({
    required this.tableIdx,
    required this.tableX,
    required this.tableY,
  });

  static void configure(ConstraintSystem meta, SinsemillaConfig config) {
    final tableIdx = config.generatorTable.tableIdx;
    final tableX = config.generatorTable.tableX;
    final tableY = config.generatorTable.tableY;

    // https://p.z.cash/halo2-0.1:sinsemilla-constraints?partial
    meta.lookup((meta) {
      final qS1 = meta.querySelector(config.qSinsemilla1);
      final qS2 = meta.queryFixed(config.qSinsemilla2);
      final qS3 = config.qS3(meta);
      final qRun = qS2 - qS3;

      // m_{i+1} = z_i - 2^K * q_run_i * z_{i+1}
      final word = () {
        final zCur = meta.queryAdvice(config.bits, Rotation.cur());
        final zNext = meta.queryAdvice(config.bits, Rotation.next());
        return zCur -
            (qRun * zNext * PallasNativeFp.from(1 << HashDomainConst.K));
      }();

      final xPCur = meta.queryAdvice(config.doubleAndAdd.xP, Rotation.cur());

      // y_p = (Y_A / 2) - lambda1 * (x_a - x_p)
      final yP = () {
        final lambda1 =
            meta.queryAdvice(config.doubleAndAdd.lambda1, Rotation.cur());
        final xA = meta.queryAdvice(config.doubleAndAdd.xA, Rotation.cur());
        final yA = config.doubleAndAdd.yA(meta, Rotation.cur());

        return (yA * PallasNativeFp.twoInv()) - (lambda1 * (xA - xPCur));
      }();

      // Default lookup values when q_s1 is disabled
      final initX = config.sinsemillaS[0].x;
      final initY = config.sinsemillaS[0].y;

      final notQS1 = ExpressionConstant(PallasNativeFp.one()) - qS1;

      // Table inputs
      final m = qS1 * word;
      final xP = qS1 * xPCur + notQS1 * initX;
      final yPFinal = qS1 * yP + notQS1 * initY;

      return [(m, tableIdx), (xP, tableX), (yPFinal, tableY)];
    });
  }

  void load(
      {required LookupRangeCheckConfig lookupConfig,
      required Layouter layouter,
      required List<PallasAffineNativePoint> sinsemillaS}) {
    lookupConfig.load(
        layouter: layouter, tableConfig: this, sinsemillaS: sinsemillaS);
  }
}
