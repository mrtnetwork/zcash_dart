import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/exception/exception.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/orchard/builder/builder.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/configs/note_commit.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/ecc.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/constants/fixed_bases.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/gadget.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/sinsemilla/merkle.dart';

import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poseidon/poseidon.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/chip/lookup.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/configs/add.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/configs/commit_ivk.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/expression.dart';

class OrchardCircuitConfig {
  final Column<Instance> primary;
  final Selector qOrchard;
  final List<Column<Advice>> advices;
  final OrchardAddConfig addConfig;
  final EccConfig eccConfig;
  final Pow5Config poseidonConfig;
  final MerkleConfig merkleConfig1;
  final MerkleConfig merkleConfig2;
  final SinsemillaConfig sinsemillaConfig1;
  final SinsemillaConfig sinsemillaConfig2;
  final CommitIvkConfig commitIvkConfig;
  final NoteCommitConfig oldNoteCommitConfig;
  final NoteCommitConfig newNoteCommitConfig;
  final ZCashCryptoContext context;
  OrchardCircuitConfig({
    required this.primary,
    required this.qOrchard,
    required this.advices,
    required this.addConfig,
    required this.eccConfig,
    required this.poseidonConfig,
    required this.merkleConfig1,
    required this.merkleConfig2,
    required this.sinsemillaConfig1,
    required this.sinsemillaConfig2,
    required this.commitIvkConfig,
    required this.oldNoteCommitConfig,
    required this.newNoteCommitConfig,
    required this.context,
  });

  factory OrchardCircuitConfig.configure(
      ConstraintSystem meta, ZCashCryptoContext context) {
    // Advice columns
    final advices = List.generate(10, (_) => meta.adviceColumn());

    // Main Orchard gate
    final qOrchard = meta.selector();
    meta.createGate((meta) {
      final q = meta.querySelector(qOrchard);
      final vOld = meta.queryAdvice(advices[0], Rotation.cur());
      final vNew = meta.queryAdvice(advices[1], Rotation.cur());
      final magnitude = meta.queryAdvice(advices[2], Rotation.cur());
      final sign = meta.queryAdvice(advices[3], Rotation.cur());
      final root = meta.queryAdvice(advices[4], Rotation.cur());
      final anchor = meta.queryAdvice(advices[5], Rotation.cur());
      final enableSpends = meta.queryAdvice(advices[6], Rotation.cur());
      final enableOutputs = meta.queryAdvice(advices[7], Rotation.cur());
      final one = ExpressionConstant(PallasNativeFp.one());

      return Constraints(selector: q, constraints: [
        vOld - vNew - magnitude * sign,
        vOld * (root - anchor),
        vOld * (one - enableSpends),
        vNew * (one - enableOutputs),
      ]);
    });

    // AstAdd chip
    final addConfig = OrchardAddConfig.configure(
        meta: meta, a: advices[7], b: advices[8], c: advices[6]);

    // Lookup table columns
    final tableIdx = meta.lookupTableColumn();
    final lookup =
        (tableIdx, meta.lookupTableColumn(), meta.lookupTableColumn());

    // Instance column for public inputs
    final primary = meta.instanceColumn();
    meta.enableEquality(primary);

    // Enable equality for all advice columns
    for (final col in advices) {
      meta.enableEquality(col);
    }

    // Fixed columns for ECC and Poseidon
    final lagrangeCoeffs = List.generate(8, (_) => meta.fixedColumn());
    final rcA = lagrangeCoeffs.sublist(2, 5);
    final rcB = lagrangeCoeffs.sublist(5, 8);
    meta.enableConstant(lagrangeCoeffs[0]);

    // Range check
    final rangeCheck = LookupRangeCheckConfig.configure(
        meta, advices[9], tableIdx, HashDomainConst.K);

    // ECC configuration
    final eccConfig =
        EccConfig.configure(meta, advices, lagrangeCoeffs, rangeCheck);

    // Poseidon configuration
    final poseidonConfig = Pow5Config.configure(
        meta: meta,
        state: advices.sublist(6, 9),
        partialSbox: advices[5],
        rcA: rcA,
        rcB: rcB,
        spec: context.getPoseidonSpec());

    // Sinsemilla and Merkle configurations
    final sinsemillaConfig1 = SinsemillaConfig.configure(
        meta: meta,
        advices: advices.sublist(0, 5),
        witnessPieces: advices[6],
        fixedYQ: lagrangeCoeffs[0],
        lookup: lookup,
        rangeCheck: rangeCheck,
        allowInitFromPrivatePoint: false,
        context: context);
    final merkleConfig1 = MerkleConfig.configure(meta, sinsemillaConfig1);
    final sinsemillaConfig2 = SinsemillaConfig.configure(
        meta: meta,
        advices: advices.sublist(5, 10),
        witnessPieces: advices[7],
        fixedYQ: lagrangeCoeffs[1],
        lookup: lookup,
        rangeCheck: rangeCheck,
        allowInitFromPrivatePoint: false,
        context: context);
    final merkleConfig2 = MerkleConfig.configure(meta, sinsemillaConfig2);

    // CommitIvk chip
    final commitIvkConfig = CommitIvkConfig.configure(meta, advices);

    // NoteCommit chips
    final oldNoteCommitConfig =
        NoteCommitConfig.configure(meta, advices, sinsemillaConfig1);
    final newNoteCommitConfig =
        NoteCommitConfig.configure(meta, advices, sinsemillaConfig2);

    return OrchardCircuitConfig(
        primary: primary,
        qOrchard: qOrchard,
        advices: advices,
        addConfig: addConfig,
        eccConfig: eccConfig,
        poseidonConfig: poseidonConfig,
        merkleConfig1: merkleConfig1,
        merkleConfig2: merkleConfig2,
        sinsemillaConfig1: sinsemillaConfig1,
        sinsemillaConfig2: sinsemillaConfig2,
        commitIvkConfig: commitIvkConfig,
        oldNoteCommitConfig: oldNoteCommitConfig,
        newNoteCommitConfig: newNoteCommitConfig,
        context: context);
  }
}

class OrchardCircuit {
  final List<OrchardMerkleHash>? path;
  final int? pos;
  final PallasNativePoint? gdOld;
  final OrchardDiversifiedTransmissionKey? pkdOld;
  final ZAmount? vOld;
  final OrchardRho? rhoOld;
  final PallasNativeFp? psiOld;
  final OrchardNoteCommitTrapdoor? rcmOld;
  final OrchardNoteCommitment? cmOld;
  final VestaNativeFq? alpha;
  final OrchardSpendValidatingKey? ak;
  final OrchardNullifierDerivingKey? nk;
  final OrchardCommitIvkRandomness? rivk;
  final PallasNativePoint? gdNew;
  final OrchardDiversifiedTransmissionKey? pkdNew;
  final ZAmount? vNew;
  final PallasNativeFp? psiNew;
  final OrchardNoteCommitTrapdoor? rcmNew;
  final OrchardValueCommitTrapdoor? rcv;

  const OrchardCircuit(
      {this.path,
      this.pos,
      this.gdOld,
      this.pkdOld,
      this.vOld,
      this.rhoOld,
      this.psiOld,
      this.rcmOld,
      this.cmOld,
      this.alpha,
      this.ak,
      this.nk,
      this.rivk,
      this.gdNew,
      this.pkdNew,
      this.vNew,
      this.psiNew,
      this.rcmNew,
      this.rcv});

  factory OrchardCircuit.defaultConfig() {
    return OrchardCircuit();
  }

  factory OrchardCircuit.fromActionContext(
      {required OrchardFullViewingKey fvk,
      required OrchardNote spendNote,
      required OrchardMerklePath merklePath,
      required OrchardNoteCommitment noteCommit,
      required OrchardCommitIvkRandomness rivk,
      required OrchardNote outputNote,
      required VestaNativeFq alpha,
      required OrchardValueCommitTrapdoor rcv}) {
    final senderAddr = spendNote.recipient;
    final rhoOld = spendNote.rho;
    final psiOld = spendNote.psi();
    final rcm = spendNote.rcm();
    final psiNew = outputNote.psi();
    final rcmNew = outputNote.rcm();
    return OrchardCircuit(
        path: merklePath.authPath,
        pos: merklePath.position.position,
        gdOld: senderAddr.gD(),
        pkdOld: senderAddr.transmissionKey,
        vOld: spendNote.value,
        rhoOld: rhoOld,
        psiOld: psiOld,
        rcmOld: rcm,
        alpha: alpha,
        ak: fvk.ak,
        nk: fvk.nk,
        rivk: rivk,
        gdNew: outputNote.recipient.gD(),
        pkdNew: outputNote.recipient.transmissionKey,
        vNew: outputNote.value,
        psiNew: psiNew,
        rcmNew: rcmNew,
        rcv: rcv,
        cmOld: noteCommit);
  }

  AssignedCell<F> assignFreeAdvice<F>(
      Layouter layouter, Column<Advice> column, F? value) {
    return layouter.assignRegion((region) {
      return region.assignAdvice(column, 0, () => value);
    });
  }

  void synthesize(OrchardCircuitConfig config, Layouter layouter) {
    // Load the Sinsemilla generator table
    config.sinsemillaConfig1.load(layouter);

    // Construct the ECC chip
    final chip = config.eccConfig;

    // Witness private inputs
    final psiOld = assignFreeAdvice(layouter, config.advices[0], this.psiOld);

    final rhoOld =
        assignFreeAdvice(layouter, config.advices[0], this.rhoOld?.inner);
    // final chip = EccChip(eccChip);
    final cmOld = EccPointWithConfig(
        chip,
        chip.witnessPoint(
            layouter: layouter, value: this.cmOld?.inner.toAffine()));
    final gDOld = chip
        .witnessPointNonId(layouter: layouter, value: gdOld?.toAffine())
        .withConfig(chip);
    // NonIdentityPoint(chip, layouter, gdOld);

    final akP = chip
        .witnessPointNonId(layouter: layouter, value: ak?.key.point.toAffine())
        .withConfig(chip);
    final nk = assignFreeAdvice(layouter, config.advices[0], this.nk?.inner);

    final vOld = assignFreeAdvice(layouter, config.advices[0],
        this.vOld == null ? null : PallasNativeFp(this.vOld!.value));

    final vNew = assignFreeAdvice(layouter, config.advices[0],
        this.vNew == null ? null : PallasNativeFp(this.vNew!.value));
    // // Merkle path validity
    assert(path == null || path?.length == 32);
    final merkleInputs = HalOrchardMerklePath(
      chips: [config.merkleConfig1, config.merkleConfig2],
      q: config.context
          .getDomainPoint("z.cash:Orchard-MerkleCRH", withSeperator: false),
      leafPosition: pos,
      path: path?.map((e) => e.inner).toList(),
    );
    // cmOld.inner.e
    final leaf = cmOld.extractP();
    final root = merkleInputs.calculateRoot(layouter, leaf);
    // // v_net magnitude and sign
    ZAmount? vNet;
    if (this.vOld != null && this.vNew != null) {
      vNet = this.vOld! - this.vNew!;
    }

    (PallasNativeFp, PallasNativeFp)? magnitudeSign;
    if (vNet != null) {
      final magnitude = vNet.magnitudeSign();
      magnitudeSign = (
        PallasNativeFp(magnitude.value),
        switch (magnitude.isNegative) {
          false => PallasNativeFp.one(),
          true => -PallasNativeFp.one()
        }
      );
    }
    final magnitude = assignFreeAdvice(
      layouter,
      config.advices[9],
      magnitudeSign?.$1,
    );

    final sign = assignFreeAdvice(
      layouter,
      config.advices[9],
      magnitudeSign?.$2,
    );

    // final vNetMagnitudeSign = Tuple2(magnitude, sign);
    final vNetScalar = chip.scalarFixedFromSignedShort(
        layouter: layouter, magnitude: (magnitude, sign));
    // ScalarFixedShortWithEccChip(chip, layouter, (magnitude, sign));
    final rcv =
        chip.witnessScalarFixed(layouter: layouter, value: this.rcv?.inner);
    // ScalarFixedWithEccChip(chip, layouter, this.rcv?.scalarNative());
    final cvNet = OrchardGadget.valueCommitOrchard(
      layouter,
      chip,
      vNetScalar,
      rcv,
    );
    layouter.constrainInstance(cvNet.inner.x.cell, config.primary, 1);
    layouter.constrainInstance(cvNet.inner.y.cell, config.primary, 2);

    final nfOld = OrchardGadget.deriveNullifier(layouter, config.poseidonConfig,
        config.addConfig, chip, rhoOld, psiOld, cmOld, nk);
    layouter.constrainInstance(nfOld.cell, config.primary, 3);
    // // Spend authority
    final alpha =
        chip.witnessScalarFixed(layouter: layouter, value: this.alpha);
    final alphaCommitment = EccPointWithConfig(
        chip,
        chip
            .mulFixed(
                layouter: layouter,
                scalar: alpha,
                base: OrchardFixedBasesFull.spendAuthG)
            .$1);

    final rk = alphaCommitment.add(layouter, akP);

    layouter.constrainInstance(rk.inner.getX().cell, config.primary, 4);
    layouter.constrainInstance(rk.inner.getY().cell, config.primary, 5);
    // // Diversified address integrity
    final rivk =
        chip.witnessScalarFixed(layouter: layouter, value: this.rivk?.inner);
    // ScalarFixedWithEccChip(chip, layouter, this.rivk?.inner);
    final ivk_ = OrchardGadget.commitIvk(
        config.sinsemillaConfig1,
        chip,
        config.commitIvkConfig,
        layouter,
        akP.extractP(),
        nk,
        rivk,
        config.context);
    final ivk = chip.scalarVarFromBase(ivk_);
    //  ScalarVarWithEccChip.fromBase(chip, layouter, ivk_);
    final (derivedPkDOld, _) = gDOld.mul(layouter, ivk);
    final pkDOld = chip
        .witnessPointNonId(layouter: layouter, value: pkdOld?.point.toAffine())
        .withConfig(chip);
    // NonIdentityPoint(chip, layouter, pkdOld?.point);
    derivedPkDOld.constrainEqual(layouter, pkDOld);
    // // Old note commitment integrity
    final rcmOld =
        chip.witnessScalarFixed(layouter: layouter, value: this.rcmOld?.inner);
    // ScalarFixedWithEccChip(chip, layouter, this.rcmOld?.inner);
    final derivedCmOld = OrchardGadget.noteCommit(
        layouter,
        config.sinsemillaConfig1,
        chip,
        config.oldNoteCommitConfig,
        gDOld.inner,
        pkDOld.inner,
        vOld,
        rhoOld,
        psiOld,
        rcmOld,
        config.context);
    derivedCmOld.constrainEqual(layouter, cmOld);
    final gDNew = chip
        .witnessPointNonId(layouter: layouter, value: gdNew?.toAffine())
        .withConfig(chip);
    final pkDNew = chip
        .witnessPointNonId(layouter: layouter, value: pkdNew?.point.toAffine())
        .withConfig(chip);
    final rhoNew = nfOld;
    final psiNew = assignFreeAdvice(layouter, config.advices[0], this.psiNew);
    final rcmNew =
        chip.witnessScalarFixed(layouter: layouter, value: this.rcmNew?.inner);
    final cmNew = OrchardGadget.noteCommit(
        layouter,
        config.sinsemillaConfig2,
        chip,
        config.newNoteCommitConfig,
        gDNew.inner,
        pkDNew.inner,
        vNew,
        rhoNew,
        psiNew,
        rcmNew,
        config.context);

    final cmx = cmNew.extractP();
    layouter.constrainInstance(cmx.cell, config.primary, 6);
    layouter.assignRegion((region) {
      vOld.copyAdvice(region, config.advices[0], 0);
      vNew.copyAdvice(region, config.advices[1], 0);
      magnitude.copyAdvice(region, config.advices[2], 0);
      sign.copyAdvice(region, config.advices[3], 0);
      root.copyAdvice(region, config.advices[4], 0);

      region.assignAdviceFromInstance(config.primary, 0, config.advices[5], 0);
      region.assignAdviceFromInstance(config.primary, 7, config.advices[6], 0);
      region.assignAdviceFromInstance(config.primary, 8, config.advices[7], 0);

      config.qOrchard.enable(region: region, offset: 0);
    });
  }
}

class OrchardCircuitInstance {
  final OrchardAnchor anchor;
  final OrchardValueCommitment valueCommitment;
  final OrchardNullifier nullifier;
  final OrchardSpendVerificationKey rk;
  final OrchardExtractedNoteCommitment cmx;
  final bool enableSpend;
  final bool enableOutput;
  const OrchardCircuitInstance(
      {required this.anchor,
      required this.valueCommitment,
      required this.nullifier,
      required this.rk,
      required this.cmx,
      required this.enableSpend,
      required this.enableOutput});
  List<List<PallasNativeFp>> toHalo2() {
    return [instances()];
  }

  List<PallasNativeFp> instances() {
    final cvNet = valueCommitment.inner.toAffine();
    final rk = this.rk.toPoint();
    final instance = [
      anchor.inner,
      cvNet.isIdentity() ? PallasNativeFp.zero() : cvNet.x,
      cvNet.isIdentity() ? PallasNativeFp.zero() : cvNet.y,
      nullifier.inner,
      rk.x,
      rk.y,
      cmx.inner,
      PallasNativeFp.from(enableSpend.toInt),
      PallasNativeFp.from(enableOutput.toInt)
    ];
    return instance;
  }
}

class OrchardTransfableCircuit with LayoutSerializable {
  final OrchardFullViewingKey fvk;
  final OrchardCommitIvkRandomness rivk;
  final OrchardNote note;
  final OrchardNoteCommitment noteCommitment;
  final OrchardMerklePath merklePath;
  final OrchardNote outputNote;
  final VestaNativeFq alpha;
  final OrchardValueCommitTrapdoor rcv;

  OrchardCircuit toCircuit() {
    return OrchardCircuit.fromActionContext(
        fvk: fvk,
        merklePath: merklePath,
        noteCommit: noteCommitment,
        rivk: rivk,
        spendNote: note,
        outputNote: outputNote,
        alpha: alpha,
        rcv: rcv);
  }

  const OrchardTransfableCircuit(
      {required this.fvk,
      // required this.scope,
      required this.note,
      required this.noteCommitment,
      required this.merklePath,
      required this.outputNote,
      required this.alpha,
      required this.rcv,
      required this.rivk});
  factory OrchardTransfableCircuit.fromActionContext({
    required OrchardSpendInfo spend,
    required OrchardNote outputNote,
    required VestaNativeFq alpha,
    required OrchardValueCommitTrapdoor rcv,
    required ZCashCryptoContext context,
  }) {
    if (spend.note.nullifier(fvk: spend.fvk, context: context).inner !=
        outputNote.rho.inner) {
      throw OrchardException("Invalid spend full view key.");
    }
    final Bip44Changes scope = spend.getScope(context);
    return OrchardTransfableCircuit(
        fvk: spend.fvk,
        noteCommitment: spend.note.commitment(context),
        note: spend.note,
        merklePath: spend.merklePath,
        outputNote: outputNote,
        rivk: spend.fvk.rivkFromScope(scope),
        alpha: alpha,
        rcv: rcv);
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(96, property: "fvk"),
      LayoutConst.fixedBlobN(43, property: "recipient"),
      LayoutConst.u64(property: "value"),
      LayoutConst.fixedBlob32(property: "rho"),
      LayoutConst.fixedBlob32(property: "rseed"),
      LayoutConst.u32(property: "position"),
      LayoutConst.array(LayoutConst.fixedBlob32(), 32, property: "auth_path"),

      ///
      LayoutConst.fixedBlobN(43, property: "out_recipient"),
      LayoutConst.u64(property: "out_value"),
      LayoutConst.fixedBlob32(property: "out_rho"),
      LayoutConst.fixedBlob32(property: "out_rseed"),
      LayoutConst.fixedBlob32(property: "alpha"),
      LayoutConst.fixedBlob32(property: "rcv"),
      LayoutConst.array(LayoutConst.fixedBlob32(), 9, property: "instances"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson(
      {List<PallasNativeFp> instances = const []}) {
    if (instances.length != 9) {
      throw OrchardException("Missing orchard transfable instances.");
    }
    return {
      "fvk": fvk.toBytes(),
      "recipient": note.recipient.toBytes(),
      "value": note.value.value,
      "rho": note.rho.toBytes(),
      "rseed": note.rseed.inner,
      "position": merklePath.position.position,
      "auth_path": merklePath.authPath.map((e) => e.toBytes()).toList(),
      "out_recipient": outputNote.recipient.toBytes(),
      "out_value": outputNote.value.value,
      "out_rho": outputNote.rho.toBytes(),
      "out_rseed": outputNote.rseed.inner,
      "alpha": alpha.toBytes(),
      "rcv": rcv.toBytes(),
      "instances": instances.map((e) => e.toBytes()).toList()
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}
