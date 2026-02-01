import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/transaction/bundle.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';
import 'package:zcash_dart/src/transaction/sighash_digest/types.dart';
import 'package:zcash_dart/src/sprout/transaction/bundle.dart';
import 'package:zcash_dart/src/transaction/types/transaction.dart';
import 'package:zcash_dart/src/transaction/types/version.dart';
import 'package:zcash_dart/src/transparent/transaction/bundle.dart';
import 'package:zcash_dart/src/transparent/transaction/input.dart';
import 'package:zcash_dart/src/transparent/transaction/output.dart';
import 'package:zcash_dart/src/value/value.dart';

class _TransactionDigestUtils {
  static const zcashOrchardHashPersonalization = "ZTxIdOrchardHash";
  static const zcashSaplingHashPersonalization = "ZTxIdSaplingHash";
  static const zcashTxPersonalizationPrefix = "ZcashTxHash_";

  static BLAKE2b hasher(List<int> personalization) => BLAKE2b(
      digestLength: QuickCrypto.blake2b256DigestSize,
      config: Blake2bConfig(personalization: personalization));
  static List<int> hashOrchardBundleTxIdData(OrchardBundle bundle) {
    final h = hasher(zcashOrchardHashPersonalization.codeUnits);
    final ch = hasher("ZTxIdOrcActCHash".codeUnits);
    final mh = hasher("ZTxIdOrcActMHash".codeUnits);
    final nh = hasher("ZTxIdOrcActNHash".codeUnits);
    for (final i in bundle.actions) {
      ch.update(i.nf.toBytes());
      ch.update(i.cmx.toBytes());
      ch.update(i.encryptedNote.epkBytes);
      ch.update(i.encryptedNote.encCiphertext.sublist(0, 52));

      mh.update(i.encryptedNote.encCiphertext.sublist(52, 564));

      nh.update(i.cvNet.toBytes());
      nh.update(i.rk.toBytes());
      nh.update(i.encryptedNote.encCiphertext.sublist(564));
      nh.update(i.encryptedNote.outCiphertext);
    }
    h.update(ch.digest());
    h.update(mh.digest());
    h.update(nh.digest());
    h.update([bundle.flags.toByte()]);
    h.update(bundle.balance.value.toI64LeBytes());
    h.update(bundle.anchor.toBytes());
    return h.digest();
  }

  static List<int> hashSaplingSpend(
      List<SaplingSpendDescription> shieldedSpends) {
    final h = hasher("ZTxIdSSpendsHash".codeUnits);
    if (shieldedSpends.isNotEmpty) {
      final ch = hasher("ZTxIdSSpendCHash".codeUnits);
      final nh = hasher("ZTxIdSSpendNHash".codeUnits);
      for (final i in shieldedSpends) {
        ch.update(i.nullifier.toBytes());

        nh.update(i.cv.toBytes());
        nh.update(i.anchor.toBytes());
        nh.update(i.rk.toBytes());
      }
      h.update(ch.digest());
      h.update(nh.digest());
    }

    return h.digest();
  }

  static List<int> hashSaplingOutputs(List<SaplingOutputDescription> outputs) {
    final h = hasher("ZTxIdSOutputHash".codeUnits);
    if (outputs.isNotEmpty) {
      final ch = hasher("ZTxIdSOutC__Hash".codeUnits);
      final mh = hasher("ZTxIdSOutM__Hash".codeUnits);
      final nh = hasher("ZTxIdSOutN__Hash".codeUnits);
      for (final i in outputs) {
        ch.update(i.cmu.toBytes());
        ch.update(i.ephemeralKey.toBytes());
        ch.update(i.encCiphertext.sublist(0, 52));
        mh.update(i.encCiphertext.sublist(52, 564));
        nh.update(i.cv.toBytes());
        nh.update(i.encCiphertext.sublist(564));
        nh.update(i.outCiphertext);
      }
      h.update(ch.digest());
      h.update(mh.digest());
      h.update(nh.digest());
    }

    return h.digest();
  }

  static List<int> hashSaplingTxId(SaplingBundle bundle) {
    final h = hasher(zcashSaplingHashPersonalization.codeUnits);
    if (!(bundle.shieldedOutputs.isEmpty && bundle.shieldedSpends.isEmpty)) {
      h.update(hashSaplingSpend(bundle.shieldedSpends));
      h.update(hashSaplingOutputs(bundle.shieldedOutputs));
      h.update(bundle.valueBalance.toBytes());
    }
    return h.digest();
  }

  static List<int> transparentPrevoutHash(List<TransparentTxInput> input) {
    final h = hasher("ZTxIdPrevoutHash".codeUnits);
    for (final i in input) {
      h.update(i.txId);
      h.update(i.txIndex.toU32LeBytes());
    }
    return h.digest();
  }

  static List<int> transparentSequenceHash(List<TransparentTxInput> input) {
    final h = hasher("ZTxIdSequencHash".codeUnits);
    for (final i in input) {
      h.update(i.sequence.toU32LeBytes());
    }
    return h.digest();
  }

  static List<int> transparentOutputsHash(List<TransparentTxOutput> output) {
    final h = hasher("ZTxIdOutputsHash".codeUnits);
    for (final i in output) {
      h.update(i.amount.toI64LeBytes());
      h.update(encodeAsVarint(i.scriptPubKey.toBytes()));
    }
    return h.digest();
  }

  static List<int> encodeAsVarint(List<int> bytes) {
    return LayoutConst.varintVector(LayoutConst.u8(), property: "script")
        .serialize(bytes);
  }

  static TransparentDigest transparentDigests(TransparentBundle bundle) {
    return TransparentDigest(
        prevoutsDigest: transparentPrevoutHash(bundle.vin),
        sequenceDigest: transparentSequenceHash(bundle.vin),
        outputsDigest: transparentOutputsHash(bundle.vout));
  }

  static List<int> hashHeaderTxId(
      {required TxVersion version,
      required NetworkUpgrade branchId,
      required int lockTime,
      required int expiryHeight}) {
    final h = hasher("ZTxIdHeadersHash".codeUnits);
    h.update(version.header().toU32LeBytes());
    h.update(version.type.groupId!.toU32LeBytes());
    h.update(branchId.branchId.toU32LeBytes());
    h.update(lockTime.toU32LeBytes());
    h.update(expiryHeight.toU32LeBytes());
    return h.digest();
  }

  static List<int> hashTransparentTxidData(TransparentDigest? digest) {
    final h = hasher("ZTxIdTranspaHash".codeUnits);
    if (digest != null) {
      h.update(digest.prevoutsDigest);
      h.update(digest.sequenceDigest);
      h.update(digest.outputsDigest);
    }
    return h.digest();
  }

  static List<int> toHash({
    required TxVersion verion,
    required NetworkUpgrade branchId,
    required List<int> headerDigest,
    required List<int> transparentDigest,
    List<int>? saplingDigest,
    List<int>? orchardDigest,
  }) {
    final h = hasher([
      ...zcashTxPersonalizationPrefix.codeUnits,
      ...branchId.branchId.toU32LeBytes()
    ]);
    h.update(headerDigest);
    h.update(transparentDigest);
    saplingDigest ??= QuickCrypto.blake2b256Hash([],
        personalization: zcashSaplingHashPersonalization.codeUnits);
    h.update(saplingDigest);
    orchardDigest ??= QuickCrypto.blake2b256Hash([],
        personalization: zcashOrchardHashPersonalization.codeUnits);
    h.update(orchardDigest);
    return h.digest();
  }
}

class _SighashV5Utils {
  static List<int> _transparentSigDigest(
      {required TransparentBundle? transparent,
      required TransparentDigest? digest,
      required SignableInput input,
      List<Script> scriptPubKeys = const [],
      List<BigInt> amounts = const []}) {
    if (transparent == null || digest == null) {
      return _TransactionDigestUtils.hashTransparentTxidData(digest);
    }
    if (transparent.vin.isEmpty ||
        (transparent.vin.length == 1 && transparent.vin[0].coinbase)) {
      return _TransactionDigestUtils.hashTransparentTxidData(digest);
    }
    final hashtype = input.hashType;
    final flagAnyoneCanPay =
        hashtype & BitcoinOpCodeConst.sighashAnyoneCanPay != 0;
    final flagSingle = hashtype & BitcoinOpCodeConst.sighashMask ==
        BitcoinOpCodeConst.sighashSingle;
    final flagNone = hashtype & BitcoinOpCodeConst.sighashMask ==
        BitcoinOpCodeConst.sighashNone;

    final prevoutsDigest = flagAnyoneCanPay
        ? _TransactionDigestUtils.transparentPrevoutHash([])
        : digest.prevoutsDigest;

    final amountsDigest = () {
      final h = _TransactionDigestUtils.hasher("ZTxTrAmountsHash".codeUnits);
      if (!flagAnyoneCanPay) {
        for (final amount in amounts) {
          h.update(amount.toI64LeBytes());
        }
      }
      return h.digest();
    }();

    final scriptsDigest = () {
      final h = _TransactionDigestUtils.hasher("ZTxTrScriptsHash".codeUnits);
      if (!flagAnyoneCanPay) {
        for (final script in scriptPubKeys) {
          h.update(_TransactionDigestUtils.encodeAsVarint(script.toBytes()));
        }
      }
      return h.digest();
    }();

    final sequenceDigest = flagAnyoneCanPay
        ? _TransactionDigestUtils.transparentSequenceHash([])
        : digest.sequenceDigest;
    final outputsDigest = () {
      if (input.type.isTransparent) {
        final index = input.cast<TransparentSignableInput>().index;
        if (flagSingle) {
          if (index < transparent.vout.length) {
            return _TransactionDigestUtils.transparentOutputsHash(
                [transparent.vout[index]]);
          } else {
            return _TransactionDigestUtils.transparentOutputsHash([]);
          }
        } else if (flagNone) {
          return _TransactionDigestUtils.transparentOutputsHash([]);
        }
      }
      return digest.outputsDigest;
    }();

    // S.2g.i – S.2g.iv
    final ch = _TransactionDigestUtils.hasher("Zcash___TxInHash".codeUnits);
    if (input.type.isTransparent) {
      final transparentInput = input.cast<TransparentSignableInput>();
      final txin = transparent.vin[transparentInput.index];
      ch.update(txin.txId);
      ch.update(txin.txIndex.toU32LeBytes());

      ch.update(transparentInput.amount.toI64LeBytes());
      ch.update(_TransactionDigestUtils.encodeAsVarint(
          transparentInput.sciptPubKey.toBytes()));
      ch.update(txin.sequence.toU32LeBytes());
    }
    final txinSigDigest = ch.digest();

    final h = _TransactionDigestUtils.hasher("ZTxIdTranspaHash".codeUnits);
    h.update([hashtype]);
    h.update(prevoutsDigest);
    h.update(amountsDigest);
    h.update(scriptsDigest);
    h.update(sequenceDigest);
    h.update(outputsDigest);
    h.update(txinSigDigest);

    return h.digest();
  }

  static List<int> generate(
      {required TransactionData tx,
      required TxDigestsPart digest,
      required SignableInput input,
      NetworkUpgrade? branchId,
      List<Script> scriptPubKeys = const [],
      List<BigInt> amounts = const []}) {
    final hash = _transparentSigDigest(
        transparent: tx.transparentBundle,
        digest: digest.transparentDigest,
        input: input,
        amounts: amounts,
        scriptPubKeys: scriptPubKeys);
    return _TransactionDigestUtils.toHash(
        verion: tx.version,
        branchId: branchId ?? tx.consensusBranchId!,
        headerDigest: digest.headerDigest,
        transparentDigest: hash,
        orchardDigest: digest.orchardDigest,
        saplingDigest: digest.saplingDigest);
  }
}

class _SighashV4Utils {
  static const String _zcashOutputsHashPersonalization = 'ZcashOutputsHash';

  static List<int> _transparentPrevoutHash(List<TransparentTxInput> inputs) {
    final inputsBytes =
        inputs.expand((e) => [...e.txId, ...e.txIndex.toU32LeBytes()]).toList();

    return _TransactionDigestUtils.hasher("ZcashPrevoutHash".codeUnits)
        .update(inputsBytes)
        .digest();
  }

  static List<int> _sequenceHash(List<TransparentTxInput> inputs) {
    final inputsBytes =
        inputs.expand((e) => e.sequence.toU32LeBytes()).toList();
    return _TransactionDigestUtils.hasher("ZcashSequencHash".codeUnits)
        .update(inputsBytes)
        .digest();
  }

  static List<int> _outputsHash(List<TransparentTxOutput> outputs) {
    final inputsBytes = outputs
        .expand((e) => [
              ...e.amount.toI64LeBytes(),
              ..._TransactionDigestUtils.encodeAsVarint(
                  e.scriptPubKey.toBytes())
            ])
        .toList();
    return _TransactionDigestUtils.hasher(
            _zcashOutputsHashPersonalization.codeUnits)
        .update(inputsBytes)
        .digest();
  }

  static List<int> _singleOutputHash(TransparentTxOutput output) {
    final inputsBytes = [
      ...output.amount.toI64LeBytes(),
      ..._TransactionDigestUtils.encodeAsVarint(output.scriptPubKey.toBytes())
    ];
    return _TransactionDigestUtils.hasher(
            _zcashOutputsHashPersonalization.codeUnits)
        .update(inputsBytes)
        .digest();
  }

  static List<int> _joinsSplitsHash(
      {required List<SproutJsDescription> joinssplits,
      required List<int> joinsplitPubKey}) {
    final joinsBytes = [
      ...joinssplits.map((e) => e.toSerializeBytes()).expand((e) => e),
      ...joinsplitPubKey
    ];
    return _TransactionDigestUtils.hasher("ZcashJSplitsHash".codeUnits)
        .update(joinsBytes)
        .digest();
  }

  static List<int> _shieldedSpendsHash(
      List<SaplingSpendDescription> shieldedSpends) {
    return _TransactionDigestUtils.hasher("ZcashSSpendsHash".codeUnits)
        .update(shieldedSpends
            .expand((e) => e.toSerializeBytes(withAuthSig: false))
            .toList())
        .digest();
  }

  static List<int> _shieldedOutputsHash(
      List<SaplingOutputDescription> shieldedOutputs) {
    return _TransactionDigestUtils.hasher("ZcashSOutputHash".codeUnits)
        .update(shieldedOutputs.expand((e) => e.toSerializeBytes()).toList())
        .digest();
  }

  static List<int> generate(
      {required TransactionData tx,
      required SignableInput signableInput,
      NetworkUpgrade? branchId}) {
    final hashType = signableInput.hashType;
    branchId ??= tx.consensusBranchId;
    final groupId = tx.version.type.groupId;
    if (!tx.version.hasOverwinter()) {
      throw ArgumentException.invalidOperationArguments(
        "generate",
        reason:
            'Signature hashing for pre-overwinter transactions is not supported.',
      );
    }
    if (branchId == null || groupId == null) {
      throw ArgumentException.invalidOperationArguments("generate",
          reason: 'Invalid transaction version.');
    }

    final personalization = [
      ..."ZcashSigHash".codeUnits,
      ...branchId.branchId.toU32LeBytes()
    ];
    final h = _TransactionDigestUtils.hasher(personalization);

    final zero32 =
        List<int>.filled(QuickCrypto.blake2b256DigestSize, 0).immutable;

    void condUpdate(bool cond, List<int> Function() bytes) {
      if (cond) {
        h.update(bytes());
        return;
      }
      h.update(zero32);
    }

    // Header fields
    h.update(tx.version.headerBytes());
    h.update(groupId.toU32LeBytes());
    final transparentInputs = tx.transparentBundle?.vin ?? [];
    final transparentOutputs = tx.transparentBundle?.vout ?? [];
    condUpdate((hashType & BitcoinOpCodeConst.sighashAnyoneCanPay) == 0,
        () => _transparentPrevoutHash(transparentInputs));

    condUpdate(
        (hashType & BitcoinOpCodeConst.sighashAnyoneCanPay) == 0 &&
            (hashType & BitcoinOpCodeConst.sighashMask) !=
                BitcoinOpCodeConst.sighashSingle &&
            (hashType & BitcoinOpCodeConst.sighashMask) !=
                BitcoinOpCodeConst.sighashNone,
        () => _sequenceHash(transparentInputs));

    // Outputs
    if ((hashType & BitcoinOpCodeConst.sighashMask) !=
            BitcoinOpCodeConst.sighashSingle &&
        (hashType & BitcoinOpCodeConst.sighashMask) !=
            BitcoinOpCodeConst.sighashNone) {
      h.update(_outputsHash(transparentOutputs));
    } else if ((hashType & BitcoinOpCodeConst.sighashMask) ==
        BitcoinOpCodeConst.sighashSingle) {
      if (signableInput is TransparentSignableInput &&
          tx.transparentBundle != null &&
          signableInput.index < tx.transparentBundle!.vout.length) {
        h.update(
          _singleOutputHash(transparentOutputs[signableInput.index]),
        );
      } else {
        h.update(zero32);
      }
    } else {
      h.update(zero32);
    }
    final joinsplits = tx.sproutBundle?.joinsplits ?? [];
    condUpdate(
        joinsplits.isNotEmpty,
        () => _joinsSplitsHash(
            joinssplits: joinsplits,
            joinsplitPubKey: tx.sproutBundle!.joinsplitPubkey));
    final shieldedSpends = tx.saplingBundle?.shieldedSpends ?? [];
    final shieldedOutputs = tx.saplingBundle?.shieldedOutputs ?? [];
    if (tx.version.hasSapling()) {
      condUpdate(
          shieldedSpends.isNotEmpty, () => _shieldedSpendsHash(shieldedSpends));
      condUpdate(shieldedOutputs.isNotEmpty,
          () => _shieldedOutputsHash(shieldedOutputs));
    }
    h.update(tx.locktime.toU32LeBytes());
    h.update(tx.expiryHeight.toU32LeBytes());

    if (tx.version.hasSapling()) {
      final balance = tx.saplingBundle?.valueBalance ?? ZAmount.zero();
      h.update(balance.toBytes());
    }

    h.update(hashType.toU32LeBytes());

    // Signable input
    if (signableInput.type.isTransparent) {
      final bundle = tx.transparentBundle;
      if (bundle == null) {
        throw ArgumentException.invalidOperationArguments(
          "generate",
          reason:
              'Requested to sign a transparent input, but none are present.',
        );
      }
      final transparentInput = signableInput.cast<TransparentSignableInput>();

      final txin = bundle.vin[transparentInput.index];
      final data = [
        ...txin.txId,
        ...txin.txIndex.toU32LeBytes(),
        ..._TransactionDigestUtils.encodeAsVarint(
            transparentInput.scriptCode.toBytes()),
        ...transparentInput.amount.toI64LeBytes(),
        ...txin.sequence.toU32LeBytes(),
      ];
      h.update(data);
    }
    return h.digest();
  }
}

/// Generates sighash values for signing Zcash transactions (v4 and v5).
class SighashGenerator {
  /// Generates a v4 sighash for a given transaction and input, optionally using a branch ID.
  static List<int> v4(
          {required TransactionData tx,
          required SignableInput signableInput,
          NetworkUpgrade? branchId}) =>
      _SighashV4Utils.generate(
          tx: tx, signableInput: signableInput, branchId: branchId);

  /// Generates a v5 sighash for a transaction, input, and digest.
  /// [scriptPubKeys] all transparent input scriptPubKeys
  /// [amounts] all transparent input amounts.
  static List<int> v5(
          {required TransactionData tx,
          required TxDigestsPart digest,
          required SignableInput input,
          NetworkUpgrade? branchId,
          List<Script> scriptPubKeys = const [],
          List<BigInt> amounts = const []}) =>
      _SighashV5Utils.generate(
          tx: tx,
          digest: digest,
          input: input,
          amounts: amounts,
          branchId: branchId,
          scriptPubKeys: scriptPubKeys);
}

/// Utility class for computing transaction digests and generating Zcash transaction IDs.
class TxIdDigester {
  /// Computes the header digest for a transaction given version, branch, locktime, and expiry.
  static List<int> _digestHeader(
      {required TxVersion version,
      required NetworkUpgrade branchId,
      required int locktime,
      required int expiryHeight}) {
    return _TransactionDigestUtils.hashHeaderTxId(
        version: version,
        branchId: branchId,
        lockTime: locktime,
        expiryHeight: expiryHeight);
  }

  /// Computes the Orchard bundle digest, or returns null if no bundle.
  static List<int>? _digestOrchard(OrchardBundle? bundle) {
    if (bundle == null) return null;
    return _TransactionDigestUtils.hashOrchardBundleTxIdData(bundle);
  }

  /// Computes the Sapling bundle digest, or returns null if no bundle.
  static List<int>? _digestSapling(SaplingBundle? bundle) {
    if (bundle == null) return null;
    return _TransactionDigestUtils.hashSaplingTxId(bundle);
  }

  /// Computes the transparent inputs/outputs digest, or null if none present.
  static TransparentDigest? _digestTransparent(TransparentBundle? bundle) {
    bool hasTrasparent =
        bundle != null && (bundle.vin.isNotEmpty || bundle.vout.isNotEmpty);
    if (hasTrasparent) {
      return _TransactionDigestUtils.transparentDigests(bundle);
    }
    return null;
  }

  /// Converts transaction digests into a ZCashTxId using branch-specific personalization.
  static ZCashTxId _toTxId({
    required TxDigestsPart digest,
    required NetworkUpgrade branchId,
  }) {
    final h = _TransactionDigestUtils.hasher([
      ..._TransactionDigestUtils.zcashTxPersonalizationPrefix.codeUnits,
      ...branchId.branchId.toU32LeBytes()
    ]);
    h.update(digest.headerDigest);
    final transparent = _TransactionDigestUtils.hashTransparentTxidData(
        digest.transparentDigest);
    h.update(transparent);
    final saplingDigest = digest.saplingDigest ??
        QuickCrypto.blake2b256Hash([],
            personalization: _TransactionDigestUtils
                .zcashSaplingHashPersonalization.codeUnits);
    h.update(saplingDigest);
    final orchardDigest = digest.orchardDigest ??
        QuickCrypto.blake2b256Hash([],
            personalization: _TransactionDigestUtils
                .zcashOrchardHashPersonalization.codeUnits);
    h.update(orchardDigest);
    return ZCashTxId(h.digest());
  }

  /// Computes the ZCashTxId for a transaction.
  static ZCashTxId txToTxId(TransactionData data) {
    final branchId = data.consensusBranchId;
    if (branchId == null) {
      throw ArgumentException.invalidOperationArguments("toTxId",
          name: "branchId", reason: "Missing branch id.");
    }
    final digest = txToDigest(data);
    return _toTxId(digest: digest, branchId: branchId);
  }

  /// Computes the digests for all parts of a transaction (header, transparent, sapling, orchard).
  static TxDigestsPart txToDigest(TransactionData data) {
    final branchId = data.consensusBranchId;
    if (branchId == null) {
      throw ArgumentException.invalidOperationArguments("toTxId",
          name: "branchId", reason: "Missing branch id.");
    }
    return TxDigestsPart(
        headerDigest: _digestHeader(
            version: data.version,
            branchId: branchId,
            locktime: data.locktime,
            expiryHeight: data.expiryHeight),
        transparentDigest: _digestTransparent(data.transparentBundle),
        orchardDigest: _digestOrchard(data.orchardBundle),
        saplingDigest: _digestSapling(data.saplingBundle));
  }
}
