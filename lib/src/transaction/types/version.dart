import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/note/note.dart';

enum ZcashNetworkProtocol implements Comparable<ZcashNetworkProtocol> {
  /// The consensus rules at the launch of Zcash.
  sprout(
    branchId: 0,
    activation: ProtocolActivationHeights(mainnet: 0, testnet: 0),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Overwinter`.
  overwinter(
    branchId: 0x5ba81b19,
    activation: ProtocolActivationHeights(mainnet: 347500, testnet: 207500),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Sapling`.
  sapling(
    branchId: 0x76b809bb,
    activation: ProtocolActivationHeights(mainnet: 419200, testnet: 280000),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Blossom`.
  blossom(
    branchId: 0x2bb40e60,
    activation: ProtocolActivationHeights(mainnet: 653600, testnet: 584000),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Heartwood`.
  heartwood(
    branchId: 0xf5b9230b,
    activation: ProtocolActivationHeights(mainnet: 903000, testnet: 903800),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Canopy`.
  canopy(
    branchId: 0xe9ff75a6,
    activation: ProtocolActivationHeights(mainnet: 1046400, testnet: 1028500),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Nu5`.
  nu5(
    branchId: 0xc2d6d0b4,
    activation: ProtocolActivationHeights(mainnet: 1687104, testnet: 1842420),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Nu6`.
  nu6(
    branchId: 0xc8e71055,
    activation: ProtocolActivationHeights(mainnet: 2726400, testnet: 2976000),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Nu6_1`.
  nu6_1(
    branchId: 0x4dec4df0,
    activation: ProtocolActivationHeights(mainnet: 3146400, testnet: 3536500),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Nu6_2`.
  nu6_2(
    branchId: 0x5437f330,
    activation: ProtocolActivationHeights(mainnet: 3364600, testnet: 4052000),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Nu6_3` (Ironwood).
  nu6_3(
    branchId: 0x37a5165b,
    activation: ProtocolActivationHeights(mainnet: 3428143, testnet: 4134000),
  ),

  /// The consensus rules deployed by `NetworkUpgrade::Nu7` (ZIP 259:
  /// 25-second blocks, v4/Sprout disabled; no new shielded pool or
  /// transaction format — v6 stays the suggested version).
  nu7(
    branchId: 0x77190AD9,
    activation: ProtocolActivationHeights(mainnet: 3543405, testnet: 4465026),
  );

  final int branchId;
  final ProtocolActivationHeights activation;
  static const int gracePeriod = 32256;
  const ZcashNetworkProtocol({
    required this.branchId,
    required this.activation,
  });

  static ZcashNetworkProtocol fromId(int? id) {
    return values.firstWhere(
      (e) => e.branchId == id,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching item found for the given value. $id",
              ),
    );
  }

  @override
  int compareTo(ZcashNetworkProtocol other) {
    return index.compareTo(other.index);
  }

  bool operator >(ZcashNetworkProtocol other) => compareTo(other) > 0;
  bool operator <(ZcashNetworkProtocol other) => compareTo(other) < 0;
  bool operator >=(ZcashNetworkProtocol other) => compareTo(other) >= 0;
  bool operator <=(ZcashNetworkProtocol other) => compareTo(other) <= 0;

  bool hasSapling() => this >= sapling;
  bool hasOrchard() => this >= nu5;
  bool hasCanopy() => this >= canopy;
  bool hasIronwood() => this >= nu6_3;
}

abstract class UpgradeActivationProvider {
  int activationHeight(ZcashNetworkProtocol protocol, ZcashNetwork network);
  ZcashNetworkProtocol protocolFromHeight(ZcashNetwork network, int height);
  Zip212Enforcement zip212Enforcement(
    ZcashNetwork network,
    int height, {

    /// if you knew the protocol.
    ZcashNetworkProtocol? protocol,
  });
}

/// for regtest all protocol activation height is 1
/// if you want to use regtest network and [DefaultZcashBlockProcessor] with different protocols activation height
/// you should create your own [UpgradeActivationProvider] class and pass to [ZcashBlockProcessorConfig]
class DefaultUpgradeActivationProvider implements UpgradeActivationProvider {
  const DefaultUpgradeActivationProvider();
  final Map<ZcashNetworkProtocol, ProtocolActivationHeights> upgrades = const {
    ZcashNetworkProtocol.sprout: ProtocolActivationHeights(
      mainnet: 0,
      testnet: 0,
      regtest: 0,
    ),
    ZcashNetworkProtocol.overwinter: ProtocolActivationHeights(
      mainnet: 347500,
      testnet: 207500,
    ),
    ZcashNetworkProtocol.sapling: ProtocolActivationHeights(
      mainnet: 419200,
      testnet: 280000,
    ),
    ZcashNetworkProtocol.blossom: ProtocolActivationHeights(
      mainnet: 653600,
      testnet: 584000,
    ),
    ZcashNetworkProtocol.heartwood: ProtocolActivationHeights(
      mainnet: 903000,
      testnet: 903800,
    ),
    ZcashNetworkProtocol.canopy: ProtocolActivationHeights(
      mainnet: 1046400,
      testnet: 1028500,
    ),
    ZcashNetworkProtocol.nu5: ProtocolActivationHeights(
      mainnet: 1687104,
      testnet: 1842420,
      regtest: 1,
    ),
    ZcashNetworkProtocol.nu6: ProtocolActivationHeights(
      mainnet: 2726400,
      testnet: 2976000,
      regtest: 1,
    ),
    ZcashNetworkProtocol.nu6_1: ProtocolActivationHeights(
      mainnet: 3146400,
      testnet: 3536500,
      regtest: 1,
    ),
    ZcashNetworkProtocol.nu6_2: ProtocolActivationHeights(
      mainnet: 3364600,
      testnet: 4052000,
      regtest: 1,
    ),
    // NU6.3 (Ironwood) is not active on regtest: no released node
    // (zcashd v6.20.0 tops out at NU6.2) implements it, so a regtest chain
    // is a NU6.2 chain. Keeping the mainnet height here makes
    // `protocolFromHeight` resolve regtest to NU6.2, which is the branch a
    // regtest node actually reports.
    ZcashNetworkProtocol.nu6_3: ProtocolActivationHeights(
      mainnet: 3428143,
      testnet: 4134000,
      regtest: 1,
    ),
    ZcashNetworkProtocol.nu7: ProtocolActivationHeights(
      mainnet: 3543405,
      testnet: 4465026,
      regtest: 1,
    ),
  };

  @override
  int activationHeight(ZcashNetworkProtocol protocol, ZcashNetwork network) {
    final activation = upgrades[protocol];
    if (activation == null) {
      throw BuError(
        DefaultErrorType.unsupported,
        "Unsupported protocol '${protocol.name}' for network '${network.name}'.",
      );
    }
    return activation.getActivationHeight(network);
  }

  @override
  ZcashNetworkProtocol protocolFromHeight(ZcashNetwork network, int height) {
    if (height.isNegative) {
      throw BuError(
        DefaultErrorType.invalidArgument,
        "Height must be non-negative",
      );
    }
    for (final i in ZcashNetworkProtocol.values.reversed) {
      final activeHeight = activationHeight(i, network);
      if (activeHeight <= height) {
        return i;
      }
    }
    return ZcashNetworkProtocol.sprout;
  }

  @override
  Zip212Enforcement zip212Enforcement(
    ZcashNetwork network,
    int height, {
    ZcashNetworkProtocol? protocol,
  }) {
    protocol ??= protocolFromHeight(network, height);
    if (protocol.hasSapling()) return Zip212Enforcement.on;
    if (!protocol.hasCanopy() || network == ZcashNetwork.regtest) {
      return Zip212Enforcement.off;
    }
    final activationHeight = this.activationHeight(
      ZcashNetworkProtocol.canopy,
      network,
    );
    if (height < activationHeight + ZcashNetworkProtocol.gracePeriod) {
      return Zip212Enforcement.gracePeriod;
    }
    return Zip212Enforcement.on;
  }
}

class LightwalletdBranchActivationProvider
    implements UpgradeActivationProvider {
  /// The active branch (tip branch reported by lightwalletd).
  final ZcashNetworkProtocol branch;

  /// Static defaults for everything except the pinned branch.
  final UpgradeActivationProvider fallback;

  const LightwalletdBranchActivationProvider(
    this.branch, {
    this.fallback = const DefaultUpgradeActivationProvider(),
  });

  /// Parses a lightwalletd `consensusBranchId` hex string (with or without
  /// `0x` prefix) into its protocol. Returns null when missing,
  /// malformed, or unknown — callers fall back to static defaults.
  static ZcashNetworkProtocol? tryParseBranchId(String? hex) {
    if (hex == null) return null;
    var s = hex.trim().toLowerCase();
    if (s.startsWith('0x')) s = s.substring(2);
    final id = int.tryParse(s, radix: 16);
    if (id == null) return null;
    try {
      return ZcashNetworkProtocol.fromId(id);
    } catch (_) {
      return null;
    }
  }

  @override
  int activationHeight(ZcashNetworkProtocol protocol, ZcashNetwork network) {
    return fallback.activationHeight(protocol, network);
  }

  @override
  ZcashNetworkProtocol protocolFromHeight(ZcashNetwork network, int height) {
    return branch;
  }

  @override
  Zip212Enforcement zip212Enforcement(
    ZcashNetwork network,
    int height, {
    ZcashNetworkProtocol? protocol,
  }) {
    return fallback.zip212Enforcement(
      network,
      height,
      protocol: protocol ?? branch,
    );
  }
}

enum TxVersionType {
  sprout(groupId: null, txVesion: 0),
  v3(groupId: 0x03C48270, txVesion: 3),
  v4(groupId: 0x892F2085, txVesion: 4),
  v5(groupId: 0x26A7270A, txVesion: 5),
  v6(groupId: 0xD884B698, txVesion: 6);

  final int? groupId;
  final int txVesion;
  const TxVersionType({required this.groupId, required this.txVesion});
  static TxVersionType findVesion({
    required bool overwintered,
    required int version,
    int? groupId,
  }) {
    if (!overwintered) {
      assert(version >= 1);
      return TxVersionType.sprout;
    }
    assert(groupId != null);
    return values.firstWhere(
      (e) => e.groupId == groupId && e.txVesion == version,
    );
  }

  static TxVersionType fromName(String? name) {
    return values.firstWhere(
      (e) => e.name == name,
      orElse:
          () =>
              throw BuError(
                DefaultErrorType.notFound,
                "No matching item found for the given value. $name",
              ),
    );
  }

  static TxVersionType? findFromVersionAndGroudId(int version, int? groupId) {
    return values.firstWhereNullable(
      (e) => e.txVesion == version && e.groupId == groupId,
    );
  }

  TxVersion toVersion() {
    return switch (this) {
      TxVersionType.v5 => TxVersionV5(),
      TxVersionType.v6 => TxVersionV6(),
      TxVersionType.v4 => TxVersionV4(),
      TxVersionType.v3 => TxVersionV3(),
      TxVersionType.sprout => TxVersionSprout(version: 0),
    };
  }

  /// Suggests the transaction version for a consensus branch.
  /// Mirrors `TxVersion::suggested_for_branch` in librustzcash.
  TxVersion suggestedVersionForBranch(ZcashNetworkProtocol branch) {
    return switch (branch) {
      ZcashNetworkProtocol.sprout => TxVersionSprout(version: 2),
      ZcashNetworkProtocol.overwinter => TxVersionV3(),
      ZcashNetworkProtocol.sapling ||
      ZcashNetworkProtocol.blossom ||
      ZcashNetworkProtocol.heartwood ||
      ZcashNetworkProtocol.canopy => TxVersionV4(),
      ZcashNetworkProtocol.nu5 ||
      ZcashNetworkProtocol.nu6 ||
      ZcashNetworkProtocol.nu6_1 ||
      ZcashNetworkProtocol.nu6_2 => TxVersionV5(),
      ZcashNetworkProtocol.nu6_3 || ZcashNetworkProtocol.nu7 => TxVersionV6(),
    };
  }

  /// Returns true if this transaction version is valid in the given branch.
  /// Mirrors `TxVersion::valid_in_branch` in librustzcash.
  bool validInBranch(ZcashNetworkProtocol branch) {
    return switch (this) {
      TxVersionType.sprout => branch == ZcashNetworkProtocol.sprout,
      TxVersionType.v3 => branch == ZcashNetworkProtocol.overwinter,
      TxVersionType.v4 => branch >= ZcashNetworkProtocol.sapling,
      TxVersionType.v5 => branch >= ZcashNetworkProtocol.nu5,
      TxVersionType.v6 => branch >= ZcashNetworkProtocol.nu6_3,
    };
  }
}

sealed class TxVersion with LayoutSerializable {
  final TxVersionType type;
  const TxVersion({required this.type});
  factory TxVersion.deserialize(List<int> bytes) {
    final decode = LayoutSerializable.deserialize(
      bytes: bytes,
      layout: layout(),
    );
    return TxVersion.deserializeJson(decode);
  }
  factory TxVersion.deserializeJson(Map<String, dynamic> json) {
    final version = json.valueEnsureAsMap<String, dynamic>("version");
    final type = TxVersionType.fromName(version.keys.firstOrNull);
    return switch (type) {
      TxVersionType.sprout => TxVersionSprout(
        version: version.valueAsInt(type.name),
      ),
      TxVersionType.v3 => TxVersionV3(),
      TxVersionType.v4 => TxVersionV4(),
      TxVersionType.v5 => TxVersionV5(),
      TxVersionType.v6 => TxVersionV6(),
    };
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder(
        layout: (property, params) => LayoutConst.u32(property: property),
        property: "header",
      ),
      LazyStructLayoutBuilder<int?, LayoutRepository>(
        layout: (property, params) {
          if (params.action.isEncode) {
            final int? version = params.sourceOrResult.valueAsInt("version");
            if (version != null) {
              return LayoutConst.u32();
            }
            return LayoutConst.none();
          }
          final int header = params.sourceOrResult.valueAsInt("header");
          final overwintered = (header >> 31) == 1;
          if (overwintered) {
            return LayoutConst.u32();
          }
          return LayoutConst.none();
        },
        finalizeDecode: (layoutResult, structResult, _) {
          final int header = structResult.valueAsInt("header");
          final version = header & 0x7FFFFFFF;
          final v = TxVersionType.findVesion(
            overwintered: layoutResult != null,
            version: version,
            groupId: layoutResult,
          );
          return {v.name: layoutResult == null ? version : null};
        },
        property: "version",
      ),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout();
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"header": (1 << 31) | type.txVesion, "version": type.groupId};
  }

  bool hasOverwinter() => true;
  bool hasSapling() => true;
  bool hasOrchard() => false;
  bool hasIronwood() => false;
  bool hasSprout() => true;

  int header() => (1 << 31) | type.txVesion;

  List<int> headerBytes() => header().toU32LeBytes();
}

class TxVersionSprout extends TxVersion {
  final int version;
  const TxVersionSprout({required this.version})
    : super(type: TxVersionType.sprout);
  @override
  int header() => version;
  @override
  Map<String, dynamic> toSerializeJson() {
    return {"header": version, "version": null};
  }

  @override
  bool hasOverwinter() {
    return false;
  }

  @override
  bool hasSapling() {
    return false;
  }

  @override
  bool hasSprout() {
    return version >= 2;
  }
}

class TxVersionV3 extends TxVersion {
  const TxVersionV3() : super(type: TxVersionType.v3);
  @override
  bool hasSapling() {
    return false;
  }
}

class TxVersionV4 extends TxVersion {
  const TxVersionV4() : super(type: TxVersionType.v4);
}

class TxVersionV5 extends TxVersion {
  const TxVersionV5() : super(type: TxVersionType.v5);
  @override
  bool hasOrchard() {
    return true;
  }

  @override
  bool hasSprout() {
    return false;
  }
}

class TxVersionV6 extends TxVersion {
  const TxVersionV6() : super(type: TxVersionType.v6);
  @override
  bool hasOrchard() {
    return true;
  }

  @override
  bool hasIronwood() {
    return true;
  }

  @override
  bool hasSprout() {
    return false;
  }
}

class ProtocolActivationHeights {
  final int mainnet;
  final int testnet;
  final int regtest;
  const ProtocolActivationHeights({
    required this.mainnet,
    required this.testnet,
    this.regtest = 1,
  });

  int getActivationHeight(ZcashNetwork network) {
    return switch (network) {
      ZcashNetwork.mainnet => mainnet,
      ZcashNetwork.testnet => testnet,
      ZcashNetwork.regtest => regtest,
    };
  }
}
