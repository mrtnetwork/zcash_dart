import 'package:blockchain_utils/blockchain_utils.dart';

enum NetworkUpgrade implements Comparable<NetworkUpgrade> {
  /// The consensus rules at the launch of Zcash.
  sprout(branchId: 0, mainnetActiveHeight: 0, testnetActiveHeight: 0),

  /// The consensus rules deployed by `NetworkUpgrade::Overwinter`.
  overwinter(
      branchId: 0x5ba81b19,
      mainnetActiveHeight: 347500,
      testnetActiveHeight: 207500),

  /// The consensus rules deployed by `NetworkUpgrade::Sapling`.
  sapling(
      branchId: 0x76b809bb,
      mainnetActiveHeight: 419200,
      testnetActiveHeight: 280000),

  /// The consensus rules deployed by `NetworkUpgrade::Blossom`.
  blossom(
      branchId: 0x2bb40e60,
      mainnetActiveHeight: 653600,
      testnetActiveHeight: 584000),

  /// The consensus rules deployed by `NetworkUpgrade::Heartwood`.
  heartwood(
      branchId: 0xf5b9230b,
      mainnetActiveHeight: 903000,
      testnetActiveHeight: 903800),

  /// The consensus rules deployed by `NetworkUpgrade::Canopy`.
  canopy(
      branchId: 0xe9ff75a6,
      mainnetActiveHeight: 1046400,
      testnetActiveHeight: 1028500),

  /// The consensus rules deployed by `NetworkUpgrade::Nu5`.
  nu5(
      branchId: 0xc2d6d0b4,
      mainnetActiveHeight: 1687104,
      testnetActiveHeight: 1842420),

  /// The consensus rules deployed by `NetworkUpgrade::Nu6`.
  nu6(
      branchId: 0xc8e71055,
      mainnetActiveHeight: 2726400,
      testnetActiveHeight: 2976000),

  /// The consensus rules deployed by `NetworkUpgrade::Nu6_1`.
  nu6_1(
      branchId: 0x4dec4df0,
      mainnetActiveHeight: 3146400,
      testnetActiveHeight: 3536500);

  final int branchId;
  final int mainnetActiveHeight;
  final int testnetActiveHeight;
  const NetworkUpgrade(
      {required this.branchId,
      required this.mainnetActiveHeight,
      required this.testnetActiveHeight});
  static NetworkUpgrade fromId(int? id) {
    return values.firstWhere((e) => e.branchId == id,
        orElse: () => throw ItemNotFoundException(value: id));
  }

  static const int gracePeriod = 32256;

  static NetworkUpgrade fromHeight(int height, ZCashNetwork network) {
    return switch (network) {
      ZCashNetwork.mainnet => () {
          return values.lastWhere((e) => height >= e.mainnetActiveHeight);
        }(),
      _ => () {
          assert(network != ZCashNetwork.regtest,
              "Network upgrade not available.");
          return values.lastWhere((e) => height >= e.testnetActiveHeight);
        }()
    };
  }

  int activeHeight(ZCashNetwork network) {
    return switch (network) {
      ZCashNetwork.mainnet => mainnetActiveHeight,
      _ => testnetActiveHeight
    };
  }

  @override
  int compareTo(NetworkUpgrade other) {
    return index.compareTo(other.index);
  }

  bool operator >(NetworkUpgrade other) {
    return compareTo(other) > 0;
  }

  bool operator <(NetworkUpgrade other) {
    return compareTo(other) < 0;
  }

  bool operator >=(NetworkUpgrade other) {
    return compareTo(other) >= 0;
  }

  bool operator <=(NetworkUpgrade other) {
    return compareTo(other) <= 0;
  }

  bool hasSapling() => this >= sapling;
  bool hasOrchard() => this >= nu5;
}

enum TxVersionType {
  sprout(groupId: null, txVesion: 0),
  v3(groupId: 0x03C48270, txVesion: 3),
  v4(groupId: 0x892F2085, txVesion: 4),
  v5(groupId: 0x26A7270A, txVesion: 5);

  final int? groupId;
  final int txVesion;
  const TxVersionType({required this.groupId, required this.txVesion});
  static TxVersionType findVesion(
      {required bool overwintered, required int version, int? groupId}) {
    if (!overwintered) {
      assert(version >= 1);
      return TxVersionType.sprout;
    }
    assert(groupId != null);
    return values
        .firstWhere((e) => e.groupId == groupId && e.txVesion == version);
  }

  static TxVersionType fromName(String? name) {
    return values.firstWhere((e) => e.name == name,
        orElse: () => throw ItemNotFoundException(value: name));
  }

  static TxVersionType? findFromVersionAndGroudId(int version, int? groupId) {
    return values.firstWhereNullable(
        (e) => e.txVesion == version && e.groupId == groupId);
  }

  TxVersion toVersion() {
    return switch (this) {
      TxVersionType.v5 => TxVersionV5(),
      TxVersionType.v4 => TxVersionV4(),
      TxVersionType.v3 => TxVersionV3(),
      TxVersionType.sprout => TxVersionSprout(version: 0),
    };
  }
}

sealed class TxVersion with LayoutSerializable {
  final TxVersionType type;
  const TxVersion({required this.type});
  factory TxVersion.deserialize(List<int> bytes) {
    final decode =
        LayoutSerializable.deserialize(bytes: bytes, layout: layout());
    return TxVersion.deserializeJson(decode);
  }
  factory TxVersion.deserializeJson(Map<String, dynamic> json) {
    final version = json.valueEnsureAsMap<String, dynamic>("version");
    final type = TxVersionType.fromName(version.keys.firstOrNull);
    return switch (type) {
      TxVersionType.sprout =>
        TxVersionSprout(version: version.valueAsInt(type.name)),
      TxVersionType.v3 => TxVersionV3(),
      TxVersionType.v4 => TxVersionV4(),
      TxVersionType.v5 => TxVersionV5()
    };
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.lazyStruct([
      LazyStructLayoutBuilder(
          layout: (property, params) => LayoutConst.u32(property: property),
          property: "header"),
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
                groupId: layoutResult);
            return {v.name: layoutResult == null ? version : null};
          },
          property: "version")
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
