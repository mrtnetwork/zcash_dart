import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';

typedef SubgroupPoint = JubJubPoint;

class SaplingUtils {
  static List<int> kdfSapling({
    required List<int> ephemeralKey,
    required List<int> secret,
  }) {
    return QuickCrypto.blake2b256Hash(
      secret,
      extraBlocks: [ephemeralKey],
      personalization: "Zcash_SaplingKDF".codeUnits,
    );
  }

  /// Consensus JubJub generators as compressed bytes (see
  /// `generatePedersenHashExpTable` / zcash spec §5.4.8). Bytes avoid
  /// constructing curve points for every `api.jubjub.mult/add` call.
  static const List<int> valueCommitmentValueGeneratorBytes = [
    215,
    200,
    103,
    6,
    245,
    129,
    122,
    167,
    24,
    205,
    28,
    250,
    208,
    50,
    51,
    188,
    214,
    74,
    119,
    137,
    253,
    148,
    34,
    211,
    177,
    122,
    246,
    130,
    58,
    126,
    106,
    198,
  ];
  static const List<int> valueCommitmentRandomnessGeneratorBytes = [
    139,
    106,
    11,
    56,
    185,
    250,
    174,
    60,
    59,
    128,
    59,
    71,
    176,
    241,
    70,
    173,
    80,
    171,
    34,
    30,
    110,
    42,
    251,
    230,
    219,
    222,
    69,
    203,
    169,
    211,
    129,
    237,
  ];
  static const List<int> proofGenerationKeyGeneratorBytes = [
    231,
    232,
    93,
    224,
    247,
    249,
    122,
    70,
    210,
    73,
    161,
    245,
    234,
    81,
    223,
    80,
    204,
    72,
    73,
    15,
    132,
    1,
    201,
    222,
    122,
    42,
    223,
    24,
    7,
    209,
    182,
    212,
  ];
  static const List<int> nullifierPositionGeneratorBytes = [
    101,
    0,
    43,
    199,
    54,
    250,
    247,
    163,
    66,
    46,
    255,
    255,
    232,
    184,
    85,
    225,
    143,
    186,
    150,
    160,
    21,
    138,
    158,
    252,
    165,
    132,
    191,
    64,
    84,
    157,
    54,
    225,
  ];
  static const List<int> spendingKeyGeneratorBytes = [
    48,
    181,
    242,
    170,
    173,
    50,
    86,
    48,
    188,
    221,
    219,
    206,
    77,
    103,
    101,
    109,
    5,
    253,
    28,
    194,
    208,
    55,
    187,
    83,
    117,
    182,
    233,
    109,
    158,
    1,
    161,
    215,
  ];
  static const List<int> noteCommitmentRandomnessGeneratorBytes = [
    172,
    119,
    108,
    121,
    101,
    99,
    252,
    212,
    76,
    196,
    156,
    250,
    234,
    139,
    183,
    150,
    149,
    44,
    38,
    110,
    71,
    119,
    157,
    148,
    87,
    76,
    16,
    173,
    1,
    117,
    75,
    17,
  ];

  static BuBytes mixingPedersenHashBytes(List<int> cmBytes32, int position) {
    final posBytes = List<int>.filled(32, 0);
    var n = position;
    for (var i = 0; i < 8; i++) {
      posBytes[i] = n & 0xff;
      n >>= 8;
    }
    final posG = blockchainUtils.api.jubjub.mult(
      posBytes,
      nullifierPositionGeneratorBytes,
    );
    return blockchainUtils.api.jubjub.add(cmBytes32, posG);
  }

  static SaplingExtendedSpendingKey dummySk() {
    final seedBytes = QuickCrypto.generateRandom();
    SaplingExtendedSpendingKey ex = SaplingExtendedSpendingKey.master(
      seedBytes,
    );
    final sk = ex.sk;
    final akBytes = blockchainUtils.api.jubjub.mult(
      sk.ask.scalar().toBytes(),
      spendingKeyGeneratorBytes,
    );
    final nkBytes = blockchainUtils.api.jubjub.mult(
      sk.nsk.toBytes(),
      proofGenerationKeyGeneratorBytes,
    );
    final fvk = SaplingFullViewingKey(
      ovk: sk.ovk,
      vk: SaplingViewingKey(
        ak: RedJubJubSpendPublicKey.fromBytes(akBytes),
        nk: SaplingNullifierDerivingKey.fromBytes(nkBytes),
      ),
    );
    return SaplingExtendedSpendingKey(
      sk: SaplingExpandedSpendingKey(
        ask: ex.sk.ask,
        nsk: ex.sk.nsk,
        ovk: ex.sk.ovk,
        fvk: fvk,
      ),
      keyData: ex.keyData,
    );
  }

  static BuBytes kaSaplingDerivePublicBytes({
    required List<int> scalar32,
    required List<int> point32,
  }) {
    return blockchainUtils.api.jubjub.mult(scalar32, point32);
  }

  static BuBytes kaSaplingAgreeBytes({
    required List<int> scalar32,
    required List<int> point32,
  }) {
    final shared = blockchainUtils.api.jubjub.mult(scalar32, point32);
    final cleared = blockchainUtils.api.jubjub.clearCofactor(shared);
    if (cleared == null) {
      throw ZcashErrors.saplingFailed(
        "kaAgree",
        reason: "Shared secret is identity.",
      );
    }
    return cleared;
  }

  static BuBytes windowedPedersenCommitBytes({
    required Personalization personalization,
    required List<bool> s,
    required List<int> r32,
    required ZcashCryptoContext context,
  }) {
    final pedersen = context.pedersonHash(
      personalization: personalization,
      bits: s,
    );
    final rG = blockchainUtils.api.jubjub.mult(
      r32,
      noteCommitmentRandomnessGeneratorBytes,
    );
    return blockchainUtils.api.jubjub.add(pedersen, rG);
  }

  static List<int> prfNf({
    required List<int> nkBytes,
    required List<int> rhoBytes,
  }) {
    return QuickCrypto.blake2s256Hash(
      nkBytes,
      personalization: "Zcash_nf".codeUnits,
      extraBlocks: [rhoBytes],
    );
  }

  static List<JubJubFq> computeMultipacking(List<bool> bits) {
    final List<JubJubFq> result = [];
    final int capacity = JubJubFqConst.capacity;

    for (var i = 0; i < bits.length; i += capacity) {
      final chunk = bits.sublist(
        i,
        (i + capacity <= bits.length) ? i + capacity : bits.length,
      );

      JubJubFq cur = JubJubFq.zero;
      JubJubFq coeff = JubJubFq.one;

      for (final bit in chunk) {
        if (bit) {
          cur = cur + coeff;
        }
        coeff = coeff.double();
      }

      result.add(cur);
    }

    return result;
  }
}
