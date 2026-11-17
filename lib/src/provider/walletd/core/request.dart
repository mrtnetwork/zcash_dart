import 'package:blockchain_utils/chain/types/network.dart';
import 'package:blockchain_utils/encoding/encoding.dart';
import 'package:blockchain_utils/helper/helper.dart';
import 'package:blockchain_utils/service/service.dart';

abstract class ZcashWalletdRequest<RESULT>
    extends IGRPCServiceRequest<RESULT, ZcashWalletdRequestDetails> {
  const ZcashWalletdRequest();
  String get method;

  List<int> toBuffer();

  @override
  ZcashWalletdRequestDetails buildRequest(int _) {
    return ZcashWalletdRequestDetails(
      buffer: toBuffer(),
      requestMethod: method,
    );
  }
}

class ZcashWalletdRequestDetails extends BaseGRPCServiceRequestParams
    with CborTagSerializable {
  final String requestMethod;
  final List<int> buffer;
  // final ZcashWalletdRequest<RESULT> request;

  ZcashWalletdRequestDetails({
    required List<int> buffer,
    required this.requestMethod,
  }) : buffer = buffer.asImmutableBytes;
  factory ZcashWalletdRequestDetails.deserialize({
    List<int>? bytes,
    CborObject? obj,
  }) {
    final values = CborTagSerializable.decodeTaggedValue(
      identifier: BlockchainNetwork.zcash.identifier,
      cborBytes: bytes,
      cborObject: obj,
    );
    return ZcashWalletdRequestDetails(
      buffer: values.rawValueAt(0),
      requestMethod: values.rawValueAt(1),
    );
  }

  @override
  String method() {
    return requestMethod;
  }

  @override
  List<int> toBuffer() {
    return buffer;
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      BlockchainNetwork.zcash.identifier;

  @override
  List<CborObject?> get serializationItems => [
    CborBytesValue(buffer),
    requestMethod.toCbor(),
  ];

  @override
  Uri encodeUrl(String uri) {
    return Uri.parse(uri);
  }
}
