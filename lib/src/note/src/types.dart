import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/exception.dart';
import 'package:zcash_dart/src/note/src/exception.dart';
import 'package:zcash_dart/src/note/src/note_encryption.dart';
import 'package:zcash_dart/src/orchard/transaction/commitment.dart';
import 'package:zcash_dart/src/sapling/transaction/commitment.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/value/value.dart';

enum Zip212Enforcement { off, gracePeriod, on }

abstract class Nullifier<T extends Object>
    with Equality, LayoutSerializable, CborTagSerializable {
  final T inner;
  const Nullifier(this.inner);
  factory Nullifier.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.nullifier,
      cborBytes: bytes,
      cborObject: obj,
    );
    final type = ZcashProtocol.fromValue(values.rawValueAt(0));
    final Nullifier nullifier = switch (type) {
      ZcashProtocol.orchard => OrchardNullifier.fromBytes(values.rawValueAt(1)),
      ZcashProtocol.sapling => SaplingNullifier(values.rawValueAt(1)),
      ZcashProtocol.transparent =>
        throw DartZcashPluginException("Invalid nullifier protocol."),
    };
    return nullifier.cast();
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    final inner = toBytes();
    assert(inner.length == 32);
    return {"inner": inner};
  }

  List<int> toBytes();
  @override
  List<dynamic> get variables => [inner];

  ZcashProtocol get protocol;

  @override
  List<CborObject?> get serializationItems => [
    protocol.value.toCbor(),
    CborBytesValue(toBytes()),
  ];

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.nullifier;

  E cast<E extends Nullifier>() {
    if (this is! E) {
      throw CastFailedException<E>(value: this);
    }
    return this as E;
  }
}

abstract class Note with LayoutSerializable, Equality {
  const Note();
  abstract final ZAmount value;
}

class EphemeralKeyBytes with LayoutSerializable, Equality {
  final List<int> inner;
  EphemeralKeyBytes(List<int> bytes)
    : inner =
          bytes
              .exc(
                length: 32,
                operation: "EphemeralKeyBytes",
                reason: "Invalid ephemeral key bytes length.",
              )
              .asImmutableBytes;
  factory EphemeralKeyBytes.deserializeJson(Map<String, dynamic> json) {
    return EphemeralKeyBytes(json.valueAsBytes("inner"));
  }
  factory EphemeralKeyBytes.random() {
    return EphemeralKeyBytes(JubJubNativePoint.random().toBytes());
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlob32(property: "inner"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"inner": inner};
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  List<int> toBytes() => inner.clone();

  @override
  List<dynamic> get variables => [inner];

  JubJubNativePoint toPoint() => JubJubNativePoint.fromBytes(inner);
}

class BatchOutputDecryptionResult<
  EXTRACTEDCOMMITMENT extends Object,
  OUTPUT extends ShieldedOutput<EXTRACTEDCOMMITMENT>,
  NOTE extends Object,
  RECIPIENT extends Object
> {
  final OUTPUT output;
  final NOTE note;
  final RECIPIENT recipient;
  final List<int>? memo;
  const BatchOutputDecryptionResult({
    required this.output,
    required this.note,
    required this.recipient,
    required this.memo,
  });
}

class BatchIVKDecryptionResult<
  INCOMINGVIEWINGKEY extends Object,
  NOTE extends Object,
  RECIPIENT extends Object
> {
  final INCOMINGVIEWINGKEY ivk;
  final NOTE note;
  final RECIPIENT recipient;
  final List<int>? memo;
  const BatchIVKDecryptionResult({
    required this.ivk,
    required this.note,
    required this.recipient,
    required this.memo,
  });
}

abstract mixin class ShieldedOutput<EXTRACTEDCOMMITMENT extends Object> {
  EphemeralKeyBytes get ephemeralKey;
  EXTRACTEDCOMMITMENT cmstar();
  List<int> cmstarBytes();
  List<int> get encCiphertext;
  List<int> get encCiphertextCompact;
  (List<int>, List<int>)? splitCiphertextAtTag() {
    final bytes = encCiphertext;
    final tagLoc = bytes.length - NoteEncryptionConst.aeadTagSize;
    assert(tagLoc > 0);
    if (tagLoc <= 0) return null;
    if (tagLoc < 0) {
      throw NoteEncryptionException.failed(
        "splitCiphertextAtTag",
        reason: "Invalid compact note bytes length",
      );
    }
    final plaintext = bytes.sublist(0, tagLoc);
    return (plaintext, bytes);
  }

  T cast<T extends ShieldedOutput>() {
    if (this is! T) {
      throw CastFailedException<T>(value: this);
    }
    return this as T;
  }
}

abstract class NoteEncryption<
  EPHEMERALSECRETKEY extends Object,
  EPHEMERALPUBLICKEY extends Object,
  NOTE extends Object,
  OUTGOINGVIEWINGKEY extends Object
> {
  final EPHEMERALSECRETKEY esk;
  final EPHEMERALPUBLICKEY epk;
  final NOTE note;
  final List<int> memo;
  final OUTGOINGVIEWINGKEY? ovk;
  const NoteEncryption({
    required this.esk,
    required this.epk,
    required this.note,
    required this.memo,
    required this.ovk,
  });
}
