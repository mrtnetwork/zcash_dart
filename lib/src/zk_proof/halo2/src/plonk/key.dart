import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/floor_planner/v1.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/circuit.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/permutation.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/constraint.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/domain.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/params.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/transcript/transcript.dart';

import 'assignment.dart';

class PlonkVerifyingKey with Equality, ProtobufEncodableMessage {
  final EvaluationDomain domain;
  final List<VestaAffineNativePoint> fixedCommitments;
  final PermutationVerifyingKey permutation;
  final ConstraintSystem cs;
  final int csDegree;
  final PallasNativeFp transcriptRepr;

  PlonkVerifyingKey clone() => PlonkVerifyingKey(
      domain: domain,
      fixedCommitments: fixedCommitments,
      permutation: permutation,
      cs: cs.clone(),
      csDegree: csDegree,
      transcriptRepr: transcriptRepr);
  const PlonkVerifyingKey(
      {required this.domain,
      required this.fixedCommitments,
      required this.permutation,
      required this.cs,
      required this.csDegree,
      required this.transcriptRepr});
  factory PlonkVerifyingKey.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    final vk = PlonkVerifyingKey(
        domain: EvaluationDomain.deserialize(decode.getBytes(1)),
        fixedCommitments: decode
            .getListOfBytes(2)
            .map((e) => VestaAffineNativePoint.fromBytes(e))
            .toList(),
        permutation: PermutationVerifyingKey.deserialize(decode.getBytes(3)),
        cs: ConstraintSystem.deserialize(decode.getBytes(4)),
        csDegree: decode.getInt(5),
        transcriptRepr: PallasNativeFp.fromBytes(decode.getBytes(6)));
    final k = vk.toDebugString();
    final r = QuickCrypto.blake2b512Hash(
      k.length.toBigInt.toU64LeBytes(),
      extraBlocks: [StringUtils.encode(k)],
      personalization: "Halo2-Verify-Key".codeUnits,
    );
    final sc = PallasNativeFp.fromBytes64(r);
    assert(BytesUtils.toHexString(sc.toBytes().reversed.toList(),
            prefix: "0x") ==
        "0x2664ff29f181fe2696fde586312fbc14689a9a427a8ad985b66d31fad4f59145");
    // assert(BytesUtils.toHexString(QuickCrypto.blake2b256Hash(vk.toBuffer())) ==
    //     "e83d1f7a4a5d7651284c1a31568605302c9860b55c1f4ae9f47fc3bd762513c3");
    return vk;
  }

  factory PlonkVerifyingKey.build(
      final EvaluationDomain domain,
      final List<VestaAffineNativePoint> fixedCommitments,
      final PermutationVerifyingKey permutation,
      final ConstraintSystem cs) {
    final csDegree = cs.degree();
    final key = PlonkVerifyingKey(
        domain: domain,
        fixedCommitments: fixedCommitments,
        permutation: permutation,
        cs: cs,
        csDegree: csDegree,
        transcriptRepr: PallasNativeFp.fromBytes(BytesUtils.fromHexString(
                "0x2664ff29f181fe2696fde586312fbc14689a9a427a8ad985b66d31fad4f59145")
            .reversed
            .toList()));
    final k = key.toDebugString();
    final r = QuickCrypto.blake2b512Hash(
      k.length.toBigInt.toU64LeBytes(),
      extraBlocks: [StringUtils.encode(k)],
      personalization: "Halo2-Verify-Key".codeUnits,
    );
    final sc = PallasNativeFp.fromBytes64(r);
    assert(BytesUtils.toHexString(sc.toBytes().reversed.toList(),
            prefix: "0x") ==
        "0x2664ff29f181fe2696fde586312fbc14689a9a427a8ad985b66d31fad4f59145");
    return key;
  }

  String toDebugString() {
    String r = "";
    r += "PinnedVerificationKey { ";
    r +=
        "base_modulus: ${StringUtils.fromJson("0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001")}, scalar_modulus: ${StringUtils.fromJson("0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001")}, ";
    r += "domain: ${domain.toDebugString()}, ";
    r += "cs: ${cs.toDebugString()}, ";
    r +=
        "fixed_commitments: [${fixedCommitments.map((e) => "(${BytesUtils.toHexString(e.x.toBytes().reversed.toList(), prefix: "0x")}, ${BytesUtils.toHexString(e.y.toBytes().reversed.toList(), prefix: "0x")})").toList().join(", ")}], ";
    r += "permutation: ${permutation.toDebugString()} }";
    return r;
  }

  void hashInto(Halo2Transcript transcript) {
    transcript.commonScalar(transcriptRepr);
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.repeated(
            fieldNumber: 2, elementType: ProtoFieldType.bytes),
        ProtoFieldConfig.message(3),
        ProtoFieldConfig.message(4),
        ProtoFieldConfig.int32(5),
        ProtoFieldConfig.bytes(6),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;
  @override
  List<Object?> get bufferValues => [
        domain,
        fixedCommitments.map((e) => e.toBytes()).toList(),
        permutation,
        cs,
        csDegree,
        transcriptRepr.toBytes()
      ];

  @override
  List<dynamic> get variables =>
      [domain, fixedCommitments, permutation, cs, csDegree, transcriptRepr];
}

class PlonkProvingKey with Equality, ProtobufEncodableMessage {
  final PlonkVerifyingKey vk;
  final PolynomialScalar<ExtendedLagrangeCoeff> l0;
  final PolynomialScalar<ExtendedLagrangeCoeff> lBlind;
  final PolynomialScalar<ExtendedLagrangeCoeff> lLast;
  final List<PolynomialScalar<LagrangeCoeff>> fixedValues;
  final List<PolynomialScalar<Coeff>> fixedPolys;
  final List<PolynomialScalar<ExtendedLagrangeCoeff>> fixedCosets;
  final PermutationProvingKey permutation;
  PlonkProvingKey clone() => PlonkProvingKey(
      vk: vk.clone(),
      l0: l0,
      lBlind: lBlind,
      lLast: lLast,
      fixedValues: fixedValues,
      fixedPolys: fixedPolys,
      fixedCosets: fixedCosets,
      permutation: permutation);
  factory PlonkProvingKey.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return PlonkProvingKey(
        vk: PlonkVerifyingKey.deserialize(decode.getBytes(1)),
        l0: PolynomialScalar<ExtendedLagrangeCoeff>.deserialize(
            decode.getBytes(2)),
        lBlind: PolynomialScalar<ExtendedLagrangeCoeff>.deserialize(
            decode.getBytes(3)),
        lLast: PolynomialScalar<ExtendedLagrangeCoeff>.deserialize(
            decode.getBytes(4)),
        fixedValues: decode
            .getListOfBytes(5)
            .map((e) => PolynomialScalar<LagrangeCoeff>.deserialize(e))
            .toList(),
        fixedPolys: decode
            .getListOfBytes(6)
            .map((e) => PolynomialScalar<Coeff>.deserialize(e))
            .toList(),
        fixedCosets: decode
            .getListOfBytes(7)
            .map((e) => PolynomialScalar<ExtendedLagrangeCoeff>.deserialize(e))
            .toList(),
        permutation: PermutationProvingKey.deserialize(decode.getBytes(8)));
  }

  const PlonkProvingKey(
      {required this.vk,
      required this.l0,
      required this.lBlind,
      required this.lLast,
      required this.fixedValues,
      required this.fixedPolys,
      required this.fixedCosets,
      required this.permutation});
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.message(2),
        ProtoFieldConfig.message(3),
        ProtoFieldConfig.message(4),
        ProtoFieldConfig.repeated(
            fieldNumber: 5, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 6, elementType: ProtoFieldType.message),
        ProtoFieldConfig.repeated(
            fieldNumber: 7, elementType: ProtoFieldType.message),
        ProtoFieldConfig.message(8),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;
  @override
  List<Object?> get bufferValues => [
        vk,
        l0,
        lBlind,
        lLast,
        fixedValues,
        fixedPolys,
        fixedCosets,
        permutation
      ];
  @override
  List<dynamic> get variables => [
        vk,
        l0,
        lBlind,
        lLast,
        fixedValues,
        fixedPolys,
        fixedCosets,
        permutation
      ];
}

class PlonkKeyGenerator {
  static PlonkProvingKey keygenPk(
      {required OrchardCircuit circuit,
      required PolyParams params,
      required PlonkVerifyingKey vk,
      required ZCashCryptoContext context}) {
    final cs = ConstraintSystem.defaultConfig();
    final config = OrchardCircuitConfig.configure(cs, context);
    if (params.n < cs.minimumRows()) {
      throw Halo2Exception.operationFailed("keygenPk",
          reason: "Not enough rows available");
    }
    final assembly = PlonkAssembly(
        k: params.k,
        fixed: List.generate(
            cs.numFixedColumns, (index) => vk.domain.emptyLagrangeAssigned()),
        permutation: PermutationAssembly.newAssembly(params.n, cs.permutation),
        selectors: List.generate(
            cs.numSelectors, (index) => List.filled(params.n, false)),
        usableRows:
            ComparableIntRange(0, (params.n - (cs.blindingFactors() + 1))));
    V1Plan.synthesize(
        cs: assembly,
        circuit: circuit,
        config: config,
        constants: cs.constants.clone(),
        context: context);
    final fixed = Polynomial.batchInvertAssigned(assembly.fixed);
    final selectorPolys = cs.compressSelectors(assembly.selectors);
    for (final poly in selectorPolys) {
      fixed.add(vk.domain.lagrangeFromVec(poly));
    }
    final fixedPolys =
        fixed.map((e) => vk.domain.lagrangeToCoeff(e.clone())).toList();
    final fixedCosets =
        fixedPolys.map((e) => vk.domain.coeffToExtended(e.clone())).toList();
    final permutation =
        assembly.permutation.buildPk(params, vk.domain, cs.permutation);
    final l0 = vk.domain.emptyLagrange();
    l0.values[0] = PallasNativeFp.one();
    final l1 = vk.domain.lagrangeToCoeff(l0);
    final l2 = vk.domain.coeffToExtended(l1);
    final lBlind = vk.domain.emptyLagrange();
    final int n = cs.blindingFactors();
    for (int i = 0; i < n; i++) {
      final int index = lBlind.values.length - 1 - i;
      if (index < 0) break;
      lBlind.values[index] = PallasNativeFp.one();
    }
    final lBlind1 = vk.domain.lagrangeToCoeff(lBlind);
    final lBlind2 = vk.domain.coeffToExtended(lBlind1);
    final lLast = vk.domain.emptyLagrange();
    lLast.values[params.n - cs.blindingFactors() - 1] = PallasNativeFp.one();
    final lLast1 = vk.domain.lagrangeToCoeff(lLast);
    final lLast2 = vk.domain.coeffToExtended(lLast1);
    return PlonkProvingKey(
        vk: vk,
        l0: l2,
        lBlind: lBlind2,
        lLast: lLast2,
        fixedValues: fixed,
        fixedPolys: fixedPolys,
        fixedCosets: fixedCosets,
        permutation: permutation);
  }

  static (EvaluationDomain, ConstraintSystem, OrchardCircuitConfig)
      createDomain(PolyParams params, ZCashCryptoContext context) {
    final cs = ConstraintSystem.defaultConfig();
    final config = OrchardCircuitConfig.configure(cs, context);
    final degree = cs.degree();
    final domain = EvaluationDomain.newDomain(degree, params.k);
    return (domain, cs, config);
  }

  static PlonkVerifyingKey keygenVk(
    OrchardCircuit circuit,
    ZCashCryptoContext context, {
    PolyParams? p,
    int k = 11,
  }) {
    final params = p ?? PolyParams.newParams(k);
    final (domain, cs, config) = createDomain(params, context);
    if (params.n < cs.minimumRows()) {
      throw Halo2Exception.operationFailed("keygenVk",
          reason: "Not enough rows available");
    }
    final assembly = PlonkAssembly(
        k: params.k,
        fixed: List.generate(
            cs.numFixedColumns, (index) => domain.emptyLagrangeAssigned()),
        permutation: PermutationAssembly.newAssembly(params.n, cs.permutation),
        selectors: List.generate(
            cs.numSelectors, (index) => List.filled(params.n, false)),
        usableRows:
            ComparableIntRange(0, (params.n - (cs.blindingFactors() + 1))));

    V1Plan.synthesize(
        cs: assembly,
        circuit: circuit,
        config: config,
        constants: cs.constants.clone(),
        context: context);
    final fixed = Polynomial.batchInvertAssigned(assembly.fixed);
    final selectorPolys = cs.compressSelectors(assembly.selectors);
    for (final poly in selectorPolys) {
      fixed.add(domain.lagrangeFromVec(poly));
    }
    final permutationVk =
        assembly.permutation.buildVk(params, domain, cs.permutation);
    final List<VestaAffineNativePoint> fixedCommitments = fixed
        .map((poly) =>
            params.commitLagrange(poly, PallasNativeFp.one()).toAffine())
        .toList(growable: false);
    return PlonkVerifyingKey.build(domain, fixedCommitments, permutationVk, cs);
  }
}
