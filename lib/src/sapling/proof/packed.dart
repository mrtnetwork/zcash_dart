import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/sapling/proof/parameters.dart';
import 'package:zcash_dart/src/sapling/proof/types.dart';

/// Packed little-endian witnesses for the new proving backend
/// (`blockchainUtils.api.sapling`, Rust `ffi::sapling`).
///
/// Layouts (mirror the Rust docs):
/// - spend (1288 B): value u64 | randomness[32] | ak[32] | nsk[32] |
///   g_d[32] | commitment_randomness[32] | ar[32] | auth_path[32][32] |
///   pos[32] (bytes 0/1) | anchor[32]
/// - output (168 B): value u64 | randomness[32] | g_d[32] | pk_d[32] |
///   commitment_randomness[32] | esk[32]
/// - verify inputs: 7×32 (spend) or 5×32 (output) concatenated limbs.
abstract final class SaplingPackedWitness {
  static List<int> _u64le(BigInt v) {
    var n = v.toUnsigned(64);
    final out = List<int>.filled(8, 0);
    for (var i = 0; i < 8; i++) {
      out[i] = (n & BigInt.from(0xff)).toInt();
      n >>= 8;
    }
    return out;
  }

  static List<int> _b32(List<int> b, String name) {
    if (b.length != 32) {
      throw BuError(
        DefaultErrorType.invalidLength,
        "Invalid $name length ${b.length}, want 32.",
      );
    }
    return b;
  }

  static List<int> packSpend(SaplingSpendParams p) {
    if (p.authPath.length != 32) {
      throw BuError(
        DefaultErrorType.invalidLength,
        "Invalid auth path length ${p.authPath.length}, want 32.",
      );
    }
    return [
      ..._u64le(p.value.value),
      ..._b32(p.randomness, 'randomness'),
      ..._b32(p.proofGenerationKey.ak.toBytes(), 'ak'),
      ..._b32(p.proofGenerationKey.nsk, 'nsk'),
      ..._b32(p.paymentAddress.gd().toBytes(), 'g_d'),
      ..._b32(p.commitmentRandomness, 'commitment_randomness'),
      ..._b32(p.ar, 'ar'),
      for (final e in p.authPath) ..._b32(e.$1.toBytes(), 'auth_path'),
      for (final e in p.authPath) e.$2 ? 1 : 0,
      ..._b32(p.anchor.toBytes(), 'anchor'),
    ];
  }

  static List<int> packOutput(SaplingOutputParams p) {
    return [
      ..._u64le(p.value.value),
      ..._b32(p.randomness, 'randomness'),
      ..._b32(p.paymentAddress.gd().toBytes(), 'g_d'),
      ..._b32(p.paymentAddress.transmissionKey.toBytes(), 'pk_d'),
      ..._b32(p.commitmentRandomness.toBytes(), 'commitment_randomness'),
      ..._b32(p.esk, 'esk'),
    ];
  }

  /// Concatenated 32-byte input limbs for `verify` (5 or 7 enforced upstream).
  static List<int> packVerifyInputs(SaplingVerifyInputs inputs) {
    final out = <int>[];
    for (final i in inputs.inputs) {
      out.addAll(_b32(i.toBytes(), 'input'));
    }
    return out;
  }
}
