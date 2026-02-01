import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/exception/exception.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';

/// Represents a Zcash Unified Address composed of one or more receivers.
class ZCashUnifiedAddress extends ZCashAddress
    with Equality, LayoutSerializable {
  /// The list of receivers contained in this unified address.
  final List<ZUnifiedReceiver> receivers;

  /// Internal constructor assuming receivers and address are already validated.
  ZCashUnifiedAddress.__(
      {required List<ZUnifiedReceiver> receivers,
      required super.network,
      required super.address})
      : receivers = receivers.immutable,
        super.internal(addressType: ZCashAddressType.unified);

  /// Creates a ZCashUnifiedAddress from receivers, validating type constraints and encoding if needed.
  factory ZCashUnifiedAddress._(
      {required List<ZUnifiedReceiver> receivers,
      required ZCashNetwork network,
      String? address}) {
    if (receivers.isEmpty ||
        receivers.map((e) => e.type).toSet().length != receivers.length) {
      throw ZCashAddressException.invalidUnifiedReceivers;
    }
    if (receivers.any((e) => e.type == Typecode.p2pkh) &&
        receivers.any((e) => e.type == Typecode.p2sh)) {
      throw ZCashAddressException.invalidUnifiedReceivers;
    }
    address ??= ZCashUnifiedAddrEncoder()
        .encodeUnifiedReceivers(receivers, network: network);
    return ZCashUnifiedAddress.__(
        receivers: receivers..sort((a, b) => a.compareTo(b)),
        network: network,
        address: address);
  }

  /// Creates a Unified address from an encoded string, validating the network if provided.
  factory ZCashUnifiedAddress(String address, {ZCashNetwork? network}) {
    final decode = ZCashAddrDecoder()
        .decodeAddr(address, network: network, type: ZCashAddressType.unified);
    return ZCashUnifiedAddress.__(
        receivers: decode.unifiedReceiver ?? [],
        network: decode.network,
        address: address);
  }

  /// Deserializes a ZCashUnifiedAddress from its binary representation.
  factory ZCashUnifiedAddress.fromBytes(
      {required List<int> bytes, required ZCashNetwork network}) {
    final json = LayoutSerializable.deserialize(bytes: bytes, layout: layout());
    final receivers = json
        .valueEnsureAsList<Map<String, dynamic>>("receivers")
        .map((e) =>
            ZUnifiedReceiver.deserializeJson(e, UnifiedReceiverMode.address))
        .toList();
    return ZCashUnifiedAddress._(receivers: receivers, network: network);
  }

  /// Deserializes a ZCashUnifiedAddress from a JSON representation.
  factory ZCashUnifiedAddress.deserializeJson(
      {required Map<String, dynamic> json, required ZCashNetwork network}) {
    final receivers = json
        .valueEnsureAsList<Map<String, dynamic>>("receivers")
        .map((e) =>
            ZUnifiedReceiver.deserializeJson(e, UnifiedReceiverMode.address))
        .toList();
    return ZCashUnifiedAddress._(receivers: receivers, network: network);
  }

  /// Constructs a ZCashUnifiedAddress from a list of receivers.
  factory ZCashUnifiedAddress.fromReceivers(
      {required List<ZUnifiedReceiver> receivers,
      required ZCashNetwork network}) {
    return ZCashUnifiedAddress._(receivers: receivers, network: network);
  }

  /// Returns the binary layout definition for ZCashUnifiedAddress serialization.
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.dynamicVector(ZUnifiedReceiver.layout(),
          property: "receivers")
    ], property: property);
  }

  /// Returns the receiver matching the given typecode or throws if not found.
  T getReceiver<T extends ZUnifiedReceiver>(Typecode type) {
    return receivers.firstWhere(
      (e) => e.type == type,
      orElse: () {
        throw ZCashAddressException(
            "No receiver found matching this Unified NodeAddress typecode.");
      },
    ).cast<T>();
  }

  /// Serializes the ZCashUnifiedAddress to a JSON-compatible map.
  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "receivers": receivers.map((e) => e.toSerializeVariantJson()).toList()
    };
  }

  /// Returns the serialization layout for this address.
  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  /// Values used for equality comparison.
  @override
  List<dynamic> get variables => [address];

  @override
  String toString() {
    return address;
  }

  /// Attempts to extract a Transparent address from the unified receivers.
  @override
  ZCashTransparentAddress? tryToTransparentAddreses() {
    final p2sh = receivers.firstWhereNullable(
        (e) => e.type == Typecode.p2sh || e.type == Typecode.p2pkh);
    if (p2sh == null) return null;
    return switch (p2sh.type) {
      Typecode.p2sh =>
        ZCashP2shAddress.fromBytes(bytes: p2sh.data, network: network),
      Typecode.p2pkh =>
        ZCashP2pkhAddress.fromBytes(bytes: p2sh.data, network: network),
      _ => null
    };
  }

  /// Attempts to extract a P2SH address from the unified receivers.
  @override
  ZCashP2shAddress? tryToP2sh() {
    final p2sh = receivers.firstWhereNullable((e) => e.type == Typecode.p2sh);
    if (p2sh == null) return null;
    return ZCashP2shAddress.fromBytes(bytes: p2sh.data, network: network);
  }

  /// Attempts to extract a P2PKH address from the unified receivers.
  @override
  ZCashP2pkhAddress? tryToP2pkh() {
    final p2pkh = receivers.firstWhereNullable((e) => e.type == Typecode.p2pkh);
    if (p2pkh == null) return null;
    return ZCashP2pkhAddress.fromBytes(bytes: p2pkh.data, network: network);
  }

  /// Attempts to extract a Sapling payment address from the unified receivers.
  @override
  SaplingPaymentAddress? tryToSaplingPaymentAddress() {
    final payment =
        receivers.firstWhereNullable((e) => e.type == Typecode.sapling);
    if (payment == null) return null;
    return SaplingPaymentAddress.fromBytes(payment.data);
  }

  /// Attempts to extract a Sapling address from the unified receivers.
  @override
  SaplingAddress? tryToSaplingAddress() {
    final payment =
        receivers.firstWhereNullable((e) => e.type == Typecode.sapling);
    if (payment == null) return null;
    return SaplingAddress.fromBytes(bytes: payment.data, network: network);
  }

  /// Attempts to extract an Orchard address from the unified receivers.
  @override
  OrchardAddress? tryToOrchardAddress() {
    final orchard =
        receivers.firstWhereNullable((e) => e.type == Typecode.orchard);
    if (orchard == null) return null;
    return OrchardAddress.fromBytes(orchard.data);
  }

  /// Converts this address to another network.
  @override
  ZCashUnifiedAddress toNetwork(ZCashNetwork network) {
    if (network == this.network) return this;
    return ZCashUnifiedAddress.fromBytes(bytes: toBytes(), network: network);
  }

  /// Serializes the ZCashUnifiedAddress into its binary form.
  @override
  List<int> toBytes() {
    return toSerializeBytes();
  }
}
