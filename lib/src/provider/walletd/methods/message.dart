import 'package:zcash_dart/src/provider/walletd/walletd.dart';
import 'package:zcash_dart/src/serialization/protobuf/protobuf.dart';

class ZcashGrpcRequestMessage<Response extends ZcashProtoMessage>
    extends ZcashWalletdRequest<Response> {
  ZcashGrpcRequestMessage({required this.request});

  final IZcashProtoQueryMessage<Response> request;

  @override
  List<int> toBuffer() {
    return request.toBuffer();
  }

  @override
  String get method => request.declarationId.getServiceUrl();

  @override
  Response onResponse(List<int> result) {
    return request.onQueryResponse(result);
  }
}
