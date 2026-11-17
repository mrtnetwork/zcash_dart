import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/transaction/builders/types.dart';
import 'package:zcash_dart/src/orchard/builder/builder.dart';
import 'package:zcash_dart/src/sapling/builder/builder.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';
import 'package:zcash_dart/src/transparent/builder/builder.dart';

abstract mixin class BaseTransactionBuilder {
  abstract final TransactionBuildConfig buildConfig;
  abstract final SaplingBuilder sapling;
  abstract final OrchardBuilder orchard;

  /// Builder for the Ironwood pool (NU6.3 second Orchard-family slot).
  abstract final OrchardBuilder ironwood;
  abstract final TransparentBuilder transparent;
  abstract final int targetHeight;
  abstract final int expiryHeight;
  abstract final ZcashCryptoContext context;
  abstract final ZcashNetwork network;
  abstract final ZFeeRole feeBuilder;

  /// Resolves the consensus branch for [targetHeight]. Defaults to
  /// [DefaultUpgradeActivationProvider]; override for chains with custom
  /// activation heights (e.g. a zebra regtest with NU6.3 active from 1).
  abstract final UpgradeActivationProvider activationProvider;
  final lock = SafeAtomicLock();

  bool hasShieldedSpends() {
    return sapling.spends.isNotEmpty ||
        orchard.spends.isNotEmpty ||
        ironwood.spends.isNotEmpty;
  }

  bool hasShieldedOutputs() {
    return sapling.outputs.isNotEmpty ||
        orchard.outputs.isNotEmpty ||
        ironwood.outputs.isNotEmpty;
  }

  bool hasSaplingSpends() {
    return sapling.spends.isNotEmpty;
  }

  bool hasSaplingOutputs() {
    return sapling.outputs.isNotEmpty;
  }

  bool hasOrchardSpends() {
    return orchard.spends.isNotEmpty || ironwood.spends.isNotEmpty;
  }

  bool hasTransparentSpends() {
    return transparent.inputs.isNotEmpty;
  }

  bool hasTransparentOutputs() {
    return transparent.output.isNotEmpty;
  }
}
