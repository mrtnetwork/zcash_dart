import 'package:zcash_dart/src/provider/walletd/core/request.dart';
import 'package:zcash_dart/src/provider/walletd/exception/exception.dart';
import 'package:zcash_dart/src/provider/walletd/extension/extensions.dart';
import 'package:zcash_dart/src/provider/walletd/proto_messages/cash/z/wallet/sdk/rpc/src/service.dart';
import 'package:zcash_dart/src/transparent/transparent.dart';

class WalletdRequestGetAddressUtxosWithAccountOwner
    extends ZcashWalletdRequest<List<TransparentUtxoWithOwner>> {
  final List<TransparentUtxoOwner> accounts;
  const WalletdRequestGetAddressUtxosWithAccountOwner(this.accounts);
  @override
  String get method =>
      "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetAddressUtxos";

  @override
  List<int> toBuffer() {
    final addresses = accounts.map((e) => e.address.address).toSet().toList();
    final request = ZWalletdGetAddressUtxosArg(addresses: addresses);
    return request.toBuffer();
  }

  @override
  List<TransparentUtxoWithOwner> onResonse(List<int> result) {
    if (accounts.isEmpty) return [];
    List<TransparentUtxoWithOwner> accountUtxos = [];
    final utxos =
        ZWalletdGetAddressUtxos().onQueryResponse(result).addressUtxos;
    for (final i in utxos) {
      final address = i.address;
      if (address == null && accounts.length != 1) {
        throw WalletdException.failed(
          "GetAddressUtxos",
          reason: "Missing utxo address.",
        );
      }
      final utxo = i.toUtxo();
      final owner =
          address == null
              ? accounts[0]
              : accounts.firstWhere(
                (e) => e.address.address == address,
                orElse:
                    () =>
                        throw WalletdException.failed(
                          "GetAddressUtxos",
                          reason: "Invalid utxo address.",
                        ),
              );
      accountUtxos.add(
        TransparentUtxoWithOwner(utxo: utxo, ownerDetails: owner),
      );
    }
    return accountUtxos;
  }
}
