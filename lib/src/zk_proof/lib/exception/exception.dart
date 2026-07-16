import 'package:blockchain_utils/cbor/cbor.dart';
import 'package:blockchain_utils/helper/extensions/extensions.dart';
import 'package:zcash_dart/src/exception/zcash.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';
import 'package:zcash_dart/src/zk_proof/lib/types/config.dart';

class ZKLibException extends BaseDartZcashPluginException {
  final ZKLibResponseCode? code;
  const ZKLibException(super.message, {this.code, super.details});

  static ZKLibException operationFailed(
    String operation, {
    Map<String, String?>? details,
    String? reason,
    ZKLibResponseCode? code,
  }) {
    return ZKLibException(
      "Operation failure during $operation",
      details: {"reason": reason, ...details ?? {}}.notNullValue,
      code: code,
    );
  }

  factory ZKLibException.deserialize({List<int>? bytes, CborObject? obj}) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: ZcashSerializationIdentifier.zklibError,
      cborBytes: bytes,
      cborObject: obj,
    );
    return ZKLibException(
      values.rawValueAt(0),
      details: values.maybeRawMapAt<String, String?>(1),
      code: values.maybeRawValueAt<ZKLibResponseCode, int>(
        2,
        (i) => ZKLibResponseCode.fromCode(i),
      ),
    );
  }

  @override
  ZcashSerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.zklibError;

  @override
  List<CborObject<Object?>?> get serializationItems => [
    ...super.serializationItems,
    code?.code.toCbor(),
  ];
}
