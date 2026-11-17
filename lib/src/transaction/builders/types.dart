import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';
import 'package:zcash_dart/src/pczt/pczt/pczt.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/transaction/builders/utils.dart';
import 'package:zcash_dart/src/transaction/types/bundle.dart';
import 'package:zcash_dart/src/transparent/transparent.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';

sealed class TransactionBuildConfig {
  SaplingBundleType saplingConfig();
  SaplingAnchor saplingAnchor();

  OrchardBundleType orchardConfig();
  OrchardAnchor orchardAnchor();

  /// Anchor for the Ironwood pool (NU6.3 second slot). Defaults to the
  /// empty tree; override per pool like [orchardAnchor].
  OrchardAnchor ironwoodAnchor();
}

class TransactionBuildConfigStandard implements TransactionBuildConfig {
  final SaplingAnchor sapling;
  final OrchardAnchor orchard;
  final OrchardAnchor ironwood;
  TransactionBuildConfigStandard({
    SaplingAnchor? sapling,
    OrchardAnchor? orchard,
    OrchardAnchor? ironwood,
  }) : sapling = sapling ?? SaplingAnchor.emptyTree(),
       orchard = orchard ?? OrchardAnchor.emptyTree(),
       ironwood = ironwood ?? OrchardAnchor.emptyTree();

  @override
  OrchardAnchor orchardAnchor() {
    return orchard;
  }

  @override
  OrchardBundleType orchardConfig() {
    return OrchardBundleType.defaultBundle();
  }

  @override
  OrchardAnchor ironwoodAnchor() {
    return ironwood;
  }

  @override
  SaplingAnchor saplingAnchor() {
    return sapling;
  }

  @override
  SaplingBundleType saplingConfig() {
    return SaplingBundleType.defaultBundle();
  }
}

class TransactionBuildConfigCoinbase implements TransactionBuildConfig {
  @override
  OrchardAnchor orchardAnchor() {
    return OrchardAnchor.emptyTree();
  }

  @override
  OrchardAnchor ironwoodAnchor() {
    return OrchardAnchor.emptyTree();
  }

  @override
  OrchardBundleType orchardConfig() {
    return OrchardBundleTypeCoinbase();
  }

  @override
  SaplingAnchor saplingAnchor() {
    return SaplingAnchor.emptyTree();
  }

  @override
  SaplingBundleType saplingConfig() {
    return SaplingBundleTypeCoinbase();
  }
}

abstract mixin class ZFeeRole {
  ZAmount feeRequired({
    required ZcashNetwork? network,
    required int targetHeight,
    required int trasparentInputSizes,
    required int transparentOutputSizes,
    required int saplingInputCount,
    required int saplingOutputCount,
    required int orchardActionCount,
    int ironwoodActionCount = 0,
  });
}

class ZFixedFee implements ZFeeRole {
  final BigInt fee;
  const ZFixedFee(this.fee);
  @override
  ZAmount feeRequired({
    ZcashNetwork? network,
    required int targetHeight,
    required int trasparentInputSizes,
    required int transparentOutputSizes,
    required int saplingInputCount,
    required int saplingOutputCount,
    required int orchardActionCount,
    int ironwoodActionCount = 0,
  }) {
    return ZAmount(fee.asPositive);
  }
}

class Zip317FeeRole implements ZFeeRole {
  final int marginalFee;
  final int graceActions;
  final int p2pkhStandardInputSize;
  final int p2pkhStandardOutputSize;
  Zip317FeeRole._({
    required this.marginalFee,
    required this.graceActions,
    required this.p2pkhStandardInputSize,
    required this.p2pkhStandardOutputSize,
  });
  factory Zip317FeeRole({
    int marginalFee = 5000,
    int graceActions = 2,
    int p2pkhStandardInputSize = 150,
    int p2pkhStandardOutputSize = 34,
  }) {
    if (p2pkhStandardInputSize <= 0 ||
        p2pkhStandardOutputSize <= 0 ||
        marginalFee <= 0 ||
        graceActions <= 0) {
      throw CoreErrors.invalidOperationArguments(
        "Zip317FeeRole",
        reason: "Invalid fee role config.",
      );
    }

    return Zip317FeeRole._(
      marginalFee: marginalFee,
      graceActions: graceActions,
      p2pkhStandardInputSize: p2pkhStandardInputSize,
      p2pkhStandardOutputSize: p2pkhStandardOutputSize,
    );
  }
  const Zip317FeeRole.standard()
    : marginalFee = 5000,
      graceActions = 2,
      p2pkhStandardInputSize = 150,
      p2pkhStandardOutputSize = 34;

  @override
  ZAmount feeRequired({
    ZcashNetwork? network,
    int? targetHeight,
    required int trasparentInputSizes,
    required int transparentOutputSizes,
    required int saplingInputCount,
    required int saplingOutputCount,
    required int orchardActionCount,
    int ironwoodActionCount = 0,
  }) {
    final input = IntUtils.ceilDiv(
      trasparentInputSizes,
      p2pkhStandardInputSize,
    );
    final output = IntUtils.ceilDiv(
      transparentOutputSizes,
      p2pkhStandardOutputSize,
    );
    final transparent = IntUtils.max(input, output);
    final sapling = IntUtils.max(saplingInputCount, saplingOutputCount);
    // ZIP 317: each Ironwood action is charged one marginal fee, exactly
    // like an Orchard action (librustzcash `zip317.rs` supports
    // Ironwood/Orchard/Sapling/transparent).
    final action = orchardActionCount + ironwoodActionCount;
    final totalActions = transparent + sapling + action;
    return ZAmount(
      BigInt.from(marginalFee * IntUtils.max(graceActions, totalActions)),
    );
  }
}

abstract class BundleBuilder<
  BUNDLE extends Bundle<BUNDLE>,
  EXT extends ExtractedBundle<BUNDLE>,
  EXTBUNDLEPARAMS extends ExtractBundleParams,
  PCZT extends PcztBundle<BUNDLE, EXT, EXTBUNDLEPARAMS, PCZT>,
  BUNDLEDATA extends Object
> {
  /// Computes the net ZAmount balance (inputs minus outputs) of the bundle.
  ZAmount valueBalance();
  PcztBundleWithMetadata<BUNDLE, EXT, EXTBUNDLEPARAMS, PCZT> toPczt();
  BundleWithMetadata<BUNDLE, BUNDLEDATA>? build();
}

class BundleMetadata {
  final List<int> spendIndices;
  final List<int> outputIndices;

  final List<int> changeSpendIndices;
  BundleMetadata({
    List<int> spendIndices = const [],
    List<int> outputIndices = const [],
    List<int> changeSpendIndices = const [],
  }) : spendIndices = spendIndices.immutable,
       outputIndices = outputIndices.immutable,
       changeSpendIndices = changeSpendIndices.immutable;
}

class PcztBundleWithMetadata<
  BUNDLE extends Bundle<BUNDLE>,
  EXT extends ExtractedBundle<BUNDLE>,
  EXTBUNDLEPARAMS extends ExtractBundleParams,

  PCZT extends PcztBundle<BUNDLE, EXT, EXTBUNDLEPARAMS, PCZT>
> {
  final PCZT bundle;
  final BundleMetadata metadata;
  const PcztBundleWithMetadata({required this.metadata, required this.bundle});
  PcztBundleWithMetadata<BUNDLE, EXT, EXTBUNDLEPARAMS, PCZT> clone() =>
      PcztBundleWithMetadata(bundle: bundle.clone(), metadata: metadata);
}

class BundleWithMetadata<
  BUNDLE extends Bundle<BUNDLE>,
  BUNDLEDATA extends Object
> {
  final BUNDLE bundle;
  final BUNDLEDATA data;
  final BundleMetadata? metadata;
  const BundleWithMetadata({
    this.metadata,
    required this.bundle,
    required this.data,
  });
}

sealed class TransactionOutputTarget<RECIPIENT extends Object> {
  final RECIPIENT recipient;
  const TransactionOutputTarget._({required this.recipient});

  factory TransactionOutputTarget({String? address, ZcashAddress? zAddress}) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
      address: address,
      zAddress: zAddress,
    )) {
      throw ZcashErrors.txBuilderFailed(
        "TransactionOutputTarget",
        reason: "Exactly one address must be provided.",
      );
    }
    zAddress ??= ZcashAddress(address ?? '');
    final orchard = zAddress.tryToOrchardAddress();

    if (orchard != null) {
      return TransactionOutputTarget.orchard(orchardAddress: orchard);
    }
    final sapling = zAddress.tryToSaplingPaymentAddress();
    if (sapling != null) {
      return TransactionOutputTarget.sapling(paymentAddress: sapling);
    }

    final transparent = zAddress.tryToP2pkh() ?? zAddress.tryToP2sh();
    if (transparent != null) {
      return TransactionOutputTarget.transparent(transparent: transparent);
    }
    throw ZcashErrors.txBuilderFailed(
      "TransactionOutputTarget",
      reason:
          'The provided address is not a valid Orchard, Sapling or transparent address.',
    );
  }
  factory TransactionOutputTarget.transparent({
    ZcashTransparentAddress? transparent,
    String? address,
    ZcashAddress? zAddress,
  }) {
    return TransparentOutputTarget(
      address: address,
      transparent: transparent,
      zAddress: zAddress,
    ).cast();
  }
  factory TransactionOutputTarget.orchard({
    OrchardAddress? orchardAddress,
    String? address,
    ZcashAddress? zAddress,
    OrchardOutgoingViewingKey? ovk,
  }) {
    return OrchardOutputTarget(
      address: address,
      orchardAddress: orchardAddress,
      zAddress: zAddress,
      ovk: ovk,
    ).cast();
  }

  factory TransactionOutputTarget.sapling({
    SaplingPaymentAddress? paymentAddress,
    String? address,
    ZcashAddress? zAddress,
    SaplingOutgoingViewingKey? ovk,
  }) {
    return SaplingOutputTarget(
      address: address,
      paymentAddress: paymentAddress,
      zAddress: zAddress,
      ovk: ovk,
    ).cast();
  }

  factory TransactionOutputTarget.shield({
    String? address,
    ZcashAddress? zAddress,
  }) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
      address: address,
      zAddress: zAddress,
    )) {
      throw ZcashErrors.txBuilderFailed(
        "TransactionOutputTarget",
        reason: "Exactly one address must be provided.",
      );
    }
    zAddress ??= ZcashAddress(address ?? '');
    final orchard = zAddress.tryToOrchardAddress();

    if (orchard != null) {
      return TransactionOutputTarget.orchard(orchardAddress: orchard);
    }
    final sapling = zAddress.tryToSaplingPaymentAddress();
    if (sapling != null) {
      return TransactionOutputTarget.sapling(paymentAddress: sapling);
    }
    throw ZcashErrors.txBuilderFailed(
      "TransactionOutputTarget",
      reason: 'The provided address is not a valid Orchard or Sapling address.',
    );
  }
  T cast<T extends TransactionOutputTarget>() {
    if (this is! T) {
      throw BuError(
        DefaultErrorType.castFailed,
        "Failed to cast value",
        details: {"expected": "T", "value": runtimeType.toString()},
      );
    }
    return this as T;
  }
}

class SaplingOutputTarget
    extends TransactionOutputTarget<SaplingPaymentAddress> {
  final SaplingOutgoingViewingKey? ovk;
  const SaplingOutputTarget._({required super.recipient, this.ovk}) : super._();
  factory SaplingOutputTarget({
    SaplingPaymentAddress? paymentAddress,
    String? address,
    ZcashAddress? zAddress,
    SaplingOutgoingViewingKey? ovk,
  }) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
      address: address,
      zAddress: zAddress,
      protocolAddr: paymentAddress,
    )) {
      throw ZcashErrors.txBuilderFailed(
        "SaplingOutputTarget",
        reason: "Exactly one address must be provided.",
      );
    }
    if (paymentAddress == null) {
      zAddress ??= ZcashAddress(address ?? '');
      paymentAddress = zAddress.tryToSaplingPaymentAddress();
      if (paymentAddress == null) {
        throw ZcashErrors.txBuilderFailed(
          "SaplingOutputTarget",
          reason:
              "The provided address cannot be converted to a valid sapling address",
        );
      }
    }
    return SaplingOutputTarget._(recipient: paymentAddress, ovk: ovk);
  }
}

class OrchardOutputTarget extends TransactionOutputTarget<OrchardAddress> {
  final OrchardOutgoingViewingKey? ovk;
  const OrchardOutputTarget._({required super.recipient, this.ovk}) : super._();
  factory OrchardOutputTarget({
    OrchardAddress? orchardAddress,
    String? address,
    ZcashAddress? zAddress,
    OrchardOutgoingViewingKey? ovk,
  }) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
      address: address,
      zAddress: zAddress,
      protocolAddr: orchardAddress,
    )) {
      throw ZcashErrors.txBuilderFailed(
        "OrchardOutputTarget",
        reason: "Exactly one address must be provided.",
      );
    }
    if (orchardAddress == null) {
      zAddress ??= ZcashAddress(address ?? '');
      orchardAddress = zAddress.tryToOrchardAddress();
      if (orchardAddress == null) {
        throw ZcashErrors.txBuilderFailed(
          "OrchardOutputTarget",
          reason:
              "The provided address cannot be converted to a valid orchard address",
        );
      }
    }
    return OrchardOutputTarget._(recipient: orchardAddress, ovk: ovk);
  }
}

/// Output target for the Ironwood pool (NU6.3). Same address type as
/// the Orchard pool (Ironwood notes are Orchard-shaped, v3); pool
/// membership is selected by the target type. Use this for
/// cross-address transfers, which are forbidden in the Orchard pool
/// under NU6.3.
class IronwoodOutputTarget extends TransactionOutputTarget<OrchardAddress> {
  final OrchardOutgoingViewingKey? ovk;
  const IronwoodOutputTarget._({required super.recipient, this.ovk})
    : super._();
  factory IronwoodOutputTarget({
    OrchardAddress? orchardAddress,
    String? address,
    ZcashAddress? zAddress,
    OrchardOutgoingViewingKey? ovk,
  }) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
      address: address,
      zAddress: zAddress,
      protocolAddr: orchardAddress,
    )) {
      throw ZcashErrors.txBuilderFailed(
        "IronwoodOutputTarget",
        reason: "Exactly one address must be provided.",
      );
    }
    if (orchardAddress == null) {
      zAddress ??= ZcashAddress(address ?? '');
      orchardAddress = zAddress.tryToOrchardAddress();
      if (orchardAddress == null) {
        throw ZcashErrors.txBuilderFailed(
          "IronwoodOutputTarget",
          reason:
              "The provided address cannot be converted to a valid orchard address",
        );
      }
    }
    return IronwoodOutputTarget._(recipient: orchardAddress, ovk: ovk);
  }
}

class TransparentOutputTarget
    extends TransactionOutputTarget<BaseTransparentOutputInfo> {
  const TransparentOutputTarget._({required super.recipient}) : super._();
  factory TransparentOutputTarget.opReturn(TransparentNullDataOutput output) {
    return TransparentOutputTarget._(recipient: output);
  }
  factory TransparentOutputTarget({
    ZcashTransparentAddress? transparent,
    String? address,
    ZcashAddress? zAddress,
  }) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
      address: address,
      zAddress: zAddress,
      protocolAddr: transparent,
    )) {
      throw ZcashErrors.txBuilderFailed(
        "TransparentOutputTarget",
        reason: "Exactly one address must be provided.",
      );
    }
    if (transparent == null) {
      zAddress ??= ZcashAddress(address ?? '');
      transparent = zAddress.tryToP2pkh() ?? zAddress.tryToP2sh();
      if (transparent == null) {
        throw ZcashErrors.txBuilderFailed(
          "TransparentOutputTarget",
          reason:
              "The provided address cannot be converted to a valid transparent address",
        );
      }
    }
    return TransparentOutputTarget._(
      recipient: TransparentSpendableOutput(
        address: transparent,
        value: BigInt.zero,
      ),
    );
  }
}

class PcztWithMetadata {
  final Pczt pczt;
  final BundleMetadata orchard;
  final BundleMetadata sapling;

  final BundleMetadata ironwood;
  const PcztWithMetadata({
    required this.pczt,
    required this.orchard,
    required this.sapling,
    required this.ironwood,
  });
  PcztWithMetadata clone() {
    return PcztWithMetadata(
      pczt: pczt.clone(),
      orchard: orchard,
      sapling: sapling,
      ironwood: ironwood,
    );
  }
}
