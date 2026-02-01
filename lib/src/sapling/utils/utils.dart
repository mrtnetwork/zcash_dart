import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/pedersen_hash/pedersen_hash.dart';

typedef SubgroupPoint = JubJubPoint;

class SaplingUtils {
  static List<int> kdfSapling(
      {required List<int> ephemeralKey, required List<int> secret}) {
    return QuickCrypto.blake2b256Hash(secret,
        extraBlocks: [ephemeralKey],
        personalization: "Zcash_SaplingKDF".codeUnits);
  }

  static JubJubNativePoint mixingPedersenHash(
    JubJubNativePoint cm,
    int position,
  ) {
    return cm +
        (nullifierPositionGeneratorNative *
            JubJubNativeFr(BigInt.from(position)));
  }

  static SaplingExtendedSpendingKey dummySk() {
    final seedBytes = QuickCrypto.generateRandom();
    SaplingExtendedSpendingKey ex =
        SaplingExtendedSpendingKey.master(seedBytes);
    final sk = ex.sk;
    final spendGenerator = SaplingKeyUtils.spendAuthGeneratorNative;
    final mult = proofGenerationKeyGeneratorNative *
        JubJubNativeFr.fromBytes(sk.nsk.toBytes());
    final fvk = SaplingFullViewingKey(
      ovk: sk.ovk,
      vk: SaplingViewingKey(
          ak: SaplingSpendVerificationKey(spendGenerator *
              JubJubNativeFr.fromBytes(sk.ask.inner.toBytes())),
          nk: SaplingNullifierDerivingKey(mult)),
    );
    return SaplingExtendedSpendingKey(
        sk: SaplingExpandedSpendingKey(
            ask: ex.sk.ask, nsk: ex.sk.nsk, ovk: ex.sk.ovk, fvk: fvk),
        keyData: ex.keyData);
  }

  static JubJubNativePoint kaSaplingDerivePublic(
      {required JubJubNativeFr scalar, required JubJubNativePoint b}) {
    return b * scalar;
  }

  static JubJubNativePoint kaSaplingAgreeNative(
      {required JubJubNativeFr scalar, required JubJubNativePoint b}) {
    return (b * scalar).clearCofactor();
  }

  static JubJubNativePoint windowedPedersenCommitNative(
      {required Personalization personalization,
      required List<bool> s,
      required JubJubNativeFr r,
      required ZCashCryptoContext context}) {
    final generator = noteCommitmentRandomnessGeneratorNative;
    return context
            .getPedersen()
            .hash(personalization: personalization, inputBits: s) +
        (generator * r);
  }

  static List<int> prfNfNative(
      {required JubJubNativePoint nk, required JubJubNativePoint rho}) {
    return QuickCrypto.blake2s256Hash(nk.toBytes(),
        personalization: "Zcash_nf".codeUnits, extraBlocks: [rho.toBytes()]);
  }

  static JubJubNativePoint get valueCommitmentValueGeneratorNative =>
      JubJubAffineNativePoint(
              u: JubJubNativeFq.nP(BigInt.parse(
                  "17752513580251316969848061286168330683816061618931639002070819176278144839505")),
              v: JubJubNativeFq.nP(BigInt.parse(
                  "31850056387203751840695958063801678921837471012044944184359114647051147135191")))
          .toExtended();
  static JubJubNativePoint get valueCommitmentRandomnessGeneratorNative =>
      JubJubAffineNativePoint(
              u: JubJubNativeFq.nP(BigInt.parse(
                  "47042227020334719030310671629496501061777616454137182971856918820250544653111")),
              v: JubJubNativeFq.nP(BigInt.parse(
                  "49531484613049745751551498609154147537293487462303198979615882148044956461707")))
          .toExtended();
  static JubJubNativePoint get proofGenerationKeyGeneratorNative =>
      JubJubAffineNativePoint(
              u: JubJubNativeFq.nP(BigInt.parse(
                  "9201111513613159952332790701602097324772839388200533360387436201225747309937")),
              v: JubJubNativeFq.nP(BigInt.parse(
                  "38317288103109448611012419043659719984035489099661802521426844652233060903143")))
          .toExtended();
  static JubJubNativePoint get nullifierPositionGeneratorNative =>
      JubJubAffineNativePoint(
              u: JubJubNativeFq.nP(BigInt.parse(
                  "16284607604664980143012113168037881631153608968546055569021851346435633393883")),
              v: JubJubNativeFq.nP(BigInt.parse(
                  "43970841899705611252315894752661758536072317246601145990753487800550441025637")))
          .toExtended();
  static JubJubNativePoint get spendingKeyGeneratorNative => JubJubAffineNativePoint(
          u: JubJubNativeFq.nP(BigInt.parse(
              "4139425550610461525665941076812662132363359224232624900223172373014329534291")),
          v: JubJubNativeFq.nP(BigInt.parse(
              "39635691377166599497441725607757882405510648532010642268690928210480481875248")))
      .toExtended();
  static JubJubNativePoint get noteCommitmentRandomnessGeneratorNative {
    return JubJubAffineNativePoint(
            u: JubJubNativeFq.nP(BigInt.parse(
                "17604198421250097151573650471091947092640882385666301668182991308218746233954")),
            v: JubJubNativeFq.nP(BigInt.parse(
                "7822639505282159744111952162548915624490722403061460022379792963749532170156")))
        .toExtended();
  }
}
