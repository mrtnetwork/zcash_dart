import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/exception/exception.dart';
import 'package:zcash_dart/src/address/src/unified.dart';

/// abstract class for all zcash addreess.
abstract class ZCashAddress with Equality {
  /// address as string
  final String address;

  /// type of address
  final ZCashAddressType addressType;

  /// network of address.
  final ZCashNetwork network;

  /// Converts this address to another network.
  ZCashAddress toNetwork(ZCashNetwork network);
  T cast<T extends ZCashAddress>() {
    if (this is! T) {
      throw CastFailedException<T>(value: this);
    }
    return this as T;
  }

  /// encode address as bytes.
  List<int> toBytes();

  const ZCashAddress.internal(
      {required this.addressType,
      required this.network,
      required this.address});

  /// Creates a ZCash address from an encoded string, validating the network and type if provided.
  factory ZCashAddress(String address,
      {ZCashNetwork? network, ZCashAddressType? type}) {
    if (type == null) {
      final addr = ZCashAddrDecoder().decodeAddr(address);

      if (network != null && network != addr.network) {
        throw ZCashAddressException.mismatchNetwork(
            network: addr.network, expected: network);
      }
      type = addr.type;
    }
    return switch (type) {
      ZCashAddressType.unified =>
        ZCashUnifiedAddress(address, network: network),
      ZCashAddressType.sprout => SproutAddress(address, network: network),
      ZCashAddressType.sapling => SaplingAddress(address, network: network),
      ZCashAddressType.tex => TexAddress(address, network: network),
      ZCashAddressType.p2pkh => ZCashP2pkhAddress(address, network: network),
      ZCashAddressType.p2sh => ZCashP2shAddress(address, network: network),
    };
  }

  /// convert address to p2sh if possible.
  ZCashP2shAddress? tryToP2sh() => null;

  /// convert address to p2pkh if possible.
  ZCashP2pkhAddress? tryToP2pkh() => null;

  /// convert address to transparent address if possible.
  ZCashTransparentAddress? tryToTransparentAddreses() => null;

  /// convert address to sapling payment address if possible.
  SaplingPaymentAddress? tryToSaplingPaymentAddress() => null;

  /// convert address to sapling address if possible.
  SaplingAddress? tryToSaplingAddress() => null;

  /// convert address to orchard address if possible.
  OrchardAddress? tryToOrchardAddress() => null;

  @override
  String toString() {
    return address;
  }

  @override
  List<dynamic> get variables => [addressType, address];
}

/// Abstract base for Zcash transparent addresses (P2SH/P2PKH).
abstract class ZCashTransparentAddress extends ZCashAddress
    implements LegacyAddress {
  const ZCashTransparentAddress._(
      {required super.address,
      required super.network,
      required super.addressType})
      : super.internal();

  /// Creates a Transparent address from an encoded string, validating the network if provided.
  factory ZCashTransparentAddress(String address, {ZCashNetwork? network}) {
    final addr = ZCashAddrDecoder().decodeAddr(address, network: network);
    return switch (addr.type) {
      ZCashAddressType.p2pkh => ZCashP2pkhAddress._(
          data: addr.addressBytes, network: addr.network, address: address),
      ZCashAddressType.p2sh => ZCashP2shAddress._(
          data: addr.addressBytes,
          network: addr.network,
          address: address,
          type: P2shAddressType.p2pkInP2sh),
      _ => throw ZCashAddressException(
          "Invalid transparent address encoding bytes.")
    };
  }

  @override
  ZCashTransparentAddress tryToTransparentAddreses() {
    return this;
  }
}

/// Represents a Zcash Sprout address.
class SproutAddress extends ZCashAddress {
  final List<int> data;
  SproutAddress._(
      {required List<int> data, required super.network, required super.address})
      : data = data
            .exc(
              length: ZCashAddressType.sprout.lengthInBytes!,
              reason: "Invalid SproutAddress address bytes length.",
              operation: "SproutAddress",
            )
            .asImmutableBytes,
        super.internal(addressType: ZCashAddressType.sprout);

  /// Creates a Sprout address from raw bytes for the specified network.
  factory SproutAddress.fromBytes(
      {required List<int> bytes, required ZCashNetwork network}) {
    return SproutAddress._(
        data: bytes,
        network: network,
        address: ZCashAddrEncoder().encodeKey(bytes,
            addrType: ZCashAddressType.sprout, network: network));
  }

  /// Creates a Sprout address from an encoded string, validating the network if provided.
  factory SproutAddress(String address, {ZCashNetwork? network}) {
    final addr = ZCashAddrDecoder()
        .decodeAddr(address, type: ZCashAddressType.sprout, network: network);
    return SproutAddress._(
        data: addr.addressBytes, network: addr.network, address: address);
  }

  @override
  List<int> toBytes() {
    return data.clone();
  }

  /// Converts this address to another network.
  @override
  SproutAddress toNetwork(ZCashNetwork network) {
    if (network == this.network) return this;
    return SproutAddress.fromBytes(bytes: toBytes(), network: network);
  }
}

/// Represents a Zcash Sapling address.
class SaplingAddress extends ZCashAddress {
  final List<int> data;
  SaplingAddress._(
      {required List<int> data, required super.network, required super.address})
      : data = data
            .exc(
                length: ZCashAddressType.sapling.lengthInBytes!,
                operation: "SaplingAddress",
                reason: "Invalid sapling address bytes length.")
            .asImmutableBytes,
        super.internal(addressType: ZCashAddressType.sapling);

  /// Creates a Sapling address from raw bytes for the specified network.
  factory SaplingAddress.fromBytes(
      {required List<int> bytes, required ZCashNetwork network}) {
    return SaplingAddress._(
        data: bytes,
        network: network,
        address: ZCashAddrEncoder().encodeKey(bytes,
            network: network, addrType: ZCashAddressType.sapling));
  }

  /// Creates a Sapling address from an encoded string, validating the network if provided.
  factory SaplingAddress(String address, {ZCashNetwork? network}) {
    final addr = ZCashAddrDecoder()
        .decodeAddr(address, type: ZCashAddressType.sapling, network: network);
    return SaplingAddress._(
        data: addr.addressBytes, network: addr.network, address: address);
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
  SaplingAddress toNetwork(ZCashNetwork network) {
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
class ZCashP2pkhAddress extends ZCashTransparentAddress {
  final List<int> data;
  ZCashP2pkhAddress._(
      {required List<int> data, required super.network, required super.address})
      : data = data
            .exc(
              length: ZCashAddressType.p2pkh.lengthInBytes!,
              operation: "ZCashP2pkhAddress",
              reason: "Invalid P2PKH address bytes length.",
            )
            .asImmutableBytes,
        super._(addressType: ZCashAddressType.p2pkh);

  /// Creates a P2PKH address from raw bytes for the specified network.
  factory ZCashP2pkhAddress.fromBytes(
      {required List<int> bytes, required ZCashNetwork network}) {
    return ZCashP2pkhAddress._(
        data: bytes,
        network: network,
        address: ZCashAddrEncoder().encodeKey(bytes,
            addrType: ZCashAddressType.p2pkh, network: network));
  }

  /// Creates a P2PKH address from an encoded string, validating the network if provided.
  factory ZCashP2pkhAddress(String address, {ZCashNetwork? network}) {
    final addr = ZCashAddrDecoder()
        .decodeAddr(address, type: ZCashAddressType.p2pkh, network: network);
    return ZCashP2pkhAddress._(
        data: addr.addressBytes, network: addr.network, address: address);
  }
  @override
  List<int> toBytes() {
    return data.clone();
  }

  @override
  ZCashP2pkhAddress? tryToP2pkh() {
    return this;
  }

  /// Converts this address to another network.
  @override
  ZCashP2pkhAddress toNetwork(ZCashNetwork network) {
    if (network == this.network) return this;
    return ZCashP2pkhAddress.fromBytes(bytes: toBytes(), network: network);
  }

  @override
  Script toScriptPubKey() {
    return Script(script: [
      BitcoinOpcode.opDup,
      BitcoinOpcode.opHash160,
      addressProgram,
      BitcoinOpcode.opEqualVerify,
      BitcoinOpcode.opCheckSig
    ]);
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
class ZCashP2shAddress extends ZCashTransparentAddress {
  final List<int> data;
  ZCashP2shAddress._(
      {required List<int> data,
      required super.network,
      required super.address,
      required this.type})
      : data = data
            .exc(
                length: ZCashAddressType.p2sh.lengthInBytes!,
                reason: "Invalid P2SH address bytes length.",
                operation: "ZCashP2shAddress")
            .asImmutableBytes,
        super._(addressType: ZCashAddressType.p2sh);

  /// Creates a P2SH address from raw bytes for the specified network.
  factory ZCashP2shAddress.fromBytes(
      {required List<int> bytes,
      required ZCashNetwork network,
      P2shAddressType type = P2shAddressType.p2pkInP2sh}) {
    if (type.isP2sh32 || type.withToken) {
      throw ZCashAddressException("Invalid p2sh address type.");
    }
    return ZCashP2shAddress._(
        data: bytes,
        network: network,
        address: ZCashAddrEncoder().encodeKey(bytes,
            addrType: ZCashAddressType.p2sh, network: network),
        type: type);
  }
  factory ZCashP2shAddress.fromScript(
      {required Script script,
      required ZCashNetwork network,
      P2shAddressType type = P2shAddressType.p2pkInP2sh}) {
    if (type.isP2sh32 || type.withToken) {
      throw ZCashAddressException("Invalid p2sh address type.");
    }
    final scriptBytes = script.toBytes();
    final bytes = QuickCrypto.hash160(scriptBytes);
    return ZCashP2shAddress._(
        data: bytes,
        network: network,
        address: ZCashAddrEncoder().encodeKey(bytes,
            addrType: ZCashAddressType.p2sh, network: network),
        type: type);
  }

  /// Creates a P2SH address from an encoded string, validating the network if provided.
  factory ZCashP2shAddress(String address,
      {ZCashNetwork? network,
      P2shAddressType type = P2shAddressType.p2pkInP2sh}) {
    if (type.isP2sh32 || type.withToken) {
      throw ZCashAddressException("Invalid p2sh address type.");
    }
    final addr = ZCashAddrDecoder()
        .decodeAddr(address, type: ZCashAddressType.p2sh, network: network);
    return ZCashP2shAddress._(
        data: addr.addressBytes,
        network: addr.network,
        address: address,
        type: type);
  }
  @override
  List<int> toBytes() {
    return data.clone();
  }

  @override
  ZCashP2shAddress tryToP2sh() {
    return this;
  }

  /// Converts this address to another network.
  @override
  ZCashP2shAddress toNetwork(ZCashNetwork network) {
    if (network == this.network) return this;
    return ZCashP2shAddress.fromBytes(bytes: toBytes(), network: network);
  }

  @override
  Script toScriptPubKey() {
    return Script(script: [
      BitcoinOpcode.opHash160,
      BytesUtils.toHexString(data),
      BitcoinOpcode.opEqual
    ]);
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
}

/// Represents a Zcash Tex address.
class TexAddress extends ZCashAddress {
  final List<int> data;
  TexAddress._(
      {required List<int> data, required super.network, required super.address})
      : data = data
            .exc(
                length: ZCashAddressType.tex.lengthInBytes!,
                operation: "TexAddress",
                reason: "Invalid TexAddress bytes length.")
            .asImmutableBytes,
        super.internal(addressType: ZCashAddressType.tex);

  /// Creates a Tex address from raw bytes for the specified network.
  factory TexAddress.fromBytes(
      {required List<int> bytes, required ZCashNetwork network}) {
    return TexAddress._(
        data: bytes,
        network: network,
        address: ZCashAddrEncoder().encodeKey(bytes,
            addrType: ZCashAddressType.tex, network: network));
  }

  /// Creates a Tex address from an encoded string, validating the network if provided.
  factory TexAddress(String address, {ZCashNetwork? network}) {
    final addr = ZCashAddrDecoder()
        .decodeAddr(address, type: ZCashAddressType.tex, network: network);
    return TexAddress._(
        data: addr.addressBytes, network: addr.network, address: address);
  }

  /// Converts this address to another network.
  @override
  TexAddress toNetwork(ZCashNetwork network) {
    if (network == this.network) return this;
    return TexAddress.fromBytes(bytes: toBytes(), network: network);
  }

  @override
  List<int> toBytes() {
    return data.clone();
  }
}
