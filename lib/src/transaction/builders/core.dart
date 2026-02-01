import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/transaction/builders/types.dart';
import 'package:zcash_dart/src/orchard/builder/builder.dart';
import 'package:zcash_dart/src/sapling/builder/builder.dart';
import 'package:zcash_dart/src/transparent/builder/builder.dart';

abstract mixin class BaseTransactionBuilder {
  abstract final TransactionBuildConfig buildConfig;
  abstract final SaplingBuilder sapling;
  abstract final OrchardBuilder orchard;
  abstract final TransparentBuilder transparent;
  abstract final int targetHeight;
  abstract final int expiryHeight;
  abstract final ZCashCryptoContext context;
  abstract final ZCashNetwork network;
  abstract final Zip317FeeRole feeBuilder;
  final lock = SafeAtomicLock();

  bool hasShieldedSpends() {
    return sapling.spends.isNotEmpty || orchard.outputs.isNotEmpty;
  }

  bool hasShieldedOutputs() {
    return sapling.outputs.isNotEmpty || orchard.spends.isNotEmpty;
  }

  bool hasSaplingSpends() {
    return sapling.spends.isNotEmpty;
  }

  bool hasSaplingOutputs() {
    return sapling.outputs.isNotEmpty;
  }

  bool hasOrchardSpends() {
    return orchard.spends.isNotEmpty;
  }

  bool hasTransparentSpends() {
    return transparent.inputs.isNotEmpty;
  }

  bool hasTransparentOutputs() {
    return transparent.output.isNotEmpty;
  }
}
