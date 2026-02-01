import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';
import 'package:zcash_dart/src/pczt/pczt/pczt.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/transaction/builders/exception.dart';
import 'package:zcash_dart/src/transaction/builders/utils.dart';
import 'package:zcash_dart/src/transaction/types/bundle.dart';
import 'package:zcash_dart/src/transparent/transparent.dart';
import 'package:zcash_dart/src/value/value.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/orchard/builder/builder.dart';
import 'package:zcash_dart/src/sapling/builder/builder.dart';

sealed class TransactionBuildConfig {
  SaplingBundleType saplingConfig();
  SaplingAnchor saplingAnchor();

  OrchardBundleType orchardConfig();
  OrchardAnchor orchardAnchor();
}

class TransactionBuildConfigStandard implements TransactionBuildConfig {
  final SaplingAnchor sapling;
  final OrchardAnchor orchard;
  TransactionBuildConfigStandard(
      {SaplingAnchor? sapling, OrchardAnchor? orchard})
      : sapling = sapling ?? SaplingAnchor.emptyTree(),
        orchard = orchard ?? OrchardAnchor.emptyTree();

  @override
  OrchardAnchor orchardAnchor() {
    return orchard;
  }

  @override
  OrchardBundleType orchardConfig() {
    return OrchardBundleType.defaultBundle();
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
  ZAmount feeRequired(
      {required ZCashNetwork? network,
      required int targetHeight,
      required int trasparentInputSizes,
      required int transparentOutputSizes,
      required int saplingInputCount,
      required int saplingOutputCount,
      required int orchardActionCount});
}

class ZFixedFee implements ZFeeRole {
  final BigInt fee;
  const ZFixedFee(this.fee);
  @override
  ZAmount feeRequired(
      {ZCashNetwork? network,
      required int targetHeight,
      required int trasparentInputSizes,
      required int transparentOutputSizes,
      required int saplingInputCount,
      required int saplingOutputCount,
      required int orchardActionCount}) {
    return ZAmount(fee.asPositive);
  }
}

class Zip317FeeRole implements ZFeeRole {
  final int marginalFee;
  final int graceActions;
  final int p2pkhStandardInputSize;
  final int p2pkhStandardOutputSize;
  Zip317FeeRole._(
      {required this.marginalFee,
      required this.graceActions,
      required this.p2pkhStandardInputSize,
      required this.p2pkhStandardOutputSize});
  factory Zip317FeeRole({
    int? marginalFee,
    int? graceActions,
    int? p2pkhStandardInputSize,
    int? p2pkhStandardOutputSize,
  }) {
    if (p2pkhStandardInputSize == 0 || p2pkhStandardOutputSize == 0) {
      throw ArgumentException.invalidOperationArguments("Zip317FeeRole",
          reason: "Invalid fee role config");
    }
    return Zip317FeeRole._(
        marginalFee: (marginalFee ?? 5000).asPositive,
        graceActions: (graceActions ?? 2).asPositive,
        p2pkhStandardInputSize: (p2pkhStandardInputSize ?? 150).asPositive,
        p2pkhStandardOutputSize: (p2pkhStandardOutputSize ?? 34).asPositive);
  }
  const Zip317FeeRole.standard()
      : marginalFee = 5000,
        graceActions = 2,
        p2pkhStandardInputSize = 150,
        p2pkhStandardOutputSize = 34;

  @override
  ZAmount feeRequired(
      {ZCashNetwork? network,
      required int targetHeight,
      required int trasparentInputSizes,
      required int transparentOutputSizes,
      required int saplingInputCount,
      required int saplingOutputCount,
      required int orchardActionCount}) {
    final input = trasparentInputSizes ~/ p2pkhStandardInputSize;
    final output = transparentOutputSizes ~/ p2pkhStandardOutputSize;
    final transparent = IntUtils.max(input, output);
    final sapling = IntUtils.max(saplingInputCount, saplingOutputCount);
    final action = orchardActionCount;
    final totalActions = transparent + sapling + action;
    return ZAmount(
        BigInt.from(marginalFee * IntUtils.max(graceActions, totalActions)));
  }
}

abstract class BundleBuilder<
    BUNDLE extends Bundle<BUNDLE>,
    EXT extends ExtractedBundle<BUNDLE>,
    PCZT extends PcztBundle<BUNDLE, EXT, PCZT>,
    BUNDLEDATA extends Object> {
  /// Computes the net ZAmount balance (inputs minus outputs) of the bundle.
  ZAmount valueBalance();
  PcztBundleWithMetadata<BUNDLE, EXT, PCZT> toPczt();
  BundleWithMetadata<BUNDLE, BUNDLEDATA>? build();
}

class BundleMetadata {
  final List<int> spendIndices;
  final List<int> outputIndices;
  BundleMetadata(
      {List<int> spendIndices = const [], List<int> outputIndices = const []})
      : spendIndices = spendIndices.immutable,
        outputIndices = outputIndices.immutable;
}

class PcztBundleWithMetadata<
    BUNDLE extends Bundle<BUNDLE>,
    EXT extends ExtractedBundle<BUNDLE>,
    PCZT extends PcztBundle<BUNDLE, EXT, PCZT>> {
  final PCZT bundle;
  final BundleMetadata metadata;
  const PcztBundleWithMetadata({required this.metadata, required this.bundle});
  PcztBundleWithMetadata<BUNDLE, EXT, PCZT> clone() =>
      PcztBundleWithMetadata(bundle: bundle.clone(), metadata: metadata);
}

class BundleWithMetadata<BUNDLE extends Bundle<BUNDLE>,
    BUNDLEDATA extends Object> {
  final BUNDLE bundle;
  final BUNDLEDATA data;
  final BundleMetadata? metadata;
  const BundleWithMetadata(
      {this.metadata, required this.bundle, required this.data});
}

sealed class TransactionOutputTarget<RECIPIENT extends Object> {
  final RECIPIENT recipient;
  const TransactionOutputTarget._({required this.recipient});

  factory TransactionOutputTarget({String? address, ZCashAddress? zAddress}) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
        address: address, zAddress: zAddress)) {
      throw TransactionBuilderException.failed("TransactionOutputTarget",
          reason: "Exactly one address must be provided.");
    }
    zAddress ??= ZCashAddress(address ?? '');
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
    throw TransactionBuilderException.failed(
      "TransactionOutputTarget",
      reason:
          'The provided address is not a valid Orchard, Sapling or transparent address.',
    );
  }
  factory TransactionOutputTarget.transparent(
      {ZCashTransparentAddress? transparent,
      String? address,
      ZCashAddress? zAddress}) {
    return TransparentOutputTarget(
            address: address, transparent: transparent, zAddress: zAddress)
        .cast();
  }
  factory TransactionOutputTarget.orchard(
      {OrchardAddress? orchardAddress,
      String? address,
      ZCashAddress? zAddress,
      OrchardOutgoingViewingKey? ovk}) {
    return OrchardOutputTarget(
            address: address,
            orchardAddress: orchardAddress,
            zAddress: zAddress,
            ovk: ovk)
        .cast();
  }

  factory TransactionOutputTarget.sapling(
      {SaplingPaymentAddress? paymentAddress,
      String? address,
      ZCashAddress? zAddress,
      SaplingOutgoingViewingKey? ovk}) {
    return SaplingOutputTarget(
            address: address,
            paymentAddress: paymentAddress,
            zAddress: zAddress,
            ovk: ovk)
        .cast();
  }

  factory TransactionOutputTarget.shield(
      {String? address, ZCashAddress? zAddress}) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
        address: address, zAddress: zAddress)) {
      throw TransactionBuilderException.failed("TransactionOutputTarget",
          reason: "Exactly one address must be provided.");
    }
    zAddress ??= ZCashAddress(address ?? '');
    final orchard = zAddress.tryToOrchardAddress();

    if (orchard != null) {
      return TransactionOutputTarget.orchard(orchardAddress: orchard);
    }
    final sapling = zAddress.tryToSaplingPaymentAddress();
    if (sapling != null) {
      return TransactionOutputTarget.sapling(paymentAddress: sapling);
    }
    throw TransactionBuilderException.failed(
      "TransactionOutputTarget",
      reason: 'The provided address is not a valid Orchard or Sapling address.',
    );
  }
  T cast<T extends TransactionOutputTarget>() {
    if (this is! T) throw CastFailedException(value: this);
    return this as T;
  }
}

class SaplingOutputTarget
    extends TransactionOutputTarget<SaplingPaymentAddress> {
  final SaplingOutgoingViewingKey? ovk;
  const SaplingOutputTarget._({required super.recipient, this.ovk}) : super._();
  factory SaplingOutputTarget(
      {SaplingPaymentAddress? paymentAddress,
      String? address,
      ZCashAddress? zAddress,
      SaplingOutgoingViewingKey? ovk}) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
        address: address, zAddress: zAddress, protocolAddr: paymentAddress)) {
      throw TransactionBuilderException.failed("SaplingOutputTarget",
          reason: "Exactly one address must be provided.");
    }
    if (paymentAddress == null) {
      zAddress ??= ZCashAddress(address ?? '');
      paymentAddress = zAddress.tryToSaplingPaymentAddress();
      if (paymentAddress == null) {
        throw TransactionBuilderException.failed("SaplingOutputTarget",
            reason:
                "The provided address cannot be converted to a valid sapling address");
      }
    }
    return SaplingOutputTarget._(recipient: paymentAddress, ovk: ovk);
  }
}

class OrchardOutputTarget extends TransactionOutputTarget<OrchardAddress> {
  final OrchardOutgoingViewingKey? ovk;
  const OrchardOutputTarget._({required super.recipient, this.ovk}) : super._();
  factory OrchardOutputTarget(
      {OrchardAddress? orchardAddress,
      String? address,
      ZCashAddress? zAddress,
      OrchardOutgoingViewingKey? ovk}) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
        address: address, zAddress: zAddress, protocolAddr: orchardAddress)) {
      throw TransactionBuilderException.failed("OrchardOutputTarget",
          reason: "Exactly one address must be provided.");
    }
    if (orchardAddress == null) {
      zAddress ??= ZCashAddress(address ?? '');
      orchardAddress = zAddress.tryToOrchardAddress();
      if (orchardAddress == null) {
        throw TransactionBuilderException.failed("OrchardOutputTarget",
            reason:
                "The provided address cannot be converted to a valid orchard address");
      }
    }
    return OrchardOutputTarget._(recipient: orchardAddress, ovk: ovk);
  }
}

class TransparentOutputTarget
    extends TransactionOutputTarget<BaseTransparentOutputInfo> {
  const TransparentOutputTarget._({required super.recipient}) : super._();
  factory TransparentOutputTarget.opReturn(List<int> data) {
    return TransparentOutputTarget._(
        recipient: TransparentNullDataOutput(data));
  }
  factory TransparentOutputTarget(
      {ZCashTransparentAddress? transparent,
      String? address,
      ZCashAddress? zAddress}) {
    if (!TransactionBuilderUtils.isValidOutputAddressParams(
        address: address, zAddress: zAddress, protocolAddr: transparent)) {
      throw TransactionBuilderException.failed("TransparentOutputTarget",
          reason: "Exactly one address must be provided.");
    }
    if (transparent == null) {
      zAddress ??= ZCashAddress(address ?? '');
      transparent = zAddress.tryToP2pkh() ?? zAddress.tryToP2sh();
      if (transparent == null) {
        throw TransactionBuilderException.failed("TransparentOutputTarget",
            reason:
                "The provided address cannot be converted to a valid transparent address");
      }
    }
    return TransparentOutputTarget._(
        recipient: TransparentSpendableOutput(
            address: transparent, value: BigInt.zero));
  }
}

class PcztWithMetadata {
  final Pczt pczt;
  final BundleMetadata orchard;
  final BundleMetadata sapling;
  const PcztWithMetadata(
      {required this.pczt, required this.orchard, required this.sapling});
  PcztWithMetadata clone() {
    return PcztWithMetadata(
        pczt: pczt.clone(), orchard: orchard, sapling: sapling);
  }
}
