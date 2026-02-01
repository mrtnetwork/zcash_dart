import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/multiexp.dart';

class Groth16Proof with LayoutSerializable {
  final G1NativeAffinePoint a;
  final G2NativeAffinePoint b;
  final G1NativeAffinePoint c;
  const Groth16Proof({required this.a, required this.b, required this.c});
  factory Groth16Proof.deserialize(List<int> bytes) {
    final decode =
        LayoutSerializable.deserialize(bytes: bytes, layout: _layout());
    return Groth16Proof.deserializeJson(decode);
  }
  factory Groth16Proof.deserializeJson(Map<String, dynamic> json) {
    return Groth16Proof(
        a: G1NativeAffinePoint.fromBytes(json.valueAsBytes("a")),
        b: G2NativeAffinePoint.fromBytes(json.valueAsBytes("b")),
        c: G1NativeAffinePoint.fromBytes(json.valueAsBytes("c")));
  }
  static Layout<Map<String, dynamic>> _layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(48, property: "a"),
      LayoutConst.fixedBlobN(96, property: "b"),
      LayoutConst.fixedBlobN(48, property: "c"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return _layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"a": a.toBytes(), "b": b.toBytes(), "c": c.toBytes()};
  }
}

class Groth16VerifyingKey with LayoutSerializable {
  /// Alpha in G1 for verifying and for creating A/C elements of proof.
  /// Never the point at infinity.
  final G1NativeAffinePoint alphaG1;

  /// Beta in G1 and G2 for verifying and for creating B/C elements of proof.
  /// Never the point at infinity.
  final G1NativeAffinePoint betaG1;
  final G2NativeAffinePoint betaG2;

  /// Gamma in G2 for verifying. Never the point at infinity.
  final G2NativeAffinePoint gammaG2;

  /// Delta in G1/G2 for verifying and proving, essentially the magic
  /// trapdoor that forces the prover to evaluate the C element of the
  /// proof with only components from the CRS. Never the point at infinity.
  final G1NativeAffinePoint deltaG1;
  final G2NativeAffinePoint deltaG2;

  /// Elements of the form
  /// (beta * u_i(tau) + alpha * v_i(tau) + w_i(tau)) / gamma
  /// for all public inputs. Because all public inputs have a dummy constraint,
  /// this is the same size as the number of inputs, and never contains points
  /// at infinity.
  final List<G1NativeAffinePoint> ic;

  const Groth16VerifyingKey({
    required this.alphaG1,
    required this.betaG1,
    required this.betaG2,
    required this.gammaG2,
    required this.deltaG1,
    required this.deltaG2,
    required this.ic,
  });

  factory Groth16VerifyingKey.deserializeJson(Map<String, dynamic> json,
      {bool check = true}) {
    return Groth16VerifyingKey(
        alphaG1: G1NativeAffinePoint.fromBytes(json.valueAsBytes("alpha_g1"),
            check: check),
        betaG1: G1NativeAffinePoint.fromBytes(json.valueAsBytes("beta_g1"),
            check: check),
        betaG2: G2NativeAffinePoint.fromBytes(json.valueAsBytes("beta_g2"),
            check: check),
        gammaG2: G2NativeAffinePoint.fromBytes(json.valueAsBytes("gamma_g2"),
            check: check),
        deltaG1: G1NativeAffinePoint.fromBytes(json.valueAsBytes("delta_g1"),
            check: check),
        deltaG2: G2NativeAffinePoint.fromBytes(json.valueAsBytes("delta_g2"),
            check: check),
        ic: json
            .valueEnsureAsList<List<int>>("ic")
            .map((e) => G1NativeAffinePoint.fromBytes(e, check: check))
            .toList());
  }

  static Layout<Map<String, dynamic>> _layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(96, property: "alpha_g1"),
      LayoutConst.fixedBlobN(96, property: "beta_g1"),
      LayoutConst.fixedBlobN(192, property: "beta_g2"),
      LayoutConst.fixedBlobN(192, property: "gamma_g2"),
      LayoutConst.fixedBlobN(96, property: "delta_g1"),
      LayoutConst.fixedBlobN(192, property: "delta_g2"),
      LayoutConst.vec(LayoutConst.fixedBlobN(96),
          lengthSizeLayout: LayoutConst.u32be(), property: "ic"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return _layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "alpha_g1": alphaG1.toBytes(mode: PubKeyModes.uncompressed),
      "beta_g1": betaG1.toBytes(mode: PubKeyModes.uncompressed),
      "beta_g2": betaG2.toBytes(mode: PubKeyModes.uncompressed),
      "gamma_g2": gammaG2.toBytes(mode: PubKeyModes.uncompressed),
      "delta_g1": deltaG1.toBytes(mode: PubKeyModes.uncompressed),
      "delta_g2": deltaG2.toBytes(mode: PubKeyModes.uncompressed),
      "ic": ic.map((e) => e.toBytes(mode: PubKeyModes.uncompressed)).toList()
    };
  }

  Groth16PreparedVerifyingKey prepareVerifyingKey() =>
      Groth16PreparedVerifyingKey.prepareVerifyingKey(this);
}

class Groth16Parameters with LayoutSerializable {
  /// Verifying key
  final Groth16VerifyingKey vk;

  /// Elements of the form ((tau^i * t(tau)) / delta) for i between 0 and m-2 inclusive.
  /// Never contains points at infinity.
  final List<G1NativeAffinePoint> h;

  /// Elements of the form (beta * u_i(tau) + alpha * v_i(tau) + w_i(tau)) / delta
  /// for all auxiliary inputs. Never contains points at infinity.
  final List<G1NativeAffinePoint> l;

  /// QAP "A" polynomials evaluated at tau in the Lagrange basis.
  /// Polynomials that evaluate to zero are omitted from the CRS.
  final List<G1NativeAffinePoint> a;

  /// QAP "B" polynomials evaluated at tau in the Lagrange basis.
  /// Needed in G1 and G2 for C/B queries. Never contains points at infinity.
  final List<G1NativeAffinePoint> bG1;
  final List<G2NativeAffinePoint> bG2;
  factory Groth16Parameters.deserialize(List<int> bytes, {bool check = true}) {
    final decode =
        LayoutSerializable.deserialize(bytes: bytes, layout: _layout());

    return Groth16Parameters.deserializeJson(decode, check: check);
  }

  factory Groth16Parameters.deserializeJson(Map<String, dynamic> json,
      {bool check = true}) {
    return Groth16Parameters(
      vk: Groth16VerifyingKey.deserializeJson(
          json.valueEnsureAsMap<String, dynamic>("vk"),
          check: check),
      h: json
          .valueEnsureAsList<List<int>>("h")
          .map((e) => G1NativeAffinePoint.fromBytes(e, check: check))
          .toList(),
      l: json
          .valueEnsureAsList<List<int>>("l")
          .map((e) => G1NativeAffinePoint.fromBytes(e, check: check))
          .toList(),
      a: json
          .valueEnsureAsList<List<int>>("a")
          .map((e) => G1NativeAffinePoint.fromBytes(e, check: check))
          .toList(),
      bG1: json
          .valueEnsureAsList<List<int>>("bg_1")
          .map((e) => G1NativeAffinePoint.fromBytes(e, check: check))
          .toList(),
      bG2: json
          .valueEnsureAsList<List<int>>("bg_2")
          .map((e) => G2NativeAffinePoint.fromBytes(e, check: check))
          .toList(),
    );
  }
  static Layout<Map<String, dynamic>> _layout({String? property}) {
    return LayoutConst.struct([
      Groth16VerifyingKey._layout(property: "vk"),
      LayoutConst.vec(LayoutConst.fixedBlobN(96),
          lengthSizeLayout: LayoutConst.u32be(), property: "h"),
      LayoutConst.vec(LayoutConst.fixedBlobN(96),
          lengthSizeLayout: LayoutConst.u32be(), property: "l"),
      LayoutConst.vec(LayoutConst.fixedBlobN(96),
          lengthSizeLayout: LayoutConst.u32be(), property: "a"),
      LayoutConst.vec(LayoutConst.fixedBlobN(96),
          lengthSizeLayout: LayoutConst.u32be(), property: "bg_1"),
      LayoutConst.vec(LayoutConst.fixedBlobN(192),
          lengthSizeLayout: LayoutConst.u32be(), property: "bg_2"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "vk": vk.toSerializeJson(),
      "h": h.map((e) => e.toBytes(mode: PubKeyModes.uncompressed)).toList(),
      "l": l.map((e) => e.toBytes(mode: PubKeyModes.uncompressed)).toList(),
      "a": a.map((e) => e.toBytes(mode: PubKeyModes.uncompressed)).toList(),
      "bg_1":
          bG1.map((e) => e.toBytes(mode: PubKeyModes.uncompressed)).toList(),
      "bg_2":
          bG2.map((e) => e.toBytes(mode: PubKeyModes.uncompressed)).toList(),
    };
  }

  const Groth16Parameters({
    required this.vk,
    required this.h,
    required this.l,
    required this.a,
    required this.bG1,
    required this.bG2,
  });

  Groth16VerifyingKey getVk() {
    return vk;
  }

  G1Source getHBuilder(int _) {
    return G1Source(points: h, start: 0);
  }

  G1Source getLBuilder(int _) {
    return G1Source(points: l, start: 0);
  }

  // Equivalent to `get_a`
  (G1Source, G1Source) getABuilders(int numInputs, int _) {
    return (
      G1Source(points: a, start: 0),
      G1Source(points: a, start: numInputs)
    );
  }

// Equivalent to `get_a`
  (G1Source, G1Source) getBG1Builders(int numInputs, int _) {
    return (
      G1Source(points: bG1, start: 0),
      G1Source(points: bG1, start: numInputs)
    );
  }

  (G2Source, G2Source) getBG2Builders(int numInputs, int _) {
    return (
      G2Source(points: bG2, start: 0),
      G2Source(points: bG2, start: numInputs)
    );
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return _layout(property: property);
  }
}

class Groth16PreparedVerifyingKey {
  /// Pairing result of alpha * beta
  final GtNative alphaG1BetaG2;

  /// -gamma in G2
  final G2NativePrepared negGammaG2;

  /// -delta in G2
  final G2NativePrepared negDeltaG2;

  /// Copy of IC from `PlonkVerifyingKey`
  final List<G1NativeAffinePoint> ic;

  const Groth16PreparedVerifyingKey(
      {required this.alphaG1BetaG2,
      required this.negGammaG2,
      required this.negDeltaG2,
      required this.ic});
  factory Groth16PreparedVerifyingKey.prepareVerifyingKey(
      Groth16VerifyingKey vk) {
    final gamma = -vk.gammaG2;
    final delta = -vk.deltaG2;
    return Groth16PreparedVerifyingKey(
        alphaG1BetaG2: Bls12PairingUtils.pairing(vk.alphaG1, vk.betaG2),
        negGammaG2: G2NativePrepared.fromG2(gamma),
        negDeltaG2: G2NativePrepared.fromG2(delta),
        ic: vk.ic);
  }
}
