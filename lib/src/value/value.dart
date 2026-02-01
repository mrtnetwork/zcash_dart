import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/exception.dart';

/// Represents an amount of Zcash in zatoshi with safe arithmetic and serialization.
class ZAmount with Equality, LayoutSerializable {
  /// Maximum possible Zcash amount in zatoshi.
  static BigInt get maxZatoshi => BigInt.parse('21000000000000000');
  final BigInt value;
  const ZAmount._(this.value);

  /// Creates a ZAmount from a BigInt value, enforcing 128-bit range.
  ZAmount(BigInt value) : value = value.asI128;

  /// Returns a zero ZAmount.
  factory ZAmount.zero() {
    return ZAmount._(BigInt.zero);
  }

  /// Creates a ZAmount from an integer value.
  factory ZAmount.from(int amount) => ZAmount._(BigInt.from(amount));

  /// Creates a ZAmount from a zatoshi value with range validation.
  factory ZAmount.fromZatoshi(BigInt amount) {
    if (amount.isNegative || amount > maxZatoshi) {
      throw ArgumentException.invalidOperationArguments("fromZatoshi",
          reason: "Inavlid zatoshi amount.");
    }
    return ZAmount._(amount);
  }

  /// Creates a ZAmount from a ZEC string amount.
  factory ZAmount.fromZec(String amount) {
    return ZAmount.fromZatoshi(AmountConverter.btc.toUnit(amount));
  }

  /// Deserializes a ZAmount from JSON.
  factory ZAmount.deserializeJson(Map<String, dynamic> json) {
    final bool isNegative = json.valueAsBool("is_negative");
    return ZAmount.fromMagnitudeSign(
        json.valueAsBigInt("magnitude"), isNegative);
  }

  /// Creates a ZAmount from magnitude and sign.
  factory ZAmount.fromMagnitudeSign(BigInt magnitude, bool isNegative) {
    switch (isNegative) {
      case false:
        return ZAmount._(magnitude.asU64);
      case true:
        return ZAmount._(-(magnitude.asU64));
    }
  }

  /// Returns the binary layout for serialization.
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU64(property: "magnitude"),
      LayoutConst.boolean(property: "is_negative")
    ], property: property);
  }

  /// Returns the magnitude and sign of the amount.
  ({BigInt value, bool isNegative}) magnitudeSign() {
    if (value.isNegative) {
      return (value: (-value).asU64, isNegative: true);
    } else {
      return (value: value.asU64, isNegative: false);
    }
  }

  /// Creates a ZAmount from an 8-byte little-endian representation.
  factory ZAmount.fromBytes(List<int> bytes) {
    if (bytes.length != 8) {
      throw ArgumentException.invalidOperationArguments("ZAmount",
          reason: "Invalid bytes length.");
    }
    return ZAmount._(BigintUtils.fromBytes(bytes, byteOrder: Endian.little));
  }

  /// Serializes the ZAmount to an 8-byte little-endian array.
  List<int> toBytes() {
    return value.toI64LeBytes();
  }

  /// Converts the value to a 64-bit binary representation.
  List<bool> toBits() => BigintUtils.toBinaryBool(value.asI64, bitLength: 64);

  /// Returns true if the amount is zero.
  bool isZero() => value == BigInt.zero;

  /// Returns true if the amount is negative.
  bool isNegative() => value.isNegative;

  /// Adds another ZAmount or BigInt, throwing on overflow.
  ZAmount operator +(Object other) {
    try {
      BigInt value = this.value;
      switch (other) {
        case ZAmount amount:
          value = (value + amount.value).asI128;
          break;
        case BigInt amount:
          value = (value + amount).asI128;
          break;
        default:
          throw DartZCashPluginException("Unsupported operation.");
      }

      return ZAmount._(value);
    } catch (_) {}
    throw DartZCashPluginException("Sum failed. ZAmount overflowed.");
  }

  /// Subtracts another ZAmount or BigInt, throwing on overflow.
  ZAmount operator -(Object other) {
    try {
      BigInt value = this.value;
      switch (other) {
        case ZAmount amount:
          value = (value - amount.value).asI128;
          break;
        case BigInt amount:
          value = (value - amount).asI128;
          break;
        default:
          throw DartZCashPluginException("Unsupported operation.");
      }

      return ZAmount._(value);
    } catch (_) {}
    throw DartZCashPluginException("Subtraction failed. ZAmount overflowed.");
  }

  /// Converts the value to a 64-bit signed integer, throwing if out of range.
  BigInt toI64() {
    try {
      return value.asI64;
    } catch (_) {}
    throw DartZCashPluginException("Value out of range.");
  }

  /// Returns the amount in zatoshi, throwing if out of range.
  BigInt toZatoshi() {
    try {
      return ZAmount.fromZatoshi(value).value;
    } catch (_) {}
    throw DartZCashPluginException("Value out of range.");
  }

  /// Returns a ZAmount clamped to zatoshi range.
  ZAmount asZatoshi() {
    try {
      return ZAmount._(value.toU64);
    } catch (_) {}
    throw DartZCashPluginException("Value out of range.");
  }

  /// Returns a ZAmount clamped to 64-bit signed integer range.
  ZAmount asI64() => ZAmount._(toI64());

  @override
  List<dynamic> get variables => [value];

  /// Returns the layout for serialization.
  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  /// Serializes the amount to JSON with magnitude and sign.
  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "magnitude": value.isNegative ? (-value).asU64 : value,
      "is_negative": value.isNegative
    };
  }

  /// Returns a string representation of the ZAmount.
  @override
  String toString() => "ZAmount($value)";
}
