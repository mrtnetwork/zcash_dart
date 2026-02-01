import 'package:blockchain_utils/service/service.dart';
import 'package:zcash_dart/src/provider/walletd/core/request.dart';

mixin ZCashWalletdServiceProvider
    implements GRPCServiceProvider<ZCashWalletdRequestDetails> {}
