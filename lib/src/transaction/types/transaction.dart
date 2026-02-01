import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/transaction/bundle.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';
import 'package:zcash_dart/src/sprout/transaction/bundle.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/transaction/bundle.dart';

class TransactionData with LayoutSerializable {
  final TxVersion version;
  final NetworkUpgrade? consensusBranchId;
  final int locktime;
  final int expiryHeight;
  final TransparentBundle? transparentBundle;
  final SproutBundle? sproutBundle;
  final SaplingBundle? saplingBundle;
  final OrchardBundle? orchardBundle;

  const TransactionData(
      {required this.version,
      required this.consensusBranchId,
      required this.locktime,
      required this.expiryHeight,
      this.transparentBundle,
      this.sproutBundle,
      this.saplingBundle,
      this.orchardBundle});
  factory TransactionData.deserialize(List<int> bytes) {
    final version = TxVersion.deserialize(bytes);
    final decode = LayoutSerializable.deserialize(
        bytes: bytes,
        layout: switch (version.type) {
          TxVersionType.v5 => layoutV5(),
          _ => layout()
        });
    return TransactionData.deserializeJson(decode);
  }
  factory TransactionData.deserializeJson(Map<String, dynamic> json) {
    final sBindingSig =
        json.valueTo<SaplingBundleAuthorization?, Map<String, dynamic>>(
            key: "binding_sig",
            parse: (v) => SaplingBundleAuthorization.deserializeJson(v));
    final consensusBranchId = json.valueTo<NetworkUpgrade?, int>(
        key: "consensus_branch_id", parse: (v) => NetworkUpgrade.fromId(v));
    return TransactionData(
        version: TxVersion.deserializeJson(json.valueAs("version")),
        consensusBranchId: consensusBranchId,
        locktime: json.valueAs("lock_time"),
        expiryHeight: json.valueAs("expiry_height"),
        transparentBundle: TransparentBundle.deserializeJson(
            json.valueAs("transparent_bundle")),
        sproutBundle: json.valueTo<SproutBundle?, Map<String, dynamic>>(
            key: "sprout_bundle",
            parse: (v) => SproutBundle.deserializeJson(v)),
        saplingBundle: json
            .valueTo<SaplingBundle?, Map<String, dynamic>>(
                key: "sapling_bundle",
                parse: (v) => SaplingBundle.deserializeJson(v))
            ?.copyWith(authorization: sBindingSig),
        orchardBundle: json.valueTo<OrchardBundle?, Map<String, dynamic>>(
            key: "orchard_bundle",
            parse: (v) => OrchardBundle.deserializeJson(v)));
  }
  static Layout<Map<String, dynamic>> layoutV5({String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder<Map<String, dynamic>, LayoutRepository>(
          layout: (property, _) => TxVersion.layout(property: property),
          property: 'version'),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.u32(property: property),
          property: 'consensus_branch_id'),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.u32(property: property),
          property: 'lock_time'),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            return LayoutConst.u32(property: property);
          },
          property: 'expiry_height'),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              TransparentBundle.layout(property: property),
          property: "transparent_bundle"),
      LazyStructLayoutBuilder<Map<String, dynamic>?, LayoutRepository>(
        layout: (property, params) {
          if (params.action.isEncode &&
              !params.sourceOrResult.hasValue("sapling_bundle")) {
            return LayoutConst.optional<Map<String, dynamic>>(
                LayoutConst.noArgs(),
                discriminator: LayoutConst.u16());
          }
          return SaplingBundle.layoutV5(property: property);
        },
        property: 'sapling_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
              layoutResult != null && layoutResult.containsKey("binding_sig"));
          if (layoutResult == null || !layoutResult.hasValue("binding_sig")) {
            return null;
          }
          return layoutResult;
        },
      ),
      LazyStructLayoutBuilder<Map<String, dynamic>?, LayoutRepository>(
        layout: (property, params) {
          if (params.action.isEncode &&
              !params.sourceOrResult.hasValue("orchard_bundle")) {
            return LayoutConst.optional<Map<String, dynamic>>(
                LayoutConst.noArgs());
          }
          return OrchardBundle.layout(property: property);
        },
        property: 'orchard_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(layoutResult != null &&
              layoutResult.containsKey("binding_signature"));
          if (layoutResult == null) return null;
          if (!layoutResult.hasValue("binding_signature")) {
            return null;
          }
          return layoutResult;
        },
      ),
    ], property: property);
  }

  static Layout<Map<String, dynamic>> layout(
      {TxVersion? txVersion, String? property}) {
    TxVersion getTxVersionOrError(
        {ZTransactionSerializationError err = ZTransactionSerializationError
            .unxpectedErrorDuringDeserialization}) {
      final version = txVersion;
      if (version == null) throw err;
      return version;
    }

    // final repository = ZTransactionLayoutRepository();
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder<Map<String, dynamic>, LayoutRepository>(
        layout: (property, _) => TxVersion.layout(property: property),
        property: 'version',
        finalizeDecode: (layoutResult, structResult, _) {
          txVersion ??= TxVersion.deserializeJson(layoutResult);
          return layoutResult;
        },
      ),
      LazyStructLayoutBuilder(
          layout: (property, params) =>
              TransparentBundle.layout(property: property),
          property: "transparent_bundle"),
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.u32(property: property),
          property: 'lock_time'),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            final version = getTxVersionOrError();
            if (version.hasOverwinter()) {
              return LayoutConst.u32(property: property);
            }
            return LayoutConst.none(property: property);
          },
          property: 'expiry_height'),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          final version = getTxVersionOrError();
          if (version.hasSapling()) {
            return SaplingBundle.layout(property: property);
          }
          return LayoutConst.none(property: property);
        },
        property: 'sapling_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          return layoutResult;
        },
      ),
      LazyStructLayoutBuilder<Map<String, dynamic>?, LayoutRepository>(
        layout: (property, params) {
          final version = getTxVersionOrError();
          if (version.hasSprout()) {
            return SproutBundle.layout(
                proof: switch (version.hasSapling()) {
                  true => SproutProofType.groth,
                  _ => SproutProofType.pHGR
                },
                property: property);
          }
          return LayoutConst.none(property: property);
        },
        property: 'sprout_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
              layoutResult == null || layoutResult.containsKey("joinsplits"));
          if (layoutResult == null) return null;
          final r = layoutResult.valueEnsureAsList("joinsplits");
          if (r.isEmpty) return null;
          return layoutResult;
        },
      ),
      LazyStructLayoutBuilder(
          layout: (property, params) {
            final version = getTxVersionOrError();
            if (version.hasSapling()) {
              if (params.action.isEncode) {
                final hasBinding =
                    params.sourceOrResult.hasValue("binding_sig");
                if (hasBinding) {
                  return SaplingBundleAuthorization.layout(property: property);
                }
                return LayoutConst.none();
              }
              final saplingData = params.sourceOrResult
                  .valueAsMap<Map<String, dynamic>?>("sapling_bundle");
              if (saplingData != null) {
                final shieldedSpends =
                    saplingData.valueAsList<List>("shielded_spends");
                final shieldedOutputs =
                    saplingData.valueAsList<List>("shielded_outputs");
                if (shieldedSpends.isNotEmpty || shieldedOutputs.isNotEmpty) {
                  return SaplingBundleAuthorization.layout(property: property);
                }
              }
            }
            return LayoutConst.none(property: property);
          },
          property: 'binding_sig'),
    ], property: property);
  }

  TransactionData copyWith(
      {TxVersion? version,
      NetworkUpgrade? consensusBranchId,
      int? locktime,
      int? expiryHeight,
      TransparentBundle? transparentBundle,
      SproutBundle? sproutBundle,
      SaplingBundle? saplingBundle,
      OrchardBundle? orchardBundle}) {
    return TransactionData(
        version: version ?? this.version,
        consensusBranchId: consensusBranchId ?? this.consensusBranchId,
        locktime: locktime ?? this.locktime,
        expiryHeight: expiryHeight ?? this.expiryHeight,
        orchardBundle: orchardBundle ?? this.orchardBundle,
        saplingBundle: saplingBundle ?? this.saplingBundle,
        sproutBundle: sproutBundle ?? this.sproutBundle,
        transparentBundle: transparentBundle ?? this.transparentBundle);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "version": version.toSerializeJson(),
      "transparent_bundle":
          (transparentBundle ?? TransparentBundle.empty()).toSerializeJson(),
      "lock_time": locktime,
      "expiry_height": expiryHeight,
      "sapling_bundle": saplingBundle?.toSerializeJson(version: version.type),
      "sprout_bundle": (sproutBundle ?? SproutBundle.empty()).toSerializeJson(),
      "binding_sig": saplingBundle?.authorization?.toSerializeJson(),
      "orchard_bundle": orchardBundle?.toSerializeJson(),
      "consensus_branch_id": consensusBranchId?.branchId
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    if (version.type == TxVersionType.v5) {
      return layoutV5(property: property);
    }
    return layout(txVersion: version, property: property);
  }

  ZCashTxId toTxId() {
    if (version.type == TxVersionType.v5) {
      return TxIdDigester.txToTxId(this);
    }
    return ZCashTxId(QuickCrypto.sha256Hash(toSerializeBytes()));
  }

  TxDigestsPart toTxDeigest() => TxIdDigester.txToDigest(this);
}

class ZCashTransaction {
  final ZCashTxId txId;
  final TransactionData transactionData;
  const ZCashTransaction({required this.txId, required this.transactionData});
}
