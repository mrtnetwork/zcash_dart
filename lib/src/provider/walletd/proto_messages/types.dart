import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/serialization/protobuf/protobuf.dart';

enum DefaultZcashProtoTypeUrl implements ZcashProtoTypeUrl {
  cashZWalletSdkRpcBlockID(typeUrl: '/cash.z.wallet.sdk.rpc.BlockID'),
  cashZWalletSdkRpcBlockRange(typeUrl: '/cash.z.wallet.sdk.rpc.BlockRange'),
  cashZWalletSdkRpcTxFilter(typeUrl: '/cash.z.wallet.sdk.rpc.TxFilter'),
  cashZWalletSdkRpcRawTransaction(
    typeUrl: '/cash.z.wallet.sdk.rpc.RawTransaction',
  ),
  cashZWalletSdkRpcSendResponse(typeUrl: '/cash.z.wallet.sdk.rpc.SendResponse'),
  cashZWalletSdkRpcChainSpec(typeUrl: '/cash.z.wallet.sdk.rpc.ChainSpec'),
  cashZWalletSdkRpcEmpty(typeUrl: '/cash.z.wallet.sdk.rpc.Empty'),
  cashZWalletSdkRpcLightdInfo(typeUrl: '/cash.z.wallet.sdk.rpc.LightdInfo'),
  cashZWalletSdkRpcTransparentAddressBlockFilter(
    typeUrl: '/cash.z.wallet.sdk.rpc.TransparentAddressBlockFilter',
  ),
  cashZWalletSdkRpcDuration(typeUrl: '/cash.z.wallet.sdk.rpc.Duration'),
  cashZWalletSdkRpcPingResponse(typeUrl: '/cash.z.wallet.sdk.rpc.PingResponse'),
  cashZWalletSdkRpcAddress(typeUrl: '/cash.z.wallet.sdk.rpc.Address'),
  cashZWalletSdkRpcAddressList(typeUrl: '/cash.z.wallet.sdk.rpc.AddressList'),
  cashZWalletSdkRpcBalance(typeUrl: '/cash.z.wallet.sdk.rpc.Balance'),
  cashZWalletSdkRpcGetMempoolTxRequest(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetMempoolTxRequest',
  ),
  cashZWalletSdkRpcTreeState(typeUrl: '/cash.z.wallet.sdk.rpc.TreeState'),
  cashZWalletSdkRpcGetSubtreeRootsArg(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetSubtreeRootsArg',
  ),
  cashZWalletSdkRpcSubtreeRoot(typeUrl: '/cash.z.wallet.sdk.rpc.SubtreeRoot'),
  cashZWalletSdkRpcGetAddressUtxosArg(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetAddressUtxosArg',
  ),
  cashZWalletSdkRpcGetAddressUtxosReply(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetAddressUtxosReply',
  ),
  cashZWalletSdkRpcGetAddressUtxosReplyList(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetAddressUtxosReplyList',
  ),
  cashZWalletSdkRpcGetLatestBlock(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetLatestBlock',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock",
  ),
  cashZWalletSdkRpcGetBlock(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetBlock',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlock",
  ),
  cashZWalletSdkRpcGetBlockNullifiers(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetBlockNullifiers',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockNullifiers",
  ),
  cashZWalletSdkRpcGetBlockRange(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetBlockRange',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockRange",
  ),
  cashZWalletSdkRpcGetBlockRangeNullifiers(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetBlockRangeNullifiers',
    serviceUrl:
        "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockRangeNullifiers",
  ),
  cashZWalletSdkRpcGetTransaction(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetTransaction',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTransaction",
  ),
  cashZWalletSdkRpcSendTransaction(
    typeUrl: '/cash.z.wallet.sdk.rpc.SendTransaction',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/SendTransaction",
  ),
  cashZWalletSdkRpcGetTaddressTxids(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetTaddressTxids',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressTxids",
  ),
  cashZWalletSdkRpcGetTaddressTransactions(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetTaddressTransactions',
    serviceUrl:
        "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressTransactions",
  ),
  cashZWalletSdkRpcGetTaddressBalance(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetTaddressBalance',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressBalance",
  ),
  cashZWalletSdkRpcGetTaddressBalanceStream(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetTaddressBalanceStream',
    serviceUrl:
        "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTaddressBalanceStream",
  ),
  cashZWalletSdkRpcGetMempoolTx(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetMempoolTx',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetMempoolTx",
  ),
  cashZWalletSdkRpcGetMempoolStream(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetMempoolStream',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetMempoolStream",
  ),
  cashZWalletSdkRpcGetTreeState(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetTreeState',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTreeState",
  ),
  cashZWalletSdkRpcGetLatestTreeState(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetLatestTreeState',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestTreeState",
  ),
  cashZWalletSdkRpcGetSubtreeRoots(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetSubtreeRoots',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetSubtreeRoots",
  ),
  cashZWalletSdkRpcGetAddressUtxos(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetAddressUtxos',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetAddressUtxos",
  ),
  cashZWalletSdkRpcGetAddressUtxosStream(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetAddressUtxosStream',
    serviceUrl:
        "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetAddressUtxosStream",
  ),
  cashZWalletSdkRpcGetLightdInfo(
    typeUrl: '/cash.z.wallet.sdk.rpc.GetLightdInfo',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo",
  ),
  cashZWalletSdkRpcPing(
    typeUrl: '/cash.z.wallet.sdk.rpc.Ping',
    serviceUrl: "/cash.z.wallet.sdk.rpc.CompactTxStreamer/Ping",
  ),
  cashZWalletSdkRpcChainMetadata(
    typeUrl: '/cash.z.wallet.sdk.rpc.ChainMetadata',
  ),
  cashZWalletSdkRpcCompactBlock(typeUrl: '/cash.z.wallet.sdk.rpc.CompactBlock'),
  cashZWalletSdkRpcCompactTx(typeUrl: '/cash.z.wallet.sdk.rpc.CompactTx'),
  cashZWalletSdkRpcCompactTxIn(typeUrl: '/cash.z.wallet.sdk.rpc.CompactTxIn'),
  cashZWalletSdkRpcTxOut(typeUrl: '/cash.z.wallet.sdk.rpc.TxOut'),
  cashZWalletSdkRpcCompactSaplingSpend(
    typeUrl: '/cash.z.wallet.sdk.rpc.CompactSaplingSpend',
  ),
  cashZWalletSdkRpcCompactSaplingOutput(
    typeUrl: '/cash.z.wallet.sdk.rpc.CompactSaplingOutput',
  ),
  cashZWalletSdkRpcCompactOrchardAction(
    typeUrl: '/cash.z.wallet.sdk.rpc.CompactOrchardAction',
  );

  @override
  final String typeUrl;
  @override
  final String? serviceUrl;
  const DefaultZcashProtoTypeUrl({required this.typeUrl, this.serviceUrl});
  static DefaultZcashProtoTypeUrl? fromUrl(String? value) {
    return DefaultZcashProtoTypeUrl.values.firstWhereNullable(
      (e) => e.typeUrl == value || e.serviceUrl == value,
    );
  }

  @override
  String getServiceUrl() {
    final serviceUrl = this.serviceUrl;
    if (serviceUrl == null) {
      throw BuError(
        DefaultErrorType.invalidState,
        "Missing proto service url.",
        details: {"type_url": typeUrl},
      );
    }
    return serviceUrl;
  }
}
