import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/transaction/bundle.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';
import 'package:zcash_dart/src/sprout/transaction/bundle.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/transaction/bundle.dart';

class TransactionData with LayoutSerializable {
  final TxVersion version;
  final ZcashNetworkProtocol? consensusBranchId;
  final int locktime;
  final int expiryHeight;
  final TransparentBundle? transparentBundle;
  final SproutBundle? sproutBundle;
  final SaplingBundle? saplingBundle;
  final OrchardBundle? orchardBundle;
  final OrchardBundle? ironwoodBundle;

  const TransactionData({
    required this.version,
    required this.consensusBranchId,
    required this.locktime,
    required this.expiryHeight,
    this.transparentBundle,
    this.sproutBundle,
    this.saplingBundle,
    this.orchardBundle,
    this.ironwoodBundle,
  });
  factory TransactionData.deserialize(List<int> bytes) {
    final version = TxVersion.deserialize(bytes);
    final decode = LayoutSerializable.deserialize(
      bytes: bytes,
      layout: switch (version.type) {
        TxVersionType.v5 => layoutV5(),
        TxVersionType.v6 => layoutV6(),
        _ => layout(),
      },
    );
    return TransactionData.deserializeJson(decode);
  }
  factory TransactionData.deserializeJson(Map<String, dynamic> json) {
    final sBindingSig = json
        .valueTo<SaplingBundleAuthorization?, Map<String, dynamic>>(
          key: "binding_sig",
          parse: (v) => SaplingBundleAuthorization.deserializeJson(v),
        );
    final consensusBranchId = json.valueTo<ZcashNetworkProtocol?, int>(
      key: "consensus_branch_id",
      parse: (v) => ZcashNetworkProtocol.fromId(v),
    );
    final branch = consensusBranchId;
    OrchardBundleVersion orchardVersion = OrchardBundleVersion.orchardV1;
    OrchardBundleVersion ironwoodVersion = OrchardBundleVersion.ironwoodV3;
    if (branch != null) {
      orchardVersion =
          OrchardBundleVersion.forBranch(branch) ??
          OrchardBundleVersion.orchardV1;
      ironwoodVersion =
          OrchardBundleVersion.forBranch(branch, isIronwoodPool: true) ??
          OrchardBundleVersion.ironwoodV3;
    }
    return TransactionData(
      version: TxVersion.deserializeJson(json.valueAs("version")),
      consensusBranchId: consensusBranchId,
      locktime: json.valueAs("lock_time"),
      expiryHeight: json.valueAs("expiry_height"),
      transparentBundle: TransparentBundle.deserializeJson(
        json.valueAs("transparent_bundle"),
      ),
      sproutBundle: json.valueTo<SproutBundle?, Map<String, dynamic>>(
        key: "sprout_bundle",
        parse: (v) => SproutBundle.deserializeJson(v),
      ),
      saplingBundle: json
          .valueTo<SaplingBundle?, Map<String, dynamic>>(
            key: "sapling_bundle",
            parse: (v) => SaplingBundle.deserializeJson(v),
          )
          ?.copyWith(authorization: sBindingSig),
      orchardBundle: json.valueTo<OrchardBundle?, Map<String, dynamic>>(
        key: "orchard_bundle",
        parse: (v) => OrchardBundle.deserializeJson(v, orchardVersion),
      ),
      ironwoodBundle: json.valueTo<OrchardBundle?, Map<String, dynamic>>(
        key: "ironwood_bundle",
        parse: (v) => OrchardBundle.deserializeJson(v, ironwoodVersion),
      ),
    );
  }
  static Layout<Map<String, dynamic>> layoutV5({String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder<Map<String, dynamic>, LayoutRepository>(
        layout: (property, _) => TxVersion.layout(property: property),
        property: 'version',
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) => LayoutConst.u32(property: property),
        property: 'consensus_branch_id',
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) => LayoutConst.u32(property: property),
        property: 'lock_time',
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          return LayoutConst.u32(property: property);
        },
        property: 'expiry_height',
      ),
      LazyStructLayoutBuilder(
        layout:
            (property, params) => TransparentBundle.layout(property: property),
        property: "transparent_bundle",
      ),
      LazyStructLayoutBuilder<Map<String, dynamic>?, LayoutRepository>(
        layout: (property, params) {
          if (params.action.isEncode &&
              !params.sourceOrResult.hasValue("sapling_bundle")) {
            return LayoutConst.optional<Map<String, dynamic>>(
              LayoutConst.noArgs(),
              discriminator: LayoutConst.u16(),
            );
          }
          return SaplingBundle.layoutV5(property: property);
        },
        property: 'sapling_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
            layoutResult != null && layoutResult.containsKey("binding_sig"),
          );
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
              LayoutConst.noArgs(),
            );
          }
          return OrchardBundle.layout(property: property);
        },
        property: 'orchard_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
            layoutResult != null &&
                layoutResult.containsKey("binding_signature"),
          );
          if (layoutResult == null) return null;
          if (!layoutResult.hasValue("binding_signature")) {
            return null;
          }
          return layoutResult;
        },
      ),
    ], property: property);
  }

  static Layout<Map<String, dynamic>> layoutV6({String? property}) {
    // V6 wire format mirrors V5 header + transparent + sapling,
    // followed by two Orchard slots: orchard then ironwood.
    // Mirrors `write_v6` / `read_v6` in librustzcash.
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder<Map<String, dynamic>, LayoutRepository>(
        layout: (property, _) => TxVersion.layout(property: property),
        property: 'version',
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) => LayoutConst.u32(property: property),
        property: 'consensus_branch_id',
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) => LayoutConst.u32(property: property),
        property: 'lock_time',
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          return LayoutConst.u32(property: property);
        },
        property: 'expiry_height',
      ),
      LazyStructLayoutBuilder(
        layout:
            (property, params) => TransparentBundle.layout(property: property),
        property: "transparent_bundle",
      ),
      LazyStructLayoutBuilder<Map<String, dynamic>?, LayoutRepository>(
        layout: (property, params) {
          if (params.action.isEncode &&
              !params.sourceOrResult.hasValue("sapling_bundle")) {
            return LayoutConst.optional<Map<String, dynamic>>(
              LayoutConst.noArgs(),
              discriminator: LayoutConst.u16(),
            );
          }
          return SaplingBundle.layoutV5(property: property);
        },
        property: 'sapling_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
            layoutResult != null && layoutResult.containsKey("binding_sig"),
          );
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
              LayoutConst.noArgs(),
            );
          }
          return OrchardBundle.layout(property: property);
        },
        property: 'orchard_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
            layoutResult != null &&
                layoutResult.containsKey("binding_signature"),
          );
          if (layoutResult == null) return null;
          if (!layoutResult.hasValue("binding_signature")) {
            return null;
          }
          return layoutResult;
        },
      ),
      LazyStructLayoutBuilder<Map<String, dynamic>?, LayoutRepository>(
        layout: (property, params) {
          if (params.action.isEncode &&
              !params.sourceOrResult.hasValue("ironwood_bundle")) {
            return LayoutConst.optional<Map<String, dynamic>>(
              LayoutConst.noArgs(),
            );
          }
          return OrchardBundle.layout(property: property);
        },
        property: 'ironwood_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
            layoutResult != null &&
                layoutResult.containsKey("binding_signature"),
          );
          if (layoutResult == null) return null;
          if (!layoutResult.hasValue("binding_signature")) {
            return null;
          }
          return layoutResult;
        },
      ),
    ], property: property);
  }

  static Layout<Map<String, dynamic>> layout({
    TxVersion? txVersion,
    String? property,
  }) {
    TxVersion getTxVersionOrError({
      BuError err = ZcashErrors.txSerializationUnexpected,
    }) {
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
        layout:
            (property, params) => TransparentBundle.layout(property: property),
        property: "transparent_bundle",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) => LayoutConst.u32(property: property),
        property: 'lock_time',
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          final version = getTxVersionOrError();
          if (version.hasOverwinter()) {
            return LayoutConst.u32(property: property);
          }
          return LayoutConst.none(property: property);
        },
        property: 'expiry_height',
      ),
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
                _ => SproutProofType.pHGR,
              },
              property: property,
            );
          }
          return LayoutConst.none(property: property);
        },
        property: 'sprout_bundle',
        finalizeDecode: (layoutResult, structResult, repository) {
          assert(
            layoutResult == null || layoutResult.containsKey("joinsplits"),
          );
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
              final hasBinding = params.sourceOrResult.hasValue("binding_sig");
              if (hasBinding) {
                return SaplingBundleAuthorization.layout(property: property);
              }
              return LayoutConst.none();
            }
            final saplingData = params.sourceOrResult
                .valueAsMap<Map<String, dynamic>?>("sapling_bundle");
            if (saplingData != null) {
              final shieldedSpends = saplingData.valueAsList<List>(
                "shielded_spends",
              );
              final shieldedOutputs = saplingData.valueAsList<List>(
                "shielded_outputs",
              );
              if (shieldedSpends.isNotEmpty || shieldedOutputs.isNotEmpty) {
                return SaplingBundleAuthorization.layout(property: property);
              }
            }
          }
          return LayoutConst.none(property: property);
        },
        property: 'binding_sig',
      ),
    ], property: property);
  }

  TransactionData copyWith({
    TxVersion? version,
    ZcashNetworkProtocol? consensusBranchId,
    int? locktime,
    int? expiryHeight,
    TransparentBundle? transparentBundle,
    SproutBundle? sproutBundle,
    SaplingBundle? saplingBundle,
    OrchardBundle? orchardBundle,
    OrchardBundle? ironwoodBundle,
  }) {
    return TransactionData(
      version: version ?? this.version,
      consensusBranchId: consensusBranchId ?? this.consensusBranchId,
      locktime: locktime ?? this.locktime,
      expiryHeight: expiryHeight ?? this.expiryHeight,
      orchardBundle: orchardBundle ?? this.orchardBundle,
      ironwoodBundle: ironwoodBundle ?? this.ironwoodBundle,
      saplingBundle: saplingBundle ?? this.saplingBundle,
      sproutBundle: sproutBundle ?? this.sproutBundle,
      transparentBundle: transparentBundle ?? this.transparentBundle,
    );
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
      "ironwood_bundle": ironwoodBundle?.toSerializeJson(),
      "consensus_branch_id": consensusBranchId?.branchId,
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    if (version.type == TxVersionType.v5) {
      return layoutV5(property: property);
    }
    if (version.type == TxVersionType.v6) {
      return layoutV6(property: property);
    }
    return layout(txVersion: version, property: property);
  }

  ZcashTxId toTxId() {
    if (version.type == TxVersionType.v5 || version.type == TxVersionType.v6) {
      return TxIdDigester.txToTxId(this);
    }
    return ZcashTxId(QuickCrypto.sha256Hash(toSerializeBytes()));
  }

  TxDigestsPart toTxDeigest() => TxIdDigester.txToDigest(this);
}

class ZcashTransaction {
  final ZcashTxId txId;
  final TransactionData transactionData;
  const ZcashTransaction({required this.txId, required this.transactionData});
}
