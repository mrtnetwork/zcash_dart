import 'package:blockchain_utils/bip/bip.dart';
import 'package:blockchain_utils/helper/extensions/extensions.dart';
import 'package:blockchain_utils/utils/binary/utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/orchard/merkle/merkle.dart';
import 'package:zcash_dart/src/provider/walletd/exception/exception.dart';
import 'package:zcash_dart/src/provider/walletd/proto_messages/cash/z/wallet/sdk/rpc/src/service.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/transparent.dart';

extension ExtGetAddressUtxosReply on ZWalletdGetAddressUtxosReply {
  TransparentUtxo toUtxo() {
    final txid = this.txid;
    final height = this.height ?? BigInt.zero;
    if (txid == null) {
      throw WalletdException.failed(
        "toUtxo",
        reason: "Unexpected service response. missing utxo tx id.",
      );
    }
    return TransparentUtxo(
      txHash: ZcashTxId(txid),
      value: valueZat ?? BigInt.zero,
      vout: index,
      blockHeight: height.toIntOrThrow,
    );
  }
}

extension ExtZcashProtocol on ZcashProtocol {
  ZWalletdShieldedProtocol toShieldedProtocol() {
    return switch (this) {
      ZcashProtocol.orchard => ZWalletdShieldedProtocol.orchard,
      ZcashProtocol.sapling => ZWalletdShieldedProtocol.sapling,
      ZcashProtocol.transparent =>
        throw WalletdException.failed(
          "toShieldedProtocol",
          reason: "Invalid shield protocol.",
        ),
    };
  }
}

extension ExtSubtreeRoot on ZWalletdSubtreeRoot {
  List<int> getRootHashes() {
    final hash = rootHash;
    if (hash == null) {
      throw WalletdException.failed(
        "getRootHashes",
        reason: "Unexpected service response. missing root hash.",
      );
    }
    return hash;
  }
}

extension ExtZWalletdTreeState on ZWalletdTreeState {
  ChainState toChainState() {
    final blockHash = hash;
    if (blockHash == null) {
      throw WalletdException.failed(
        "toChainState",
        reason: "Missing block hash",
      );
    }
    final height = this.height ?? BigInt.zero;

    final orchardTree = this.orchardTree;
    final saplingTree = this.saplingTree;
    return ChainState(
      blockHash: BytesUtils.fromHexString(blockHash).reversed.toList(),
      blockHeight: height.toIntOrThrow,
      finalOrchardTree:
          orchardTree == null
              ? null
              : OrchardCommitmentTree.deserialize(
                BytesUtils.fromHexString(orchardTree),
              ).toFrontier().frontier,
      finalSaplingTree:
          saplingTree == null
              ? null
              : SaplingCommitmentTree.deserialize(
                BytesUtils.fromHexString(saplingTree),
              ).toFrontier().frontier,
    );
  }
}

extension ExtZWalletdBlockID on ZWalletdBlockID {
  int getHeight() {
    final height = this.height;
    if (height == null) {
      throw WalletdException.failed(
        "getLatestBlock",
        reason: "Unexcpected provider response. Missing block height.",
      );
    }
    return height.toIntOrThrow;
  }
}

extension ExtZWalletdRawTransaction on ZWalletdRawTransaction {
  TransactionData toTransaction() {
    final data = this.data;
    if (data == null) {
      throw WalletdException.failed(
        "toTransaction",
        reason: "Unexcpected provider response. Missing transaction data.",
      );
    }
    return TransactionData.deserialize(data);
  }
}
