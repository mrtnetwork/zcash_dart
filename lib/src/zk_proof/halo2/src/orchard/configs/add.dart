import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

class OrchardAddConfig {
  final Column<Advice> a;
  final Column<Advice> b;
  final Column<Advice> c;
  final Selector qAdd;
  const OrchardAddConfig(
      {required this.a, required this.b, required this.c, required this.qAdd});
  factory OrchardAddConfig.configure({
    required Column<Advice> a,
    required Column<Advice> b,
    required Column<Advice> c,
    required ConstraintSystem meta,
  }) {
    final qAdd = meta.selector();
    meta.createGate(
      (meta) {
        final expQ = meta.querySelector(qAdd);
        final expA = meta.queryAdvice(a, Rotation.cur());
        final expB = meta.queryAdvice(b, Rotation.cur());
        final expC = meta.queryAdvice(c, Rotation.cur());
        return Constraints(selector: expQ, constraints: [expA + expB - expC]);
      },
    );
    return OrchardAddConfig(a: a, b: b, c: c, qAdd: qAdd);
  }

  AssignedCell<PallasNativeFp> add(Layouter layouter,
      AssignedCell<PallasNativeFp> a, AssignedCell<PallasNativeFp> b) {
    return layouter.assignRegion(
      (region) {
        qAdd.enable(region: region, offset: 0);
        a.copyAdvice(region, this.a, 0);
        b.copyAdvice(region, this.b, 0);
        PallasNativeFp? scalar;
        if (a.hasValue && b.hasValue) {
          scalar = a.getValue() + b.getValue();
        }
        return region.assignAdvice(c, 0, () => scalar);
      },
    );
  }
}
