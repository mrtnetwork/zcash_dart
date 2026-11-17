import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/note/src/note_encryption.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/pczt/pczt.dart';
import 'package:zcash_dart/src/provider/provider.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/transparent.dart';
import 'package:zcash_dart/src/value/value.dart';
part 'input.dart';
part 'output.dart';
part 'fee.dart';
part 'pczt.dart';
part 'signer.dart';
part 'extractor.dart';

class TransactionBuilder extends BaseTransactionBuilder
    with
        TransactionBuilderOutputContoller,
        TransactionBuilderInputContoller,
        TransactionBuilderFeeContoller,
        TransactionBuilderPcztContoller,
        TransactionBuilderSignerContoller,
        TransactionBuilderExtractor {
  @override
  final TransactionBuildConfig buildConfig;
  @override
  final SaplingBuilder sapling;
  @override
  final OrchardBuilder orchard;
  @override
  final OrchardBuilder ironwood;
  @override
  final TransparentBuilder transparent;
  @override
  final int targetHeight;
  @override
  final int expiryHeight;
  @override
  final ZcashCryptoContext context;
  @override
  final ZcashNetwork network;

  @override
  final ZFeeRole feeBuilder;

  @override
  final UpgradeActivationProvider activationProvider;

  TransactionBuilder._({
    required this.buildConfig,
    required this.expiryHeight,
    required this.targetHeight,
    required this.orchard,
    required this.ironwood,
    required this.sapling,
    required this.transparent,
    required this.context,
    required this.network,
    required this.feeBuilder,
    required this.activationProvider,
  });
  factory TransactionBuilder({
    required int targetHeight,
    required TransactionBuildConfig config,
    required ZcashCryptoContext context,
    int? expiryHeight,
    ZcashNetwork network = ZcashNetwork.mainnet,
    ZFeeRole feeBuilder = const Zip317FeeRole.standard(),
    UpgradeActivationProvider activationProvider =
        const DefaultUpgradeActivationProvider(),
  }) {
    if (expiryHeight != null && expiryHeight >= targetHeight) {
      throw ZcashErrors.txBuilderFailed(
        "TransactionBuilder",
        reason: "Invalid expiry height.",
      );
    }
    final branch = activationProvider.protocolFromHeight(network, targetHeight);
    OrchardBundleVersion resolveVersion(bool isIronwood) {
      return OrchardBundleVersion.forBranch(
            branch,
            isIronwoodPool: isIronwood,
          ) ??
          (isIronwood
              ? OrchardBundleVersion.ironwoodV3
              : OrchardBundleVersion.orchardV1);
    }

    final orchard = OrchardBuilder(
      bundleType: config.orchardConfig(),
      anchor: config.orchardAnchor(),
      context: context,
      pool: OrchardValuePool.orchard,
      networkUpgrade: branch,
      bundleVersionOverride: resolveVersion(false),
    );
    final ironwood = OrchardBuilder(
      bundleType: config.orchardConfig(),
      anchor: config.ironwoodAnchor(),
      context: context,
      pool: OrchardValuePool.ironwood,
      networkUpgrade: branch,
      bundleVersionOverride: resolveVersion(true),
    );
    final sapling = SaplingBuilder(
      context: context,
      anchor: config.saplingAnchor(),
      bundleType: config.saplingConfig(),
    );
    return TransactionBuilder._(
      buildConfig: config,
      context: context,
      expiryHeight: expiryHeight ?? targetHeight + 40,
      targetHeight: targetHeight,
      network: network,
      feeBuilder: feeBuilder,
      activationProvider: activationProvider,
      orchard: orchard,
      ironwood: ironwood,
      sapling: sapling,
      transparent: TransparentBuilder(),
    );
  }
}
