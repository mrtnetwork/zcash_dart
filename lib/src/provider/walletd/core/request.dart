import 'package:blockchain_utils/service/service.dart';

abstract class ZCashWalletdRequest<RESULT>
    extends BaseGRPCServiceRequest<RESULT, ZCashWalletdRequestDetails<RESULT>> {
  const ZCashWalletdRequest();
  String get method;

  List<int> toBuffer();

  @override
  ZCashWalletdRequestDetails<RESULT> buildRequest() {
    return ZCashWalletdRequestDetails(this);
  }
}

class ZCashWalletdRequestDetails<RESULT>
    extends BaseGRPCServiceRequestParams<RESULT> {
  final ZCashWalletdRequest<RESULT> request;

  const ZCashWalletdRequestDetails(this.request);

  @override
  String method() {
    return request.method;
  }

  @override
  List<int> toBuffer() {
    return request.toBuffer();
  }

  @override
  RESULT onResponse(List<int> bytes) => request.onResonse(bytes);
}
