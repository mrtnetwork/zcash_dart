import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:zcash_dart/src/orchard/merkle/merkle.dart';
import 'package:zcash_dart/src/note/note.dart';
import 'package:zcash_dart/src/orchard/note/note.dart';
import 'package:zcash_dart/src/orchard/proof/types.dart';
import 'package:zcash_dart/src/orchard/transaction/commitment.dart';
import 'package:zcash_dart/src/transaction/types/bundle.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';
import 'package:zcash_dart/src/value/value.dart';

enum OrchardValuePool {
  orchard,
  ironwood;

  OrchardNoteVersion get noteVersion => switch (this) {
    OrchardValuePool.orchard => OrchardNoteVersion.v2,
    OrchardValuePool.ironwood => OrchardNoteVersion.v3,
  };
}

enum OrchardProtocolVersion {
  insecureV1(0),
  v2(1),
  v3(2);

  final int version;
  const OrchardProtocolVersion(this.version);

  OrchardNoteVersion get noteVersion => switch (this) {
    insecureV1 || v2 => OrchardNoteVersion.v2,
    v3 => OrchardNoteVersion.v3,
  };
}

class OrchardBundleVersion {
  final OrchardValuePool valuePool;
  final OrchardProtocolVersion protocolVersion;
  const OrchardBundleVersion({
    required this.valuePool,
    required this.protocolVersion,
  });

  static const orchardV1 = OrchardBundleVersion(
    valuePool: OrchardValuePool.orchard,
    protocolVersion: OrchardProtocolVersion.insecureV1,
  );
  static const orchardV2 = OrchardBundleVersion(
    valuePool: OrchardValuePool.orchard,
    protocolVersion: OrchardProtocolVersion.v2,
  );
  static const orchardV3 = OrchardBundleVersion(
    valuePool: OrchardValuePool.orchard,
    protocolVersion: OrchardProtocolVersion.v3,
  );
  static const ironwoodV3 = OrchardBundleVersion(
    valuePool: OrchardValuePool.ironwood,
    protocolVersion: OrchardProtocolVersion.v3,
  );

  /// Whether this bundle version permits cross-address transfers.
  /// Mirrors `BundleVersion::permits_cross_address_transfers`: everything
  /// permits them except the Orchard pool under protocol V3 (NU6.3).
  bool get permitsCrossAddressTransfers {
    return !(protocolVersion == OrchardProtocolVersion.v3 &&
        valuePool == OrchardValuePool.orchard);
  }

  /// The default flags for a bundle of this version: spends and outputs
  /// enabled, cross-address set to the least-restrictive value the
  /// version permits. Mirrors `BundleVersion::default_flags`.
  OrchardBundleFlags defaultFlags() {
    return OrchardBundleFlags(
      spendsEnabled: true,
      outputsEnabled: true,
      crossAddressEnabled: permitsCrossAddressTransfers,
    );
  }

  /// Mirrors `BranchId::orchard_protocol_revision` + pool selection.
  /// [isIronwoodPool] selects the Ironwood slot (V6 second bundle).
  static OrchardBundleVersion? forBranch(
    ZcashNetworkProtocol branch, {
    bool isIronwoodPool = false,
  }) {
    if (branch < ZcashNetworkProtocol.nu5) return null;
    if (branch < ZcashNetworkProtocol.nu6_2) {
      if (isIronwoodPool) return null;
      return orchardV1;
    }
    if (branch < ZcashNetworkProtocol.nu6_3) {
      if (isIronwoodPool) return null;
      return orchardV2;
    }
    return isIronwoodPool ? ironwoodV3 : orchardV3;
  }
}
// enum BundleVersion{

// }
class OrchardTransmittedNoteCiphertext with LayoutSerializable, Equality {
  final List<int> epkBytes;
  final List<int> encCiphertext;
  final List<int> outCiphertext;
  OrchardTransmittedNoteCiphertext({
    required List<int> epkBytes,
    required List<int> encCiphertext,
    required List<int> outCiphertext,
  }) : epkBytes =
           epkBytes
               .exc(
                 length: 32,
                 operation: "OrchardTransmittedNoteCiphertext",
                 name: "epkBytes",
                 reason: "Invalid EPK bytes length.",
               )
               .asImmutableBytes,
       encCiphertext =
           encCiphertext
               .exc(
                 length: NoteEncryptionConst.encCiphertextSize,
                 name: "encCiphertext",
                 operation: "OrchardTransmittedNoteCiphertext",
                 reason: "Invalid enc cipher text bytes length.",
               )
               .asImmutableBytes,
       outCiphertext =
           outCiphertext
               .exc(
                 length: NoteEncryptionConst.outCiphertextSize,
                 operation: "OrchardTransmittedNoteCiphertext",
                 name: "outCiphertext",
                 reason: "Invalid out cipher text bytes length.",
               )
               .asImmutableBytes;

  factory OrchardTransmittedNoteCiphertext.deserializeJson(
    Map<String, dynamic> json,
  ) {
    return OrchardTransmittedNoteCiphertext(
      epkBytes: json.valueAsBytes("epk_bytes"),
      encCiphertext: json.valueAsBytes("enc_ciphertext"),
      outCiphertext: json.valueAsBytes("out_ciphertext"),
    );
  }

  static Layout<Map<String, dynamic>> layout({
    bool pczt = false,
    String? property,
  }) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "epk_bytes"),
      if (pczt) ...[
        LayoutConst.bcsBytes(property: "enc_ciphertext"),
        LayoutConst.bcsBytes(property: "out_ciphertext"),
      ] else ...[
        LayoutConst.fixedBlobN(
          NoteEncryptionConst.encCiphertextSize,
          property: "enc_ciphertext",
        ),
        LayoutConst.fixedBlobN(
          NoteEncryptionConst.outCiphertextSize,
          property: "out_ciphertext",
        ),
      ],
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "epk_bytes": epkBytes,
      "enc_ciphertext": encCiphertext,
      "out_ciphertext": outCiphertext,
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({bool pczt = false, String? property}) {
    return layout(property: property, pczt: pczt);
  }

  @override
  List<dynamic> get variables => [epkBytes, encCiphertext, outCiphertext];
}

class OrchardAction extends OrchardShildOutput with LayoutSerializable {
  @override
  final OrchardNullifier nf;
  final RedPallasSpendPublicKey rk;
  final OrchardExtractedNoteCommitment cmx;
  final OrchardTransmittedNoteCiphertext encryptedNote;
  final OrchardValueCommitment cvNet;
  final ReddsaSignature? authorization;

  OrchardAction({
    required this.nf,
    required this.rk,
    required this.cmx,
    required this.encryptedNote,
    required this.cvNet,
    this.authorization,
  });
  factory OrchardAction.deserializeJson(Map<String, dynamic> json) {
    return OrchardAction(
      nf: OrchardNullifier.deserializeJson(json.valueAs("nf_old")),
      rk: RedPallasSpendPublicKey.deserializeJson(json.valueAs("rk")),
      cmx: OrchardExtractedNoteCommitment.deserializeJson(json.valueAs("cmx")),
      encryptedNote: OrchardTransmittedNoteCiphertext.deserializeJson(
        json.valueAs("encrypted_note"),
      ),
      cvNet: OrchardValueCommitment.deserializeJson(json.valueAs("cv_net")),
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      OrchardValueCommitment.layout(property: "cv_net"),
      Nullifier.layout(property: "nf_old"),
      RedPallasSpendPublicKey.layout(property: "rk"),
      OrchardExtractedNoteCommitment.layout(property: "cmx"),
      OrchardTransmittedNoteCiphertext.layout(property: "encrypted_note"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "cv_net": cvNet.toSerializeJson(),
      "nf_old": nf.toSerializeJson(),
      "rk": rk.toSerializeJson(),
      "cmx": cmx.toSerializeJson(),
      "encrypted_note": encryptedNote.toSerializeJson(),
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return toLayout(property: property);
  }

  OrchardAction copyWith({
    OrchardNullifier? nf,
    RedPallasSpendPublicKey? rk,
    OrchardExtractedNoteCommitment? cmx,
    OrchardTransmittedNoteCiphertext? encryptedNote,
    OrchardValueCommitment? cvNet,
    ReddsaSignature? authorization,
  }) {
    return OrchardAction(
      nf: nf ?? this.nf,
      rk: rk ?? this.rk,
      cmx: cmx ?? this.cmx,
      encryptedNote: encryptedNote ?? this.encryptedNote,
      cvNet: cvNet ?? this.cvNet,
      authorization: authorization ?? this.authorization,
    );
  }

  @override
  OrchardExtractedNoteCommitment cmstar() {
    return cmx;
  }

  @override
  List<int> cmstarBytes() {
    return cmx.toBytes();
  }

  @override
  List<int> get encCiphertext => encryptedNote.encCiphertext;

  @override
  List<int> get encCiphertextCompact => encryptedNote.encCiphertext.sublist(
    0,
    NoteEncryptionConst.compactNoteSize,
  );

  @override
  EphemeralKeyBytes get ephemeralKey =>
      EphemeralKeyBytes(encryptedNote.epkBytes);

  OrchardCircuitInstance toCircuitInstance({
    required OrchardAnchor anchor,
    required OrchardBundleFlags flags,
    required OrchardProtocolVersion version,
  }) {
    return OrchardCircuitInstance(
      anchor: anchor,
      valueCommitment: cvNet,
      nullifier: nf,
      rk: rk,
      cmx: cmx,
      enableSpend: flags.spendsEnabled,
      enableOutput: flags.outputsEnabled,
      disableCrossAddress: !flags.crossAddressEnabled,
      version: version,
    );
  }
}

class OrchardProof with LayoutSerializable {
  final BuBytes inner;
  OrchardProof(List<int> inner) : inner = inner.asImmutableBytes;

  factory OrchardProof.deserializeJson(Map<String, dynamic> json) {
    return OrchardProof(json.valueAsBytes("inner"));
  }

  static Layout<Map<String, dynamic>> layout({
    String? property,
    bool pczt = false,
  }) {
    return LayoutConst.struct([
      switch (pczt) {
        false => LayoutConst.varintVector(LayoutConst.u8(), property: "inner"),
        true => LayoutConst.bcsBytes(property: "inner"),
      },
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner};
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property, bool pczt = false}) {
    return layout(property: property, pczt: pczt);
  }

  BuBytes toBytes() => inner.clone();
}

class OrchardBundleAuthorization {
  final OrchardProof proof;
  final ReddsaSignature bindingSignature;
  const OrchardBundleAuthorization({
    required this.proof,
    required this.bindingSignature,
  });
}

class OrchardBundleFlags with LayoutSerializable, Equality {
  static const int flagSpendsEnabled = 0x01; // 1
  static const int flagOutputsEnabled = 0x02;
  static const int flagV6CrossAddressEnabled = 0x04;
  static const OrchardBundleFlags enabled = OrchardBundleFlags(
    spendsEnabled: true,
    outputsEnabled: true,
    crossAddressEnabled: true,
  );
  static const OrchardBundleFlags spendDisabled = OrchardBundleFlags(
    spendsEnabled: false,
    outputsEnabled: true,
    crossAddressEnabled: true,
  );
  static const OrchardBundleFlags outputDisabled = OrchardBundleFlags(
    spendsEnabled: true,
    outputsEnabled: false,
    crossAddressEnabled: true,
  );
  static const OrchardBundleFlags crossAddressDisabled = OrchardBundleFlags(
    spendsEnabled: true,
    outputsEnabled: true,
    crossAddressEnabled: false,
  );
  static const int flagsExpectedUnset =
      (~(flagSpendsEnabled | flagOutputsEnabled | flagV6CrossAddressEnabled)) &
      BinaryOps.mask8;

  final bool spendsEnabled;
  final bool outputsEnabled;
  final bool crossAddressEnabled;
  const OrchardBundleFlags({
    required this.spendsEnabled,
    required this.outputsEnabled,
    this.crossAddressEnabled = true,
  });

  OrchardBundleFlags copyWith({
    bool? spendsEnabled,
    bool? outputsEnabled,
    bool? crossAddressEnabled,
  }) {
    return OrchardBundleFlags(
      spendsEnabled: spendsEnabled ?? this.spendsEnabled,
      outputsEnabled: outputsEnabled ?? this.outputsEnabled,
      crossAddressEnabled: crossAddressEnabled ?? this.crossAddressEnabled,
    );
  }

  factory OrchardBundleFlags.fromByte(int value, OrchardBundleVersion version) {
    if ((value & flagsExpectedUnset) == 0) {
      final crossAddrEnabled = (value & flagV6CrossAddressEnabled) != 0;
      if (crossAddrEnabled && version.valuePool == OrchardValuePool.orchard) {
        throw ZcashErrors.orchardFailed("fromByte", reason: "Invalid flags.");
      }
      return OrchardBundleFlags(
        spendsEnabled: (value & flagSpendsEnabled) != 0,
        outputsEnabled: (value & flagOutputsEnabled) != 0,
        crossAddressEnabled:
            version.protocolVersion == OrchardProtocolVersion.v3
                ? crossAddrEnabled
                : true,
      );
    }
    throw ZcashErrors.orchardFailed("fromByte", reason: "Invalid flags.");
  }
  factory OrchardBundleFlags.deserializeJson(
    Map<String, dynamic> json, [
    OrchardBundleVersion version = OrchardBundleVersion.orchardV1,
  ]) {
    return OrchardBundleFlags.fromByte(json.valueAs("flag"), version);
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.u8(property: "flag"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  int toByte() {
    return toByteForVersion(null);
  }

  /// Version-aware flag encoding. Mirrors official `Flags::to_byte`
  /// returning `None` when unrepresentable: throws [BuError].
  /// - (Orchard, V1|V2) + cross disabled => unrepresentable (bit 2 reserved).
  /// - (Orchard, V3) + cross enabled => unrepresentable (mandated restriction).
  /// - (Ironwood, pre-V3) => unrepresentable (pool exists only at V3).
  /// With null (legacy/V5 path) the cross-address bit is never emitted;
  /// cross disabled is unrepresentable, preserving existing behavior.
  int toByteForVersion([OrchardBundleVersion? version]) {
    int value = 0;
    if (spendsEnabled) {
      value |= flagSpendsEnabled;
    }
    if (outputsEnabled) {
      value |= flagOutputsEnabled;
    }
    if (version == null) {
      if (!crossAddressEnabled) {
        throw ZcashErrors.orchardFailed(
          "toByteForVersion",
          reason: "Unrepresentable flags for pre-NU6.3 version.",
        );
      }
      return value.toU8;
    }
    final pool = version.valuePool;
    final protocol = version.protocolVersion;
    switch (pool) {
      case OrchardValuePool.orchard:
        if (protocol == OrchardProtocolVersion.v3) {
          if (crossAddressEnabled) {
            throw ZcashErrors.orchardFailed(
              "toByteForVersion",
              reason:
                  "Unrepresentable flags for Orchard pool under V3 (cross-address mandated disabled).",
            );
          }
          return value.toU8;
        }
        if (!crossAddressEnabled) {
          throw ZcashErrors.orchardFailed(
            "toByteForVersion",
            reason: "Unrepresentable flags for pre-NU6.3 version.",
          );
        }
        return value.toU8;
      case OrchardValuePool.ironwood:
        if (protocol != OrchardProtocolVersion.v3) {
          throw ZcashErrors.orchardFailed(
            "toByteForVersion",
            reason: "The Ironwood pool exists only from NU6.3 (protocol v3).",
          );
        }
        if (crossAddressEnabled) {
          value |= flagV6CrossAddressEnabled;
        }
        return value.toU8;
    }
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"flag": toByte()};
  }

  /// Serialize with explicit bundle version (required for Ironwood).
  Map<String, dynamic> toSerializeJsonForVersion(
    OrchardBundleVersion? version,
  ) {
    return {"flag": toByteForVersion(version)};
  }

  @override
  List<dynamic> get variables => [
    spendsEnabled,
    outputsEnabled,
    crossAddressEnabled,
  ];
}

class OrchardBundle with LayoutSerializable implements Bundle<OrchardBundle> {
  final List<OrchardAction> actions;
  final OrchardBundleFlags flags;
  final ZAmount balance;
  final OrchardAnchor anchor;
  final OrchardBundleAuthorization? authorization;
  final OrchardBundleVersion bundleVersion;

  const OrchardBundle({
    required this.actions,
    required this.flags,
    required this.balance,
    required this.anchor,
    required this.authorization,
    this.bundleVersion = OrchardBundleVersion.orchardV1,
  });
  factory OrchardBundle.deserializeJson(
    Map<String, dynamic> json, [
    OrchardBundleVersion version = OrchardBundleVersion.orchardV1,
  ]) {
    final signatures =
        json
            .valueEnsureAsList<Map<String, dynamic>>("signatures")
            .map(ReddsaSignature.deserializeJson)
            .toList();
    return OrchardBundle(
      actions:
          json
              .valueEnsureAsList<Map<String, dynamic>>("actions")
              .indexed
              .map(
                (e) => OrchardAction.deserializeJson(
                  e.$2,
                ).copyWith(authorization: signatures.elementAt(e.$1)),
              )
              .toList(),
      flags: OrchardBundleFlags.deserializeJson(json.valueAs("flags"), version),
      balance: ZAmount(json.valueAsBigInt("balance")),
      anchor: OrchardAnchor.deserializeJson(json.valueAs("anchor")),
      authorization: OrchardBundleAuthorization(
        proof: OrchardProof.deserializeJson(json.valueAs("proof")),
        bindingSignature: ReddsaSignature.deserializeJson(
          json.valueAs("binding_signature"),
        ),
      ),
      bundleVersion: version,
    );
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    int actions = 0;
    bool haveActions() => actions > 0;
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder<List<Map<String, dynamic>>, LayoutRepository>(
        layout:
            (property, params) => LayoutConst.varintVector(
              OrchardAction.layout(),
              property: property,
            ),
        finalizeDecode: (layoutResult, structResult, repository) {
          actions = layoutResult.length;
          return layoutResult;
        },
        finalizeEncode: (source, structSource, repository) {
          actions = source.length;
        },
        property: "actions",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          if (!haveActions()) return LayoutConst.none(property: property);
          return OrchardBundleFlags.layout(property: property);
        },
        property: "flags",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          if (!haveActions()) return LayoutConst.none(property: property);
          return LayoutConst.i64(property: property);
        },
        property: "balance",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          if (!haveActions()) return LayoutConst.none(property: property);
          return OrchardAnchor.layout(property: property);
        },
        property: "anchor",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          if (!haveActions()) return LayoutConst.none(property: property);
          return OrchardProof.layout(property: property);
        },
        property: "proof",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          return LayoutConst.array(
            ReddsaSignature.layout(),
            actions,
            property: property,
          );
        },
        property: "signatures",
      ),
      LazyStructLayoutBuilder(
        layout: (property, params) {
          if (!haveActions()) return LayoutConst.none(property: property);
          return ReddsaSignature.layout(property: property);
        },
        property: "binding_signature",
      ),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return toSerializeJsonForVersion(bundleVersion);
  }

  /// Version-aware serialization (required to emit the Ironwood 0x04 bit).
  Map<String, dynamic> toSerializeJsonForVersion(OrchardBundleVersion version) {
    final authorization = this.authorization;
    final bool haveActions = actions.isNotEmpty;
    if (haveActions && authorization == null) {
      throw ZcashErrors.orchardFailed(
        "toSerializeJson",
        reason: "Missing orchard bundle authorization.",
      );
    }
    final actionSignatures =
        actions.map((e) {
          final signature = e.authorization;
          if (signature == null) {
            throw ZcashErrors.orchardFailed(
              "toSerializeJson",
              reason: "Missing orchard action signature.",
            );
          }
          return signature;
        }).toList();
    return {
      "actions": actions.map((e) => e.toSerializeJson()).toList(),
      "flags": flags.toSerializeJsonForVersion(version),
      "balance": balance.value,
      "anchor": anchor.toSerializeJson(),
      "proof": authorization?.proof.toSerializeJson(),
      "binding_signature": authorization?.bindingSignature.toSerializeJson(),
      "signatures": actionSignatures.map((e) => e.toSerializeJson()).toList(),
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  List<OrchardCircuitInstance> toCircuitInstance() {
    final anchor = this.anchor;
    return actions
        .map(
          (e) => e.toCircuitInstance(
            anchor: anchor,
            flags: flags,
            version: bundleVersion.protocolVersion,
          ),
        )
        .toList();
  }

  RedPallasBindingPublicKey toBvk() {
    final bvk =
        OrchardValueCommitment.from(actions.map((e) => e.cvNet).toList()) -
        OrchardValueCommitment.derive(
          value: balance,
          rcv: OrchardValueCommitTrapdoor.zero(),
        );
    return RedPallasBindingPublicKey.fromBytes(bvk.toBytes());
  }
}
