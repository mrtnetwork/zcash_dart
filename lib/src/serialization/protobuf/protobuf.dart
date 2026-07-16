import 'package:blockchain_utils/proto/proto.dart';

abstract class ZcashProtoMessage extends IProtoMessage {
  const ZcashProtoMessage();

  static ProtoBufferDecoderResult decode(
    List<int> bytes,
    ProtoMessageConfig config,
  ) {
    final result = ProtoBufferDecoder.decode(
      bytes: bytes,
      messageConfig: config,
    );
    return result;
  }

  ZcashProtoTypeUrl get declarationId;
}

mixin IZcashProtoQueryMessage<RESPONSE extends ZcashProtoMessage>
    on ZcashProtoMessage {
  RESPONSE onQueryResponse(List<int> bytes);
}

abstract class ZcashProtoTypeUrl {
  abstract final String typeUrl;
  abstract final String? serviceUrl;
  String getServiceUrl();
}
