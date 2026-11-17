import 'package:blockchain_utils/helper/extensions/extensions.dart';
import 'package:blockchain_utils/protocol/protocol.dart';
import 'package:blockchain_utils/utils/utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/orchard/merkle/merkle.dart';
import 'package:zcash_dart/src/provider/walletd/proto_messages/cash/z/wallet/sdk/rpc/src/service.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/transparent.dart';

extension ExtGetAddressUtxosReply on ZWalletdGetAddressUtxosReply {
  TransparentUtxo toUtxo() {
    final txid = this.txid;
    final height = this.height ?? BigInt.zero;
    if (txid == null) {
      throw ZcashErrors.walletdFailed(
        "toUtxo",
        reason: "Unexpected service response. missing utxo tx id.",
      );
    }
    return TransparentUtxo(
      txHash: ZcashTxId(txid),
      value: valueZat ?? BigInt.zero,
      vout: index ?? 0,
      blockHeight: height.asSafeInt,
    );
  }
}

extension ExtZcashProtocol on ZcashProtocol {
  ZWalletdShieldedProtocol toShieldedProtocol() {
    return switch (this) {
      ZcashProtocol.orchard => ZWalletdShieldedProtocol.orchard,
      ZcashProtocol.sapling => ZWalletdShieldedProtocol.sapling,
      ZcashProtocol.transparent =>
        throw ZcashErrors.walletdFailed(
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
      throw ZcashErrors.walletdFailed(
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
      throw ZcashErrors.walletdFailed(
        "toChainState",
        reason: "Missing block hash",
      );
    }
    final height = this.height ?? BigInt.zero;

    final orchardTree = this.orchardTree;
    final saplingTree = this.saplingTree;
    final ironwoodTree = this.ironwoodTree;
    return ChainState(
      blockHash: BytesUtils.fromHexString(blockHash).reversed.toList(),
      blockHeight: height.asSafeInt,
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
      finalIronwoodTree:
          ironwoodTree == null
              ? null
              : OrchardCommitmentTree.deserialize(
                BytesUtils.fromHexString(ironwoodTree),
              ).toFrontier().frontier,
    );
  }
}

extension ExtZWalletdBlockID on ZWalletdBlockID {
  int getHeight() {
    final height = this.height;
    if (height == null) {
      throw ZcashErrors.walletdFailed(
        "getLatestBlock",
        reason: "Unexcpected provider response. Missing block height.",
      );
    }
    return height.asSafeInt;
  }
}

extension ExtZWalletdRawTransaction on ZWalletdRawTransaction {
  TransactionData toTransaction() {
    final data = this.data;
    if (data == null) {
      throw ZcashErrors.walletdFailed(
        "toTransaction",
        reason: "Unexcpected provider response. Missing transaction data.",
      );
    }
    return TransactionData.deserialize(data);
  }
}
