import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/exception/exception.dart';
import 'package:zcash_dart/src/address/src/unified.dart';
import 'package:zcash_dart/src/transparent/keys/public_key.dart';

/// abstract class for all zcash addreess.
abstract class ZcashAddress
    with Equality, CborTagSerializable
    implements IAddress {
  /// address as string
  @override
  final String address;

  /// type of address
  final ZcashAddressType addressType;

  /// network of address.
  final ZcashNetwork network;

  /// this show only supported supportedProtocols. (transparent, orchard, sapling)
  final List<ZcashProtocol> supportedProtocols;

  /// Converts this address to another network.
  ZcashAddress toNetwork(ZcashNetwork network);
  T cast<T extends ZcashAddress>() {
    if (this is! T) {
      throw CastFailedException<T>(value: this);
    }
    return this as T;
  }

  /// encode address as bytes.
  List<int> toBytes();

  const ZcashAddress.internal({
    required this.addressType,
    required this.network,
    required this.address,
    required this.supportedProtocols,
  });

  /// Creates a Zcash address from an encoded string, validating the network and type if provided.
  factory ZcashAddress(
    String address, {
    ZcashNetwork? network,
    ZcashAddressType? type,
  }) {
    if (type == null) {
      final addr = ZcashAddrDecoder().decodeAddr(address);

      if (network != null && network != addr.network) {
        throw ZcashAddressException.mismatchNetwork(
          network: addr.network,
          expected: network,
        );
      }
      type = addr.type;
    }
    return switch (type) {
      ZcashAddressType.unified => ZcashUnifiedAddress(
        address,
        network: network,
      ),
      ZcashAddressType.sprout => SproutAddress(address, network: network),
      ZcashAddressType.sapling => SaplingAddress(address, network: network),
      ZcashAddressType.tex => TexAddress(address, network: network),
      ZcashAddressType.p2pkh => ZcashP2pkhAddress(address, network: network),
      ZcashAddressType.p2sh => ZcashP2shAddress(address, network: network),
    };
  }

  factory ZcashAddress.deserializeIAddress({
    List<int>? bytes,
    CborObject? object,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: BlockchainNetwork.zcash.identifier,
      cborBytes: bytes,
      cborObject: object,
    );
    final type = ZcashAddressType.fromValue(values.rawValueAt(0));
    final network = ZcashNetwork.fromValue(values.rawValueAt(1));
    final List<int> addrBytes = values.rawValueAt(2);
    return switch (type) {
      ZcashAddressType.unified => ZcashUnifiedAddress.fromBytes(
        bytes: addrBytes,
        network: network,
      ),
      ZcashAddressType.sprout => SproutAddress.fromBytes(
        bytes: addrBytes,
        network: network,
      ),
      ZcashAddressType.sapling => SaplingAddress.fromBytes(
        bytes: addrBytes,
        network: network,
      ),
      ZcashAddressType.tex => TexAddress.fromBytes(
        bytes: addrBytes,
        network: network,
      ),
      ZcashAddressType.p2pkh => ZcashP2pkhAddress.fromBytes(
        bytes: addrBytes,
        network: network,
      ),
      ZcashAddressType.p2sh => ZcashP2shAddress.fromBytes(
        bytes: addrBytes,
        network: network,
        type:
            BitcoinAddressType.fromTag(
              values.rawValueAt(3),
            ).cast<P2shAddressType>(),
      ),
    };
  }

  /// convert address to p2sh if possible.
  ZcashP2shAddress? tryToP2sh() => null;

  /// convert address to p2pkh if possible.
  ZcashP2pkhAddress? tryToP2pkh() => null;

  /// convert address to transparent address if possible.
  ZcashTransparentAddress? tryToTransparentAddreses() => null;

  /// convert address to sapling payment address if possible.
  SaplingPaymentAddress? tryToSaplingPaymentAddress() => null;

  /// convert address to sapling address if possible.
  SaplingAddress? tryToSaplingAddress() => null;

  /// convert address to orchard address if possible.
  OrchardAddress? tryToOrchardAddress() => null;

  /// return protocol address
  /// for orchard protocol return unified address only contains orchard receiver.
  ZcashAddress? toProtocolAddress(ZcashProtocol protocol) {
    if (!supportedProtocols.contains(protocol)) {
      return null;
    }
    return switch (protocol) {
      ZcashProtocol.transparent => tryToTransparentAddreses(),
      ZcashProtocol.sapling => tryToSaplingAddress(),
      _ => null,
    };
  }

  @override
  String toString() {
    return address;
  }

  @override
  List<dynamic> get variables => [addressType, address];

  @override
  BlockchainNetwork get blockchainNetwork => BlockchainNetwork.zcash;

  @override
  SerializationIdentifier get serializationIdentifier =>
      blockchainNetwork.identifier;

  @override
  List<CborObject?> get serializationItems => [
    addressType.value.toCbor(),
    network.value.toCbor(),
    CborBytesValue(toBytes()),
  ];

  @override
  List<int> encodeAsIAddress() {
    return toCbor().encode();
  }

  @override
  String get viewType => addressType.name;
}

/// Abstract base for Zcash transparent addresses (P2SH/P2PKH).
abstract class ZcashTransparentAddress extends ZcashAddress
    implements LegacyAddress {
  const ZcashTransparentAddress._({
    required super.address,
    required super.network,
    required super.addressType,
  }) : super.internal(supportedProtocols: const [ZcashProtocol.transparent]);

  /// Creates a Transparent address from an encoded string, validating the network if provided.
  factory ZcashTransparentAddress(String address, {ZcashNetwork? network}) {
    final addr = ZcashAddrDecoder().decodeAddr(address, network: network);
    return switch (addr.type) {
      ZcashAddressType.p2pkh => ZcashP2pkhAddress._(
        data: addr.addressBytes,
        network: addr.network,
        address: address,
      ),
      ZcashAddressType.p2sh => ZcashP2shAddress._(
        data: addr.addressBytes,
        network: addr.network,
        address: address,
        type: P2shAddressType.p2pkInP2sh,
      ),
      _ =>
        throw ZcashAddressException(
          "Invalid transparent address encoding bytes.",
        ),
    };
  }

  @override
  ZcashTransparentAddress tryToTransparentAddreses() {
    return this;
  }
}

/// Represents a Zcash Sprout address.
class SproutAddress extends ZcashAddress {
  final List<int> data;
  SproutAddress._({
    required List<int> data,
    required super.network,
    required super.address,
  }) : data =
           data
               .exc(
                 length: ZcashAddressType.sprout.lengthInBytes!,
                 reason: "Invalid SproutAddress address bytes length.",
                 operation: "SproutAddress",
               )
               .asImmutableBytes,
       super.internal(
         addressType: ZcashAddressType.sprout,
         supportedProtocols: const [],
       );

  /// Creates a Sprout address from raw bytes for the specified network.
  factory SproutAddress.fromBytes({
    required List<int> bytes,
    required ZcashNetwork network,
  }) {
    return SproutAddress._(
      data: bytes,
      network: network,
      address: ZcashAddrEncoder().encodeKey(
        bytes,
        addrType: ZcashAddressType.sprout,
        network: network,
      ),
    );
  }

  /// Creates a Sprout address from an encoded string, validating the network if provided.
  factory SproutAddress(String address, {ZcashNetwork? network}) {
    final addr = ZcashAddrDecoder().decodeAddr(
      address,
      type: ZcashAddressType.sprout,
      network: network,
    );
    return SproutAddress._(
      data: addr.addressBytes,
      network: addr.network,
      address: address,
    );
  }

  @override
  List<int> toBytes() {
    return data.clone();
  }

  /// Converts this address to another network.
  @override
  SproutAddress toNetwork(ZcashNetwork network) {
    if (network == this.network) return this;
    return SproutAddress.fromBytes(bytes: toBytes(), network: network);
  }
}

/// Represents a Zcash Sapling address.
class SaplingAddress extends ZcashAddress {
  final List<int> data;
  SaplingAddress._({
    required List<int> data,
    required super.network,
    required super.address,
  }) : data =
           data
               .exc(
                 length: ZcashAddressType.sapling.lengthInBytes!,
                 operation: "SaplingAddress",
                 reason: "Invalid sapling address bytes length.",
               )
               .asImmutableBytes,
       super.internal(
         addressType: ZcashAddressType.sapling,
         supportedProtocols: const [ZcashProtocol.sapling],
       );

  /// Creates a Sapling address from raw bytes for the specified network.
  factory SaplingAddress.fromBytes({
    required List<int> bytes,
    required ZcashNetwork network,
  }) {
    return SaplingAddress._(
      data: bytes,
      network: network,
      address: ZcashAddrEncoder().encodeKey(
        bytes,
        network: network,
        addrType: ZcashAddressType.sapling,
      ),
    );
  }

  /// Creates a Sapling address from an encoded string, validating the network if provided.
  factory SaplingAddress(String address, {ZcashNetwork? network}) {
    final addr = ZcashAddrDecoder().decodeAddr(
      address,
      type: ZcashAddressType.sapling,
      network: network,
    );
    return SaplingAddress._(
      data: addr.addressBytes,
      network: addr.network,
      address: address,
    );
  }

  SaplingPaymentAddress toSaplingPaymentAddress() {
    return SaplingPaymentAddress.fromBytes(data);
  }

  @override
  List<int> toBytes() {
    return data.clone();
  }

  /// Converts this address to another network.
  @override
  SaplingAddress toNetwork(ZcashNetwork network) {
    if (network == this.network) return this;
    return SaplingAddress.fromBytes(bytes: toBytes(), network: network);
  }

  @override
  SaplingAddress tryToSaplingAddress() {
    return this;
  }

  @override
  SaplingPaymentAddress tryToSaplingPaymentAddress() {
    return SaplingPaymentAddress.fromBytes(data);
  }
}

/// Represents a Zcash P2PKH address.
class ZcashP2pkhAddress extends ZcashTransparentAddress {
  final List<int> data;
  ZcashP2pkhAddress._({
    required List<int> data,
    required super.network,
    required super.address,
  }) : data =
           data
               .exc(
                 length: ZcashAddressType.p2pkh.lengthInBytes!,
                 operation: "ZcashP2pkhAddress",
                 reason: "Invalid P2PKH address bytes length.",
               )
               .asImmutableBytes,
       super._(addressType: ZcashAddressType.p2pkh);

  /// Creates a P2PKH address from raw bytes for the specified network.
  factory ZcashP2pkhAddress.fromBytes({
    required List<int> bytes,
    required ZcashNetwork network,
  }) {
    return ZcashP2pkhAddress._(
      data: bytes,
      network: network,
      address: ZcashAddrEncoder().encodeKey(
        bytes,
        addrType: ZcashAddressType.p2pkh,
        network: network,
      ),
    );
  }

  /// Creates a P2PKH address from an encoded string, validating the network if provided.
  factory ZcashP2pkhAddress(String address, {ZcashNetwork? network}) {
    final addr = ZcashAddrDecoder().decodeAddr(
      address,
      type: ZcashAddressType.p2pkh,
      network: network,
    );
    return ZcashP2pkhAddress._(
      data: addr.addressBytes,
      network: addr.network,
      address: address,
    );
  }
  @override
  List<int> toBytes() {
    return data.clone();
  }

  @override
  ZcashP2pkhAddress? tryToP2pkh() {
    return this;
  }

  /// Converts this address to another network.
  @override
  ZcashP2pkhAddress toNetwork(ZcashNetwork network) {
    if (network == this.network) return this;
    return ZcashP2pkhAddress.fromBytes(bytes: toBytes(), network: network);
  }

  @override
  Script toScriptPubKey() {
    return Script(
      script: [
        BitcoinOpcode.opDup,
        BitcoinOpcode.opHash160,
        addressProgram,
        BitcoinOpcode.opEqualVerify,
        BitcoinOpcode.opCheckSig,
      ],
    );
  }

  @override
  String get addressProgram => BytesUtils.toHexString(data);

  @override
  String pubKeyHash() {
    return BitcoinAddressUtils.pubKeyHash(toScriptPubKey());
  }

  /// Override from bitcoin_base legacy addresses.
  /// Converts this address to another UTXO network (e.g. Bitcoin, Litecoin).
  @override
  String toAddress(BasedUtxoNetwork network) {
    return BitcoinAddressUtils.legacyToAddress(
      network: network,
      addressProgram: addressProgram,
      type: type,
    );
  }

  @override
  P2pkhAddressType get type => P2pkhAddressType.p2pkh;
}

/// Represents a Zcash P2SH address.
class ZcashP2shAddress extends ZcashTransparentAddress {
  final List<int> data;
  ZcashP2shAddress._({
    required List<int> data,
    required super.network,
    required super.address,
    required this.type,
  }) : data =
           data
               .exc(
                 length: ZcashAddressType.p2sh.lengthInBytes!,
                 reason: "Invalid P2SH address bytes length.",
                 operation: "ZcashP2shAddress",
               )
               .asImmutableBytes,
       super._(addressType: ZcashAddressType.p2sh);

  /// Creates a P2SH address from raw bytes for the specified network.
  factory ZcashP2shAddress.fromBytes({
    required List<int> bytes,
    required ZcashNetwork network,
    P2shAddressType type = P2shAddressType.p2pkInP2sh,
  }) {
    switch (type) {
      case P2shAddressType.p2pkhInP2sh:
      case P2shAddressType.p2pkInP2sh:
        break;
      default:
        throw ZcashAddressException("Invalid p2sh address type.");
    }
    return ZcashP2shAddress._(
      data: bytes,
      network: network,
      address: ZcashAddrEncoder().encodeKey(
        bytes,
        addrType: ZcashAddressType.p2sh,
        network: network,
      ),
      type: type,
    );
  }

  /// Creates a P2SH address from raw bytes for the specified network.
  factory ZcashP2shAddress.fromPublicKey({
    required List<int> publicKey,
    required ZcashNetwork network,
    P2shAddressType type = P2shAddressType.p2pkInP2sh,
  }) {
    final pk = ZECPublic.fromBytes(publicKey);
    switch (type) {
      case P2shAddressType.p2pkhInP2sh:
        return pk.toP2pkhInP2sh();
      case P2shAddressType.p2pkInP2sh:
        return pk.toP2pkInP2sh();
      default:
        throw ZcashAddressException("Invalid p2sh address type.");
    }
  }
  factory ZcashP2shAddress.fromScript({
    required Script script,
    required ZcashNetwork network,
    P2shAddressType type = P2shAddressType.p2pkInP2sh,
  }) {
    switch (type) {
      case P2shAddressType.p2pkhInP2sh:
      case P2shAddressType.p2pkInP2sh:
        break;
      default:
        throw ZcashAddressException("Unsupported p2sh address type.");
    }
    final bytes = BitcoinAddressUtils.scriptToHash160Bytes(script);
    return ZcashP2shAddress._(
      data: bytes,
      network: network,
      address: ZcashAddrEncoder().encodeKey(
        bytes,
        addrType: ZcashAddressType.p2sh,
        network: network,
      ),
      type: type,
    );
  }

  /// Creates a P2SH address from an encoded string, validating the network if provided.
  factory ZcashP2shAddress(
    String address, {
    ZcashNetwork? network,
    P2shAddressType type = P2shAddressType.p2pkInP2sh,
  }) {
    if (type.isP2sh32 || type.withToken) {
      throw ZcashAddressException("Invalid p2sh address type.");
    }
    final addr = ZcashAddrDecoder().decodeAddr(
      address,
      type: ZcashAddressType.p2sh,
      network: network,
    );
    return ZcashP2shAddress._(
      data: addr.addressBytes,
      network: addr.network,
      address: address,
      type: type,
    );
  }
  @override
  List<int> toBytes() {
    return data.clone();
  }

  @override
  ZcashP2shAddress tryToP2sh() {
    return this;
  }

  /// Converts this address to another network.
  @override
  ZcashP2shAddress toNetwork(ZcashNetwork network) {
    if (network == this.network) return this;
    return ZcashP2shAddress.fromBytes(bytes: toBytes(), network: network);
  }

  @override
  Script toScriptPubKey() {
    return Script(
      script: [
        BitcoinOpcode.opHash160,
        BytesUtils.toHexString(data),
        BitcoinOpcode.opEqual,
      ],
    );
  }

  @override
  String get addressProgram => BytesUtils.toHexString(data);

  @override
  String pubKeyHash() {
    return BitcoinAddressUtils.pubKeyHash(toScriptPubKey());
  }

  /// Override from bitcoin_base legacy addresses.
  /// Converts this address to another UTXO network (e.g. Bitcoin, Litecoin).
  @override
  String toAddress(BasedUtxoNetwork network) {
    return BitcoinAddressUtils.legacyToAddress(
      network: network,
      addressProgram: addressProgram,
      type: type,
    );
  }

  @override
  final P2shAddressType type;

  @override
  List<CborObject?> get serializationItems => [
    addressType.value.toCbor(),
    network.value.toCbor(),
    CborBytesValue(toBytes()),
    type.id.toCbor(),
  ];
}

/// Represents a Zcash Tex address.
class TexAddress extends ZcashAddress {
  final List<int> data;
  TexAddress._({
    required List<int> data,
    required super.network,
    required super.address,
  }) : data =
           data
               .exc(
                 length: ZcashAddressType.tex.lengthInBytes!,
                 operation: "TexAddress",
                 reason: "Invalid TexAddress bytes length.",
               )
               .asImmutableBytes,
       super.internal(
         addressType: ZcashAddressType.tex,
         supportedProtocols: const [],
       );

  /// Creates a Tex address from raw bytes for the specified network.
  factory TexAddress.fromBytes({
    required List<int> bytes,
    required ZcashNetwork network,
  }) {
    return TexAddress._(
      data: bytes,
      network: network,
      address: ZcashAddrEncoder().encodeKey(
        bytes,
        addrType: ZcashAddressType.tex,
        network: network,
      ),
    );
  }

  /// Creates a Tex address from an encoded string, validating the network if provided.
  factory TexAddress(String address, {ZcashNetwork? network}) {
    final addr = ZcashAddrDecoder().decodeAddr(
      address,
      type: ZcashAddressType.tex,
      network: network,
    );
    return TexAddress._(
      data: addr.addressBytes,
      network: addr.network,
      address: address,
    );
  }

  /// Converts this address to another network.
  @override
  TexAddress toNetwork(ZcashNetwork network) {
    if (network == this.network) return this;
    return TexAddress.fromBytes(bytes: toBytes(), network: network);
  }

  @override
  List<int> toBytes() {
    return data.clone();
  }
}
