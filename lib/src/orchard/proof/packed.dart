import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/proof/types.dart';

/// Packed field-level circuit inputs for the new proving backend
/// (`blockchainUtils.api.orchard`, Rust `orchard_halo2::bridge`).
///
/// One action (1716 B, all little-endian canonical encodings):
/// path[32][32] | pos u32 | gd_old[64] | pkd_old[64] | v_old u64 |
/// rho_old[32] | psi_old[32] | rcm_old[32] | cm_old[64] | alpha[32] |
/// ak[64] | nk[32] | rivk[32] | gd_new[64] | pkd_new[64] | v_new u64 |
/// psi_new[32] | rcm_new[32] | rcv[32].
/// Points are `x || y` (32 bytes each); scalars/fields 32 bytes LE.
///
/// Instances travel separately: 10 x 32 LE limbs per action
/// (`OrchardCircuitInstance.instances`). No wallet parsing happens in Rust.
abstract final class OrchardPackedCircuit {
  static List<int> _b(List<int> b, int len, String name) {
    if (b.length != len) {
      throw BuError(
        DefaultErrorType.invalidLength,
        "Invalid $name length ${b.length}, want $len.",
      );
    }
    return b;
  }

  static List<int> _ptAffine(
    List<int> out, {
    required List<int> x32,
    required List<int> y32,
    required String name,
  }) {
    out.addAll(_b(x32, 32, '$name.x'));
    out.addAll(_b(y32, 32, '$name.y'));
    return out;
  }

  /// Pack one action's circuit witness + append its 10 instance limbs.
  static List<int> packAction(
    OrchardProofInputs inputs, {
    required List<int> instancesOut,
  }) {
    final c = inputs.circuit;
    if (c.merklePath.authPath.length != 32) {
      throw BuError(
        DefaultErrorType.invalidLength,
        "Invalid auth path length ${c.merklePath.authPath.length}, want 32.",
      );
    }
    final inst = inputs.instance.instances();
    if (inst.length != 10) {
      throw BuError(
        DefaultErrorType.invalidLength,
        "Invalid instance count ${inst.length}, want 10.",
      );
    }
    final out = <int>[];
    for (final e in c.merklePath.authPath) {
      out.addAll(_b(e.inner.toBytes(), 32, 'path'));
    }
    out.addAll(c.merklePath.position.position.toU32LeBytes());
    final gdOld = PallasAffinePoint.fromBytes(c.note.recipient.gD());
    _ptAffine(
      out,
      x32: gdOld.x.toBytes(),
      y32: gdOld.y.toBytes(),
      name: 'gdOld',
    );
    final pkdOld = PallasAffinePoint.fromBytes(
      c.note.recipient.transmissionKey.inner,
    );
    _ptAffine(
      out,
      x32: pkdOld.x.toBytes(),
      y32: pkdOld.y.toBytes(),
      name: 'pkdOld',
    );
    out.addAll(c.note.value.value.toU64LeBytes());
    out.addAll(_b(c.note.rho.toBytes(), 32, 'rhoOld'));
    out.addAll(_b(c.note.psi(), 32, 'psiOld'));
    out.addAll(_b(c.note.rcm().toBytes(), 32, 'rcmOld'));
    final cmOld = PallasPoint.fromBytes(c.noteCommitment.toBytes()).toAffine();
    _ptAffine(
      out,
      x32: cmOld.x.toBytes(),
      y32: cmOld.y.toBytes(),
      name: 'cmOld',
    );
    out.addAll(_b(c.alpha, 32, 'alpha'));
    final ak = PallasAffinePoint.fromBytes(c.fvk.ak.key.keyBytes);
    _ptAffine(out, x32: ak.x.toBytes(), y32: ak.y.toBytes(), name: 'ak');
    out.addAll(_b(c.fvk.nk.toBytes(), 32, 'nk'));
    out.addAll(_b(c.rivk.toBytes(), 32, 'rivk'));
    final gdNew = PallasAffinePoint.fromBytes(c.outputNote.recipient.gD());
    _ptAffine(
      out,
      x32: gdNew.x.toBytes(),
      y32: gdNew.y.toBytes(),
      name: 'gdNew',
    );
    final pkdNew = PallasAffinePoint.fromBytes(
      c.outputNote.recipient.transmissionKey.inner,
    );
    _ptAffine(
      out,
      x32: pkdNew.x.toBytes(),
      y32: pkdNew.y.toBytes(),
      name: 'pkdNew',
    );
    out.addAll(c.outputNote.value.value.toU64LeBytes());
    out.addAll(_b(c.outputNote.psi(), 32, 'psiNew'));
    out.addAll(_b(c.outputNote.rcm().toBytes(), 32, 'rcmNew'));
    out.addAll(_b(c.rcv.toBytes(), 32, 'rcv'));
    for (final e in inst) {
      instancesOut.addAll(_b(e, 32, 'instance'));
    }
    assert(out.length == 1716, 'packed action must be 1716 bytes');
    return out;
  }

  /// Pack N actions: concatenated 1716-byte circuits + concatenated instances.
  static ({List<int> inputs, List<int> instances}) packActions(
    List<OrchardProofInputs> args,
  ) {
    final inputs = <int>[];
    final instances = <int>[];
    for (final a in args) {
      inputs.addAll(packAction(a, instancesOut: instances));
    }
    return (inputs: inputs, instances: instances);
  }
}
