import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';

/// Represents a Zcash Unified Address composed of one or more receivers.
class ZcashUnifiedAddress extends ZcashAddress
    with Equality, LayoutSerializable {
  /// The list of receivers contained in this unified address.
  final List<ZUnifiedReceiver> receivers;

  /// Internal constructor assuming receivers and address are already validated.
  ZcashUnifiedAddress.__({
    required List<ZUnifiedReceiver> receivers,
    required super.network,
    required super.address,
  }) : receivers = receivers.immutable,
       super.internal(
         addressType: ZcashAddressType.unified,
         supportedProtocols: [
           if (receivers.any((e) => e.type == Typecode.sapling))
             ZcashProtocol.sapling,
           if (receivers.any((e) => e.type == Typecode.orchard))
             ZcashProtocol.orchard,
           if (receivers.any(
             (e) => e.type == Typecode.p2pkh || e.type == Typecode.p2sh,
           ))
             ZcashProtocol.transparent,
         ],
       );

  /// Creates a ZcashUnifiedAddress from receivers, validating type constraints and encoding if needed.
  factory ZcashUnifiedAddress._({
    required List<ZUnifiedReceiver> receivers,
    required ZcashNetwork network,
    String? address,
  }) {
    if (receivers.isEmpty ||
        receivers.map((e) => e.type).toSet().length != receivers.length) {
      throw ZcashErrors.invalidUnifiedReceivers;
    }
    if (receivers.any((e) => e.type == Typecode.p2pkh) &&
        receivers.any((e) => e.type == Typecode.p2sh)) {
      throw ZcashErrors.invalidUnifiedReceivers;
    }
    address ??= ZcashUnifiedAddrEncoder().encodeUnifiedReceivers(
      receivers,
      network: network,
    );
    return ZcashUnifiedAddress.__(
      receivers: receivers..sort((a, b) => a.compareTo(b)),
      network: network,
      address: address,
    );
  }

  /// Creates a Unified address from an encoded string, validating the network if provided.
  factory ZcashUnifiedAddress(String address, {ZcashNetwork? network}) {
    final decode = ZcashAddrDecoder().decodeAddr(
      address,
      network: network,
      type: ZcashAddressType.unified,
    );
    return ZcashUnifiedAddress.__(
      receivers: decode.unifiedReceiver ?? [],
      network: decode.network,
      address: address,
    );
  }

  /// Deserializes a ZcashUnifiedAddress from its binary representation.
  factory ZcashUnifiedAddress.fromBytes({
    required List<int> bytes,
    required ZcashNetwork network,
  }) {
    final json = LayoutSerializable.deserialize(bytes: bytes, layout: layout());
    final receivers =
        json
            .valueEnsureAsList<Map<String, dynamic>>("receivers")
            .map(
              (e) => ZUnifiedReceiver.deserializeJson(
                e,
                UnifiedReceiverMode.address,
              ),
            )
            .toList();
    return ZcashUnifiedAddress._(receivers: receivers, network: network);
  }

  /// Deserializes a ZcashUnifiedAddress from a JSON representation.
  factory ZcashUnifiedAddress.deserializeJson({
    required Map<String, dynamic> json,
    required ZcashNetwork network,
  }) {
    final receivers =
        json
            .valueEnsureAsList<Map<String, dynamic>>("receivers")
            .map(
              (e) => ZUnifiedReceiver.deserializeJson(
                e,
                UnifiedReceiverMode.address,
              ),
            )
            .toList();
    return ZcashUnifiedAddress._(receivers: receivers, network: network);
  }

  /// Constructs a ZcashUnifiedAddress from a list of receivers.
  factory ZcashUnifiedAddress.fromReceivers({
    required List<ZUnifiedReceiver> receivers,
    required ZcashNetwork network,
  }) {
    return ZcashUnifiedAddress._(receivers: receivers, network: network);
  }

  /// Returns the binary layout definition for ZcashUnifiedAddress serialization.
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.dynamicVector(
        ZUnifiedReceiver.layout(),
        property: "receivers",
      ),
    ], property: property);
  }

  /// Returns the receiver matching the given typecode or throws if not found.
  T getReceiver<T extends ZUnifiedReceiver>(Typecode type) {
    return receivers
        .firstWhere(
          (e) => e.type == type,
          orElse: () {
            throw BuError(
              DefaultErrorType.notFound,
              "No receiver found matching this Unified NodeAddress typecode.",
            );
          },
        )
        .cast<T>();
  }

  /// Serializes the ZcashUnifiedAddress to a JSON-compatible map.
  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "receivers": receivers.map((e) => e.toSerializeVariantJson()).toList(),
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
  ZcashTransparentAddress? tryToTransparentAddreses() {
    final p2sh = receivers.firstWhereNullable(
      (e) => e.type == Typecode.p2sh || e.type == Typecode.p2pkh,
    );
    if (p2sh == null) return null;
    return switch (p2sh.type) {
      Typecode.p2sh => ZcashP2shAddress.fromBytes(
        bytes: p2sh.data,
        network: network,
      ),
      Typecode.p2pkh => ZcashP2pkhAddress.fromBytes(
        bytes: p2sh.data,
        network: network,
      ),
      _ => null,
    };
  }

  /// Attempts to extract a P2SH address from the unified receivers.
  @override
  ZcashP2shAddress? tryToP2sh() {
    final p2sh = receivers.firstWhereNullable((e) => e.type == Typecode.p2sh);
    if (p2sh == null) return null;
    return ZcashP2shAddress.fromBytes(bytes: p2sh.data, network: network);
  }

  /// Attempts to extract a P2PKH address from the unified receivers.
  @override
  ZcashP2pkhAddress? tryToP2pkh() {
    final p2pkh = receivers.firstWhereNullable((e) => e.type == Typecode.p2pkh);
    if (p2pkh == null) return null;
    return ZcashP2pkhAddress.fromBytes(bytes: p2pkh.data, network: network);
  }

  /// Attempts to extract a Sapling payment address from the unified receivers.
  @override
  SaplingPaymentAddress? tryToSaplingPaymentAddress() {
    final payment = receivers.firstWhereNullable(
      (e) => e.type == Typecode.sapling,
    );
    if (payment == null) return null;
    return SaplingPaymentAddress.fromBytes(payment.data);
  }

  /// Attempts to extract a Sapling address from the unified receivers.
  @override
  SaplingAddress? tryToSaplingAddress() {
    final payment = receivers.firstWhereNullable(
      (e) => e.type == Typecode.sapling,
    );
    if (payment == null) return null;
    return SaplingAddress.fromBytes(bytes: payment.data, network: network);
  }

  /// Attempts to extract an Orchard address from the unified receivers.
  @override
  OrchardAddress? tryToOrchardAddress() {
    final orchard = receivers.firstWhereNullable(
      (e) => e.type == Typecode.orchard,
    );
    if (orchard == null) return null;
    return OrchardAddress.fromBytes(orchard.data);
  }

  ZcashUnifiedAddress? tryOnlyOrchard() {
    final orchard = receivers.firstWhereNullable(
      (e) => e.type == Typecode.orchard,
    );
    if (orchard == null) return null;
    return ZcashUnifiedAddress.fromReceivers(
      receivers: [orchard],
      network: network,
    );
  }

  ZcashUnifiedAddress? tryOnlySapling() {
    final sapling = receivers.firstWhereNullable(
      (e) => e.type == Typecode.sapling,
    );
    if (sapling == null) return null;
    return ZcashUnifiedAddress.fromReceivers(
      receivers: [sapling],
      network: network,
    );
  }

  /// Converts this address to another network.
  @override
  ZcashUnifiedAddress toNetwork(ZcashNetwork network) {
    if (network == this.network) return this;
    return ZcashUnifiedAddress.fromBytes(bytes: toBytes(), network: network);
  }

  /// Serializes the ZcashUnifiedAddress into its binary form.
  @override
  BuBytes toBytes() {
    return toSerializeBytes();
  }

  /// return unified address only contains orchard receiver.
  @override
  ZcashAddress? toProtocolAddress(ZcashProtocol protocol) {
    if (protocol == ZcashProtocol.orchard) {
      if (supportedProtocols.contains(protocol)) {
        return ZcashUnifiedAddress.fromReceivers(
          receivers: [getReceiver<ReceiverOrchard>(Typecode.orchard)],
          network: network,
        );
      }
      return null;
    }
    return super.toProtocolAddress(protocol);
  }
}
