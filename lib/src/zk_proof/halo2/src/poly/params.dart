import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';

class PolyParams with Equality, ProtobufEncodableMessage {
  final int k;
  final int n;
  final List<VestaAffineNativePoint> g;
  final List<VestaAffineNativePoint> gLagrange;
  final VestaAffineNativePoint w;
  final VestaAffineNativePoint u;

  const PolyParams(
      {required this.k,
      required this.n,
      required this.g,
      required this.gLagrange,
      required this.w,
      required this.u});
  factory PolyParams.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    final param = PolyParams(
        k: decode.getInt(1),
        n: decode.getInt(2),
        g: decode
            .getList<List<int>>(3)
            .map((e) => VestaAffineNativePoint.fromBytes(e))
            .toList(),
        gLagrange: decode
            .getList<List<int>>(4)
            .map((e) => VestaAffineNativePoint.fromBytes(e))
            .toList(),
        w: VestaAffineNativePoint.fromBytes(decode.getBytes(5)),
        u: VestaAffineNativePoint.fromBytes(decode.getBytes(6)));
    assert(param.k != 11 ||
        BytesUtils.toHexString(QuickCrypto.blake2b256Hash(param.toBuffer())) ==
            "0e62a7083c2dfec972bce93a00cbb9043a323968e5b6757d0c2940c9aa6e673f");
    return param;
  }

  factory PolyParams.newParams(int k) {
    if (k >= 32) {
      throw ArgumentException.invalidOperationArguments("newParams",
          reason: "Invalid k argument.");
    }
    final n = 1 << k;
    List<VestaNativePoint> gProjective = [];
    for (var i = 0; i < n; i++) {
      final hasher = VestaNativePoint.hashToCurve(
          domainPrefix: "Halo2-Parameters", message: [0, ...i.toU32LeBytes()]);
      gProjective.add(hasher);
    }

    final g = gProjective.map((e) => e.toAffine()).toList();
    var alphaInv = PallasNativeFp.rootOfUnityInv();
    for (var i = k; i < PallasFPConst.S; i++) {
      alphaInv = alphaInv.square();
    }

    // final gLagrangeProjective = List<VestaNativePoint>.from(gProjective);
    Halo2Utils.bestFft(gProjective, alphaInv, k);
    final minv = PallasNativeFp.twoInv().pow(BigInt.from(k));
    for (var i = 0; i < gProjective.length; i++) {
      gProjective[i] *= minv;
    }

    final gLagrange = gProjective.map((e) => e.toAffine()).toList();

    // Hash points w and u
    final w = VestaNativePoint.hashToCurve(
        domainPrefix: "Halo2-Parameters", message: [1]).toAffine();
    final u = VestaNativePoint.hashToCurve(
        domainPrefix: "Halo2-Parameters", message: [2]).toAffine();
    return PolyParams(k: k, n: n, g: g, gLagrange: gLagrange, w: w, u: u);
  }

  VestaNativePoint commitLagrange(
      Polynomial<PallasNativeFp, LagrangeCoeff> poly, PallasNativeFp r) {
    return Halo2Utils.bestMultiexp([...poly.values, r], [...gLagrange, w]);
  }

  /// Computes a commitment to a polynomial described by the provided
  /// coefficients. The commitment is blinded by the blinding factor `r`.
  VestaNativePoint commit(
      Polynomial<PallasNativeFp, Basis> poly, PallasNativeFp r) {
    return Halo2Utils.bestMultiexp([...poly.values, r], [...g, w]);
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.int32(2),
        ProtoFieldConfig.repeated(
            fieldNumber: 3, elementType: ProtoFieldType.bytes),
        ProtoFieldConfig.repeated(
            fieldNumber: 4, elementType: ProtoFieldType.bytes),
        ProtoFieldConfig.bytes(5),
        ProtoFieldConfig.bytes(6),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;
  @override
  List<Object?> get bufferValues => [
        k,
        n,
        g.map((e) => e.toBytes()).toList(),
        gLagrange.map((e) => e.toBytes()).toList(),
        w.toBytes(),
        u.toBytes()
      ];
  @override
  List<dynamic> get variables => [k, n, g, gLagrange, w, u];
}
