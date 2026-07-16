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

  TransactionBuilder._({
    required this.buildConfig,
    required this.expiryHeight,
    required this.targetHeight,
    required this.orchard,
    required this.sapling,
    required this.transparent,
    required this.context,
    required this.network,
    required this.feeBuilder,
  });
  factory TransactionBuilder({
    required int targetHeight,
    required TransactionBuildConfig config,
    required ZcashCryptoContext context,
    int? expiryHeight,
    ZcashNetwork network = ZcashNetwork.mainnet,
    ZFeeRole feeBuilder = const Zip317FeeRole.standard(),
  }) {
    if (expiryHeight != null && expiryHeight >= targetHeight) {
      throw TransactionBuilderException.failed(
        "TransactionBuilder",
        reason: "Invalid expiry height.",
      );
    }
    final orchard = OrchardBuilder(
      bundleType: config.orchardConfig(),
      anchor: config.orchardAnchor(),
      context: context,
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
      orchard: orchard,
      sapling: sapling,
      transparent: TransparentBuilder(),
    );
  }
}
