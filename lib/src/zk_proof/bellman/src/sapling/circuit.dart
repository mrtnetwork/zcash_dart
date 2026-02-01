import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/variable.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/blake2s.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/boolean.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/multipack.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/num.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/constants.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/ecc.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/pedersen_hash.dart';
import 'package:zcash_dart/src/pedersen_hash/src/hash.dart';

class ValueCommitmentOpening {
  final ZAmount value;
  final JubJubNativeFr randomness;
  const ValueCommitmentOpening(this.value, this.randomness);

  JubJubNativePoint commitment() {
    return SaplingUtils.valueCommitmentValueGeneratorNative *
            JubJubNativeFr(value.value) +
        (SaplingUtils.valueCommitmentRandomnessGeneratorNative * randomness);
  }
}

class SaplingSpend with BellmanCircuit, LayoutSerializable {
  final ValueCommitmentOpening valueCommitmentOpening;
  final SaplingProofGenerationKey proofGenerationKey;
  final SaplingPaymentAddress paymentAddress;
  final JubJubNativeFr commitmentRandomness;
  final JubJubNativeFr ar;
  final List<(JubJubNativeFq, bool)> authPath;
  final SaplingAnchor anchor;
  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "value": valueCommitmentOpening.value.value,
      "randomness": valueCommitmentOpening.randomness.toBytes(),
      "ak": proofGenerationKey.ak.toBytes(),
      "nsk": proofGenerationKey.nsk.toBytes(),
      "payment_address_diversify_hash": paymentAddress.gd().toBytes(),
      "commitment_randomness": commitmentRandomness.toBytes(),
      "ar": ar.toBytes(),
      "auth_path": authPath.map((e) => e.$1.toBytes()).toList(),
      "auth_path_pos": authPath.map((e) => e.$2).toList(),
      "anchor": anchor.toBytes()
    };
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.u64(property: "value"),
      LayoutConst.fixedBlob32(property: "randomness"),
      LayoutConst.fixedBlob32(property: "ak"),
      LayoutConst.fixedBlob32(property: "nsk"),
      LayoutConst.fixedBlobN(32, property: "payment_address_diversify_hash"),
      LayoutConst.fixedBlob32(property: "commitment_randomness"),
      LayoutConst.fixedBlob32(property: "ar"),
      LayoutConst.array(LayoutConst.fixedBlob32(), 32, property: "auth_path"),
      LayoutConst.array(LayoutConst.boolean(), 32, property: "auth_path_pos"),
      LayoutConst.fixedBlob32(property: "anchor"),
    ], property: property);
  }

  const SaplingSpend({
    required this.valueCommitmentOpening,
    required this.proofGenerationKey,
    required this.paymentAddress,
    required this.commitmentRandomness,
    required this.ar,
    required this.authPath,
    required this.anchor,
  });
  factory SaplingSpend.build(
      {required SaplingProofGenerationKey proofGenerationKey,
      required Diversifier diversifier,
      required SaplingRSeed rseed,
      required ZAmount value,
      required JubJubNativeFr alpha,
      required SaplingValueCommitTrapdoor rcv,
      required SaplingAnchor anchor,
      required SaplingMerklePath merklePath}) {
    final vco = ValueCommitmentOpening(value, rcv.value);
    final viewingKey = proofGenerationKey.toViewingKey();
    final paymentAddress = viewingKey.ivk().toPaymentAddress(diversifier);
    final note =
        SaplingNote(recipient: paymentAddress, value: value, rseed: rseed);
    final position = merklePath.position;
    return SaplingSpend(
        valueCommitmentOpening: vco,
        proofGenerationKey: proofGenerationKey,
        paymentAddress: paymentAddress,
        commitmentRandomness: note.rseed.rcm().inner,
        ar: alpha,
        authPath: merklePath.authPath.indexed
            .map((e) => (e.$2.inner, (position.position >> e.$1) & 0x01 == 1))
            .toList(),
        anchor: anchor);
  }

  /// Exposes a Pedersen commitment to the value as an
  /// input to the circuit
  static List<GBoolean> exposeValueCommitment(
    BellmanConstraintSystem cs,
    ValueCommitmentOpening? valueCommitmentOpening,
  ) {
    // Booleanize the value into little-endian bit order
    final valueBits =
        GBooleanUtils.u64ToBits(cs, valueCommitmentOpening?.value.value);

    // Compute the note value in the exponent
    final value = GEdwardsUtils.fixedBaseMultiplication(
        cs, SaplingCircuitConstants.valueCommitmentValueGenerator(), valueBits);

    // Booleanize the randomness. This does not ensure
    // the bit representation is "in the field" because
    // it doesn't matter for security.
    final rcvBits = GBooleanUtils.frToBits(
      cs,
      valueCommitmentOpening?.randomness,
    );

    // Compute the randomness in the exponent
    final rcv = GEdwardsUtils.fixedBaseMultiplication(
      cs,
      SaplingCircuitConstants.valueCommitmentRandomnessGenerator(),
      rcvBits,
    );

    // Compute the Pedersen commitment to the value
    final cv = value.add(cs, rcv);

    // Expose the commitment as an input to the circuit
    cv.inputize(cs);

    return valueBits;
  }

  @override
  void synthesize(BellmanConstraintSystem cs) {
    // Witness ak
    final ak = GEdwardsPoint.witness(cs, proofGenerationKey.ak.point);

    // Small-order check
    ak.assertNotSmallOrder(cs);

    // Rerandomize ak and expose rk
    {
      final arBits = GBooleanUtils.frToBits(cs, ar);

      final arPoint = GEdwardsUtils.fixedBaseMultiplication(
          cs, SaplingCircuitConstants.spendingKeyGenerator(), arBits);

      final rk = ak.add(cs, arPoint);

      rk.inputize(cs);
    }

    // Compute nk = [nsk] ProofGenerationKey
    late final GEdwardsPoint nk;
    {
      final nskBits = GBooleanUtils.frToBits(cs, proofGenerationKey.nsk);

      nk = GEdwardsUtils.fixedBaseMultiplication(
          cs, SaplingCircuitConstants.proofGeneratorKeyGenerator(), nskBits);
    }

    // ivk and nf preimages
    final List<GBoolean> ivkPreimage = [];
    final List<GBoolean> nfPreimage = [];

    // ak representation
    ivkPreimage.addAll(ak.repr(cs));

    // nk representation
    {
      final reprNk = nk.repr(cs);
      ivkPreimage.addAll(reprNk);
      nfPreimage.addAll(reprNk);
    }

    assert(ivkPreimage.length == 512);
    assert(nfPreimage.length == 256);

    var ivk = GBlake2sUtils.blake2s(cs, ivkPreimage, "Zcashivk".codeUnits);
    ivk = ivk.sublist(0, JubJubFrConst.capacity);

    // Witness g_d
    final gD = GEdwardsPoint.witness(cs, paymentAddress.gd());

    gD.assertNotSmallOrder(cs);

    // pk_d = g_d^ivk
    final pkD = gD.mul(cs, ivk);

    // Note contents
    final List<GBoolean> noteContents = [];

    // Value
    var valueNum = GNum.zero();
    {
      final valueBits = exposeValueCommitment(cs, valueCommitmentOpening);

      var coeff = JubJubNativeFq.one();
      for (final bit in valueBits) {
        valueNum =
            valueNum.addBoolWithCoeff(GVariable(GIndexInput(0)), bit, coeff);
        coeff = coeff.double();
      }

      noteContents.addAll(valueBits);
    }

    // g_d
    noteContents.addAll(gD.repr(cs));

    // pk_d
    noteContents.addAll(pkD.repr(cs));

    assert(noteContents.length == 64 + 256 + 256);

    // Pedersen hash of note
    var cm = GPedersenHashUtils.pedersenHash(
        cs, PersonalizationNoteCommitment(), noteContents);

    // Randomize cm
    {
      final rcmBits = GBooleanUtils.frToBits(cs, commitmentRandomness);

      final rcm = GEdwardsUtils.fixedBaseMultiplication(cs,
          SaplingCircuitConstants.noteCommitmentRandomnessGenerator(), rcmBits);

      cm = cm.add(cs, rcm);
    }

    // LeafPosition bits
    final List<GBoolean> positionBits = [];

    // Current subtree value
    var cur = cm.u;

    // Merkle path
    for (var i = 0; i < authPath.length; i++) {
      final e = authPath[i];
      // final subCs = cs.namespace(() => 'merkle tree hash $i');

      final curIsRight = GBooleanIs(
        GAllocatedBit.alloc(cs: cs, value: e.$2),
      );

      positionBits.add(curIsRight);

      final pathElement = GAllocatedNum.alloc(cs, () => e.$1);

      final (ul, ur) =
          GAllocatedNum.conditionallyReverse(cs, cur, pathElement, curIsRight);

      final List<GBoolean> preimage = [];
      preimage.addAll(ul.toBitsLe(cs));
      preimage.addAll(ur.toBitsLe(cs));

      cur = GPedersenHashUtils.pedersenHash(
              cs, PersonalizationMerkleTree(i), preimage)
          .u;
    }

    // Anchor enforcement
    {
      final rt = GAllocatedNum.alloc(cs, () => anchor.inner);

      cs.enforce(
        (lc) => lc + cur.variable - rt.variable,
        (lc) => lc + valueNum.lcMul(JubJubNativeFq.one()),
        (lc) => lc,
      );

      rt.inputize(cs);
    }

    // Faerie gold prevention
    var rho = cm;
    {
      final position = GEdwardsUtils.fixedBaseMultiplication(
        cs,
        SaplingCircuitConstants.nullifierPositionGenerator(),
        positionBits,
      );

      rho = rho.add(cs, position);
    }

    // nf = BLAKE2s(nk || rho)
    nfPreimage.addAll(rho.repr(cs));

    assert(nfPreimage.length == 512);

    final nf = GBlake2sUtils.blake2s(cs, nfPreimage, "Zcash_nf".codeUnits);

    GMultipackUtils.packIntoInputs(cs, nf);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}

class SaplingOutput with BellmanCircuit, LayoutSerializable {
  final ValueCommitmentOpening valueCommitmentOpening;
  final SaplingPaymentAddress paymentAddress;
  final SaplingNoteCommitTrapdoor commitmentRandomness;
  final JubJubNativeFr esk;
  const SaplingOutput(
      {required this.valueCommitmentOpening,
      required this.paymentAddress,
      required this.commitmentRandomness,
      required this.esk});
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.u64(property: "value"),
      LayoutConst.fixedBlob32(property: "randomness"),
      LayoutConst.fixedBlob32(property: "recipient_address_diversify_hash"),
      LayoutConst.fixedBlob32(property: "recipient_address_pk_d"),
      LayoutConst.fixedBlob32(property: "commitment_randomness"),
      LayoutConst.fixedBlob32(property: "esk"),
    ], property: property);
  }

  factory SaplingOutput.build(
      {required JubJubNativeFr esk,
      required SaplingPaymentAddress paymentAddress,
      required SaplingNoteCommitTrapdoor rcm,
      required ZAmount value,
      required SaplingValueCommitTrapdoor rcv}) {
    final vco = ValueCommitmentOpening(value, rcv.value);
    return SaplingOutput(
        valueCommitmentOpening: vco,
        commitmentRandomness: rcm,
        esk: esk,
        paymentAddress: paymentAddress);
  }

  @override
  void synthesize(BellmanConstraintSystem cs) {
    // Let's start to construct our note, which contains
    // value (big endian)
    final List<GBoolean> noteContents = [];

    // Expose the value commitment and place the value
    // in the note.
    noteContents.addAll(
      SaplingSpend.exposeValueCommitment(cs, valueCommitmentOpening),
    );

    // Let's deal with g_d
    {
      // Prover witnesses g_d, ensuring it's on the curve.
      final gD = GEdwardsPoint.witness(
          cs, paymentAddress.gd() // checked at construction
          );

      // Ensure g_d is not small order
      gD.assertNotSmallOrder(cs);

      // Extend note contents with representation of g_d
      noteContents.addAll(gD.repr(cs));

      // Booleanize ephemeral secret key
      final eskBits = GBooleanUtils.frToBits(cs, esk);

      // Compute ephemeral public key epk = g_d^esk
      final epk = gD.mul(cs, eskBits);

      // Expose epk publicly
      epk.inputize(cs);
    }

    // Now let's deal with pk_d
    {
      // Witness pk_d (no checks)
      final pkD = paymentAddress.transmissionKey.inner.toAffine();

      // Witness v-coordinate bits (little endian)
      final vContents = GBooleanUtils.fqToBits(cs, pkD.v);

      // Witness sign bit of u
      final signBit =
          GBooleanIs(GAllocatedBit.alloc(cs: cs, value: pkD.u.isOdd()));

      // Extend note contents with pk_d representation
      noteContents.addAll(vContents);
      noteContents.add(signBit);
    }

    assert(noteContents.length == 64 + 256 + 256);

    // Compute the hash of the note contents
    var cm = GPedersenHashUtils.pedersenHash(
        cs, PersonalizationNoteCommitment(), noteContents);

    {
      // Booleanize the randomness
      final rcmBits = GBooleanUtils.frToBits(cs, commitmentRandomness.inner);

      // Compute the note commitment randomness in the exponent
      final rcm = GEdwardsUtils.fixedBaseMultiplication(cs,
          SaplingCircuitConstants.noteCommitmentRandomnessGenerator(), rcmBits);

      // Randomize our note commitment
      cm = cm.add(cs, rcm);
    }

    // Expose only the u-coordinate
    cm.u.inputize(cs);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "value": valueCommitmentOpening.value.value,
      "randomness": valueCommitmentOpening.randomness.toBytes(),
      "recipient_address_diversify_hash": paymentAddress.gd().toBytes(),
      "recipient_address_pk_d": paymentAddress.transmissionKey.toBytes(),
      "commitment_randomness": commitmentRandomness.toBytes(),
      "esk": esk.toBytes()
    };
  }
}
