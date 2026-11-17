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
  static const zcashOrchardV6HashPersonalization = "ZTxIdOrchardH_v6";
  static const zcashIronwoodHashPersonalization = "ZTxIdIronwd_H_v6";
  static const zcashIronwoodCompactPersonalization = "ZTxIdIrnActCH_v6";
  static const zcashIronwoodMemosPersonalization = "ZTxIdIrnActMH_v6";
  static const zcashIronwoodNonCompactPersonalization = "ZTxIdIrnActNH_v6";
  static const zcashSaplingHashPersonalization = "ZTxIdSaplingHash";
  static const zcashSaplingSpendsNonCompactV6Personalization =
      "ZTxIdSSpendNH_v6";
  static const zcashSaplingSpendsNonCompactPersonalization = "ZTxIdSSpendNHash";
  static const zcashTxPersonalizationPrefix = "ZcashTxHash_";

  static BuSerializableHash _hasher(List<int> personalization) =>
      QuickCrypto.blake2bInstance(
        digestLength: QuickCrypto.blake2b256DigestSize,
        config: Blake2Config.blake2b(personalization: personalization),
      );
  static List<int> hashOrchardBundleTxIdData(
    OrchardBundle bundle, {
    TxVersionType version = TxVersionType.v5,
  }) {
    // Orchard V6 reuses V5 action-level personalizations, only the top-level
    // string gains `_v6` and the anchor moves to the auth digest (ZIP 229).
    final isV6 = version == TxVersionType.v6;
    final topPersonalization =
        isV6
            ? zcashOrchardV6HashPersonalization
            : zcashOrchardHashPersonalization;
    final h = _hasher(topPersonalization.codeUnits);
    final ch = _hasher("ZTxIdOrcActCHash".codeUnits);
    final mh = _hasher("ZTxIdOrcActMHash".codeUnits);
    final nh = _hasher("ZTxIdOrcActNHash".codeUnits);
    try {
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
      h.update([bundle.flags.toByteForVersion(bundle.bundleVersion)]);
      h.update(bundle.balance.value.toI64LeBytes());
      if (!isV6) {
        h.update(bundle.anchor.toBytes());
      }
      return h.digest();
    } finally {
      h.clean();
      ch.clean();
      nh.clean();
      mh.clean();
    }
  }

  /// Ironwood txid digest: Orchard-shaped with fresh `_v6` personalizations
  /// throughout, anchor excluded (in auth digest). Mirrors
  /// `ironwood_v6_domain` in librustzcash.
  static List<int> hashIronwoodBundleTxIdData(OrchardBundle bundle) {
    final h = _hasher(zcashIronwoodHashPersonalization.codeUnits);
    final ch = _hasher(zcashIronwoodCompactPersonalization.codeUnits);
    final mh = _hasher(zcashIronwoodMemosPersonalization.codeUnits);
    final nh = _hasher(zcashIronwoodNonCompactPersonalization.codeUnits);
    try {
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
      h.update([bundle.flags.toByteForVersion(bundle.bundleVersion)]);
      h.update(bundle.balance.value.toI64LeBytes());
      return h.digest();
    } finally {
      h.clean();
      ch.clean();
      nh.clean();
      mh.clean();
    }
  }

  /// Empty-bundle commitments are domain-separated per pool/tx version.
  static List<int> emptyOrchardDigest(TxVersionType version) {
    final personalization =
        version == TxVersionType.v6
            ? zcashOrchardV6HashPersonalization
            : zcashOrchardHashPersonalization;
    return QuickCrypto.blake2b256Hash(
      [],
      personalization: personalization.codeUnits,
    );
  }

  static List<int> emptyIronwoodDigest() {
    return QuickCrypto.blake2b256Hash(
      [],
      personalization: zcashIronwoodHashPersonalization.codeUnits,
    );
  }

  static List<int> hashSaplingSpend(
    List<SaplingSpendDescription> shieldedSpends, {
    TxVersionType version = TxVersionType.v5,
  }) {
    final h = _hasher("ZTxIdSSpendsHash".codeUnits);
    try {
      if (shieldedSpends.isNotEmpty) {
        final ch = _hasher("ZTxIdSSpendCHash".codeUnits);
        // V6 uses a distinct noncompact personalization and omits the anchor
        // (ZIP 229). Mirrors `sapling_spends_noncompact_personalization`.
        final nhPersonalization =
            version == TxVersionType.v6
                ? zcashSaplingSpendsNonCompactV6Personalization
                : zcashSaplingSpendsNonCompactPersonalization;
        final nh = _hasher(nhPersonalization.codeUnits);
        try {
          for (final i in shieldedSpends) {
            ch.update(i.nullifier.toBytes());

            nh.update(i.cv.toBytes());
            if (version != TxVersionType.v6) {
              nh.update(i.anchor.toBytes());
            }
            nh.update(i.rk.toBytes());
          }
          h.update(ch.digest());
          h.update(nh.digest());
        } finally {
          ch.clean();
          nh.clean();
        }
      }

      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> hashSaplingOutputs(List<SaplingOutputDescription> outputs) {
    final h = _hasher("ZTxIdSOutputHash".codeUnits);
    try {
      if (outputs.isNotEmpty) {
        final ch = _hasher("ZTxIdSOutC__Hash".codeUnits);
        final mh = _hasher("ZTxIdSOutM__Hash".codeUnits);
        final nh = _hasher("ZTxIdSOutN__Hash".codeUnits);
        try {
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
        } finally {
          ch.clean();
          mh.clean();
          nh.clean();
        }
      }

      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> hashSaplingTxId(
    SaplingBundle bundle, {
    TxVersionType version = TxVersionType.v5,
  }) {
    final h = _hasher(zcashSaplingHashPersonalization.codeUnits);
    try {
      if (!(bundle.shieldedOutputs.isEmpty && bundle.shieldedSpends.isEmpty)) {
        h.update(hashSaplingSpend(bundle.shieldedSpends, version: version));
        h.update(hashSaplingOutputs(bundle.shieldedOutputs));
        h.update(bundle.valueBalance.toBytes());
      }
      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> transparentPrevoutHash(List<TransparentTxInput> input) {
    final h = _hasher("ZTxIdPrevoutHash".codeUnits);
    try {
      for (final i in input) {
        h.update(i.txId.hash);
        h.update(i.txIndex.toU32LeBytes());
      }
      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> transparentSequenceHash(List<TransparentTxInput> input) {
    final h = _hasher("ZTxIdSequencHash".codeUnits);
    try {
      for (final i in input) {
        h.update(i.sequence.toU32LeBytes());
      }
      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> transparentOutputsHash(List<TransparentTxOutput> output) {
    final h = _hasher("ZTxIdOutputsHash".codeUnits);
    try {
      for (final i in output) {
        h.update(i.amount.toI64LeBytes());
        h.update(encodeAsVarint(i.scriptPubKey.toBytes()));
      }
      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> encodeAsVarint(List<int> bytes) {
    return LayoutConst.varintVector(
      LayoutConst.u8(),
      property: "script",
    ).serialize(bytes);
  }

  static TransparentDigest transparentDigests(TransparentBundle bundle) {
    return TransparentDigest(
      prevoutsDigest: transparentPrevoutHash(bundle.vin),
      sequenceDigest: transparentSequenceHash(bundle.vin),
      outputsDigest: transparentOutputsHash(bundle.vout),
    );
  }

  static List<int> hashHeaderTxId({
    required TxVersion version,
    required ZcashNetworkProtocol branchId,
    required int lockTime,
    required int expiryHeight,
  }) {
    final h = _hasher("ZTxIdHeadersHash".codeUnits);
    try {
      h.update(version.header().toU32LeBytes());
      h.update(version.type.groupId!.toU32LeBytes());
      h.update(branchId.branchId.toU32LeBytes());
      h.update(lockTime.toU32LeBytes());
      h.update(expiryHeight.toU32LeBytes());
      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> hashTransparentTxidData(TransparentDigest? digest) {
    final h = _hasher("ZTxIdTranspaHash".codeUnits);
    try {
      if (digest != null) {
        h.update(digest.prevoutsDigest);
        h.update(digest.sequenceDigest);
        h.update(digest.outputsDigest);
      }
      return h.digest();
    } finally {
      h.clean();
    }
  }

  static List<int> toHash({
    required TxVersion verion,
    required ZcashNetworkProtocol branchId,
    required List<int> headerDigest,
    required List<int> transparentDigest,
    List<int>? saplingDigest,
    List<int>? orchardDigest,
    List<int>? ironwoodDigest,
  }) {
    final h = _hasher([
      ...zcashTxPersonalizationPrefix.codeUnits,
      ...branchId.branchId.toU32LeBytes(),
    ]);
    try {
      h.update(headerDigest);
      h.update(transparentDigest);
      saplingDigest ??= QuickCrypto.blake2b256Hash(
        [],
        personalization: zcashSaplingHashPersonalization.codeUnits,
      );
      h.update(saplingDigest);
      orchardDigest ??= emptyOrchardDigest(verion.type);
      h.update(orchardDigest);
      // V6 commits to the Ironwood digest as a fifth component (ZIP 229).
      if (verion.type == TxVersionType.v6) {
        ironwoodDigest ??= emptyIronwoodDigest();
        h.update(ironwoodDigest);
      }
      return h.digest();
    } finally {
      h.clean();
    }
  }
}

class _SighashV5Utils {
  static List<int> _transparentSigDigest({
    required TransparentBundle? transparent,
    required TransparentDigest? digest,
    required SignableInput input,
    List<Script> scriptPubKeys = const [],
    List<BigInt> amounts = const [],
  }) {
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
    final flagSingle =
        hashtype & BitcoinOpCodeConst.sighashMask ==
        BitcoinOpCodeConst.sighashSingle;
    final flagNone =
        hashtype & BitcoinOpCodeConst.sighashMask ==
        BitcoinOpCodeConst.sighashNone;

    final prevoutsDigest =
        flagAnyoneCanPay
            ? _TransactionDigestUtils.transparentPrevoutHash([])
            : digest.prevoutsDigest;

    final amountsDigest = () {
      final h = _TransactionDigestUtils._hasher("ZTxTrAmountsHash".codeUnits);
      try {
        if (!flagAnyoneCanPay) {
          for (final amount in amounts) {
            h.update(amount.toI64LeBytes());
          }
        }
        return h.digest();
      } finally {
        h.clean();
      }
    }();

    final scriptsDigest = () {
      final h = _TransactionDigestUtils._hasher("ZTxTrScriptsHash".codeUnits);
      try {
        if (!flagAnyoneCanPay) {
          for (final script in scriptPubKeys) {
            h.update(_TransactionDigestUtils.encodeAsVarint(script.toBytes()));
          }
        }
        return h.digest();
      } finally {
        h.clean();
      }
    }();

    final sequenceDigest =
        flagAnyoneCanPay
            ? _TransactionDigestUtils.transparentSequenceHash([])
            : digest.sequenceDigest;
    final outputsDigest = () {
      if (input.type.isTransparent) {
        final index = input.cast<TransparentSignableInput>().index;
        if (flagSingle) {
          if (index < transparent.vout.length) {
            return _TransactionDigestUtils.transparentOutputsHash([
              transparent.vout[index],
            ]);
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
    final ch = _TransactionDigestUtils._hasher("Zcash___TxInHash".codeUnits);
    if (input.type.isTransparent) {
      final transparentInput = input.cast<TransparentSignableInput>();
      final txin = transparent.vin[transparentInput.index];
      ch.update(txin.txId.hash);
      ch.update(txin.txIndex.toU32LeBytes());

      ch.update(transparentInput.amount.toI64LeBytes());
      ch.update(
        _TransactionDigestUtils.encodeAsVarint(
          transparentInput.sciptPubKey.toBytes(),
        ),
      );
      ch.update(txin.sequence.toU32LeBytes());
    }
    final txinSigDigest = ch.digest();

    final h = _TransactionDigestUtils._hasher("ZTxIdTranspaHash".codeUnits);
    try {
      h.update([hashtype]);
      h.update(prevoutsDigest);
      h.update(amountsDigest);
      h.update(scriptsDigest);
      h.update(sequenceDigest);
      h.update(outputsDigest);
      h.update(txinSigDigest);

      return h.digest();
    } finally {
      h.clean();
      ch.clean();
    }
  }

  static List<int> generate({
    required TransactionData tx,
    required TxDigestsPart digest,
    required SignableInput input,
    ZcashNetworkProtocol? branchId,
    List<Script> scriptPubKeys = const [],
    List<BigInt> amounts = const [],
  }) {
    final hash = _transparentSigDigest(
      transparent: tx.transparentBundle,
      digest: digest.transparentDigest,
      input: input,
      amounts: amounts,
      scriptPubKeys: scriptPubKeys,
    );
    return _TransactionDigestUtils.toHash(
      verion: tx.version,
      branchId: branchId ?? tx.consensusBranchId!,
      headerDigest: digest.headerDigest,
      transparentDigest: hash,
      orchardDigest: digest.orchardDigest,
      saplingDigest: digest.saplingDigest,
      ironwoodDigest: digest.ironwoodDigest,
    );
  }
}

/// V6 sighash reuses the V5 transparent sig digest; only the txid hash
/// gains the Ironwood component (ZIP 229 / `sighash_v6.rs`).
class _SighashV6Utils {
  static List<int> generate({
    required TransactionData tx,
    required TxDigestsPart digest,
    required SignableInput input,
    ZcashNetworkProtocol? branchId,
    List<Script> scriptPubKeys = const [],
    List<BigInt> amounts = const [],
  }) => _SighashV5Utils.generate(
    tx: tx,
    digest: digest,
    input: input,
    branchId: branchId,
    scriptPubKeys: scriptPubKeys,
    amounts: amounts,
  );
}

class _SighashV4Utils {
  static const String _zcashOutputsHashPersonalization = 'ZcashOutputsHash';

  static List<int> _transparentPrevoutHash(List<TransparentTxInput> inputs) {
    final inputsBytes =
        inputs
            .expand((e) => [...e.txId.hash, ...e.txIndex.toU32LeBytes()])
            .toList();
    final h = _TransactionDigestUtils._hasher("ZcashPrevoutHash".codeUnits);

    try {
      return h.update(inputsBytes).digest();
    } finally {
      h.clean();
    }
  }

  static List<int> _sequenceHash(List<TransparentTxInput> inputs) {
    final inputsBytes =
        inputs.expand((e) => e.sequence.toU32LeBytes()).toList();
    final h = _TransactionDigestUtils._hasher("ZcashSequencHash".codeUnits);
    try {
      return h.update(inputsBytes).digest();
    } finally {
      h.clean();
    }
  }

  static List<int> _outputsHash(List<TransparentTxOutput> outputs) {
    final inputsBytes =
        outputs
            .expand(
              (e) => [
                ...e.amount.toI64LeBytes(),
                ..._TransactionDigestUtils.encodeAsVarint(
                  e.scriptPubKey.toBytes(),
                ),
              ],
            )
            .toList();
    final h = _TransactionDigestUtils._hasher(
      _zcashOutputsHashPersonalization.codeUnits,
    );
    try {
      return h.update(inputsBytes).digest();
    } finally {
      h.clean();
    }
  }

  static List<int> _singleOutputHash(TransparentTxOutput output) {
    final inputsBytes = [
      ...output.amount.toI64LeBytes(),
      ..._TransactionDigestUtils.encodeAsVarint(output.scriptPubKey.toBytes()),
    ];
    final h = _TransactionDigestUtils._hasher(
      _zcashOutputsHashPersonalization.codeUnits,
    );
    try {
      return h.update(inputsBytes).digest();
    } finally {
      h.clean();
    }
  }

  static List<int> _joinsSplitsHash({
    required List<SproutJsDescription> joinssplits,
    required List<int> joinsplitPubKey,
  }) {
    final joinsBytes = [
      ...joinssplits.map((e) => e.toSerializeBytes()).expand((e) => e),
      ...joinsplitPubKey,
    ];
    final h = _TransactionDigestUtils._hasher("ZcashJSplitsHash".codeUnits);
    try {
      return h.update(joinsBytes).digest();
    } finally {
      h.clean();
    }
  }

  static List<int> _shieldedSpendsHash(
    List<SaplingSpendDescription> shieldedSpends,
  ) {
    final h = _TransactionDigestUtils._hasher("ZcashSSpendsHash".codeUnits);
    try {
      return h
          .update(
            shieldedSpends
                .expand((e) => e.toSerializeBytes(withAuthSig: false))
                .toList(),
          )
          .digest();
    } finally {
      h.clean();
    }
  }

  static List<int> _shieldedOutputsHash(
    List<SaplingOutputDescription> shieldedOutputs,
  ) {
    final h = _TransactionDigestUtils._hasher("ZcashSOutputHash".codeUnits);
    try {
      return h
          .update(shieldedOutputs.expand((e) => e.toSerializeBytes()).toList())
          .digest();
    } finally {
      h.clean();
    }
  }

  static List<int> generate({
    required TransactionData tx,
    required SignableInput signableInput,
    ZcashNetworkProtocol? branchId,
  }) {
    final hashType = signableInput.hashType;
    branchId ??= tx.consensusBranchId;
    final groupId = tx.version.type.groupId;
    if (!tx.version.hasOverwinter()) {
      throw CoreErrors.invalidOperationArguments(
        "generate",
        reason:
            'Signature hashing for pre-overwinter transactions is not supported.',
      );
    }
    if (branchId == null || groupId == null) {
      throw CoreErrors.invalidOperationArguments(
        "generate",
        reason: 'Invalid transaction version.',
      );
    }

    final personalization = [
      ..."ZcashSigHash".codeUnits,
      ...branchId.branchId.toU32LeBytes(),
    ];
    final h = _TransactionDigestUtils._hasher(personalization);
    try {
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
      condUpdate(
        (hashType & BitcoinOpCodeConst.sighashAnyoneCanPay) == 0,
        () => _transparentPrevoutHash(transparentInputs),
      );

      condUpdate(
        (hashType & BitcoinOpCodeConst.sighashAnyoneCanPay) == 0 &&
            (hashType & BitcoinOpCodeConst.sighashMask) !=
                BitcoinOpCodeConst.sighashSingle &&
            (hashType & BitcoinOpCodeConst.sighashMask) !=
                BitcoinOpCodeConst.sighashNone,
        () => _sequenceHash(transparentInputs),
      );

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
          h.update(_singleOutputHash(transparentOutputs[signableInput.index]));
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
          joinsplitPubKey: tx.sproutBundle!.joinsplitPubkey,
        ),
      );
      final shieldedSpends = tx.saplingBundle?.shieldedSpends ?? [];
      final shieldedOutputs = tx.saplingBundle?.shieldedOutputs ?? [];
      if (tx.version.hasSapling()) {
        condUpdate(
          shieldedSpends.isNotEmpty,
          () => _shieldedSpendsHash(shieldedSpends),
        );
        condUpdate(
          shieldedOutputs.isNotEmpty,
          () => _shieldedOutputsHash(shieldedOutputs),
        );
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
          throw CoreErrors.invalidOperationArguments(
            "generate",
            reason:
                'Requested to sign a transparent input, but none are present.',
          );
        }
        final transparentInput = signableInput.cast<TransparentSignableInput>();

        final txin = bundle.vin[transparentInput.index];
        final data = [
          ...txin.txId.hash,
          ...txin.txIndex.toU32LeBytes(),
          ..._TransactionDigestUtils.encodeAsVarint(
            transparentInput.scriptCode.toBytes(),
          ),
          ...transparentInput.amount.toI64LeBytes(),
          ...txin.sequence.toU32LeBytes(),
        ];
        h.update(data);
      }
      return h.digest();
    } finally {
      h.clean();
    }
  }
}

/// Generates sighash values for signing Zcash transactions (v4, v5 and v6).
class SighashGenerator {
  /// Generates a v4 sighash for a given transaction and input, optionally using a branch ID.
  static List<int> v4({
    required TransactionData tx,
    required SignableInput signableInput,
    ZcashNetworkProtocol? branchId,
  }) => _SighashV4Utils.generate(
    tx: tx,
    signableInput: signableInput,
    branchId: branchId,
  );

  /// Generates a v5 sighash for a transaction, input, and digest.
  /// [scriptPubKeys] all transparent input scriptPubKeys
  /// [amounts] all transparent input amounts.
  static List<int> v5({
    required TransactionData tx,
    required TxDigestsPart digest,
    required SignableInput input,
    ZcashNetworkProtocol? branchId,
    List<Script> scriptPubKeys = const [],
    List<BigInt> amounts = const [],
  }) => _SighashV5Utils.generate(
    tx: tx,
    digest: digest,
    input: input,
    amounts: amounts,
    branchId: branchId,
    scriptPubKeys: scriptPubKeys,
  );

  /// Generates a v6 sighash (ZIP 229). Transparent digest logic matches V5;
  /// the txid hash additionally commits to the Ironwood bundle digest.
  static List<int> v6({
    required TransactionData tx,
    required TxDigestsPart digest,
    required SignableInput input,
    ZcashNetworkProtocol? branchId,
    List<Script> scriptPubKeys = const [],
    List<BigInt> amounts = const [],
  }) => _SighashV6Utils.generate(
    tx: tx,
    digest: digest,
    input: input,
    amounts: amounts,
    branchId: branchId,
    scriptPubKeys: scriptPubKeys,
  );

  /// Dispatches to v5 or v6 based on the transaction version.
  static List<int> forVersion({
    required TransactionData tx,
    required TxDigestsPart digest,
    required SignableInput input,
    ZcashNetworkProtocol? branchId,
    List<Script> scriptPubKeys = const [],
    List<BigInt> amounts = const [],
  }) {
    if (tx.version.type == TxVersionType.v6) {
      return v6(
        tx: tx,
        digest: digest,
        input: input,
        branchId: branchId,
        scriptPubKeys: scriptPubKeys,
        amounts: amounts,
      );
    }
    return v5(
      tx: tx,
      digest: digest,
      input: input,
      branchId: branchId,
      scriptPubKeys: scriptPubKeys,
      amounts: amounts,
    );
  }
}

/// Utility class for computing transaction digests and generating Zcash transaction IDs.
class TxIdDigester {
  /// Computes the header digest for a transaction given version, branch, locktime, and expiry.
  static List<int> _digestHeader({
    required TxVersion version,
    required ZcashNetworkProtocol branchId,
    required int locktime,
    required int expiryHeight,
  }) {
    return _TransactionDigestUtils.hashHeaderTxId(
      version: version,
      branchId: branchId,
      lockTime: locktime,
      expiryHeight: expiryHeight,
    );
  }

  /// Computes the Orchard bundle digest, or returns null if no bundle.
  static List<int>? _digestOrchard(
    OrchardBundle? bundle, {
    TxVersionType version = TxVersionType.v5,
  }) {
    if (bundle == null) return null;
    return _TransactionDigestUtils.hashOrchardBundleTxIdData(
      bundle,
      version: version,
    );
  }

  /// Computes the Ironwood bundle digest, or returns null if no bundle.
  static List<int>? _digestIronwood(OrchardBundle? bundle) {
    if (bundle == null) return null;
    return _TransactionDigestUtils.hashIronwoodBundleTxIdData(bundle);
  }

  /// Computes the Sapling bundle digest, or returns null if no bundle.
  static List<int>? _digestSapling(
    SaplingBundle? bundle, {
    TxVersionType version = TxVersionType.v5,
  }) {
    if (bundle == null) return null;
    return _TransactionDigestUtils.hashSaplingTxId(bundle, version: version);
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

  /// Converts transaction digests into a ZcashTxId using branch-specific personalization.
  static ZcashTxId _toTxId({
    required TxDigestsPart digest,
    required ZcashNetworkProtocol branchId,
    required TxVersionType version,
  }) {
    final h = _TransactionDigestUtils._hasher([
      ..._TransactionDigestUtils.zcashTxPersonalizationPrefix.codeUnits,
      ...branchId.branchId.toU32LeBytes(),
    ]);
    try {
      h.update(digest.headerDigest);
      final transparent = _TransactionDigestUtils.hashTransparentTxidData(
        digest.transparentDigest,
      );
      h.update(transparent);
      final saplingDigest =
          digest.saplingDigest ??
          QuickCrypto.blake2b256Hash(
            [],
            personalization:
                _TransactionDigestUtils
                    .zcashSaplingHashPersonalization
                    .codeUnits,
          );
      h.update(saplingDigest);
      final orchardDigest =
          digest.orchardDigest ??
          _TransactionDigestUtils.emptyOrchardDigest(version);
      h.update(orchardDigest);
      if (version == TxVersionType.v6) {
        final ironwoodDigest =
            digest.ironwoodDigest ??
            _TransactionDigestUtils.emptyIronwoodDigest();
        h.update(ironwoodDigest);
      }
      return ZcashTxId(h.digest());
    } finally {
      h.clean();
    }
  }

  /// Computes the ZcashTxId for a transaction.
  static ZcashTxId txToTxId(TransactionData data) {
    final branchId = data.consensusBranchId;
    if (branchId == null) {
      throw CoreErrors.invalidOperationArguments(
        "toTxId",
        name: "branchId",
        reason: "Missing branch id.",
      );
    }
    final digest = txToDigest(data);
    return _toTxId(
      digest: digest,
      branchId: branchId,
      version: data.version.type,
    );
  }

  /// Computes the digests for all parts of a transaction (header, transparent, sapling, orchard, ironwood).
  static TxDigestsPart txToDigest(TransactionData data) {
    final branchId = data.consensusBranchId;
    if (branchId == null) {
      throw CoreErrors.invalidOperationArguments(
        "toTxId",
        name: "branchId",
        reason: "Missing branch id.",
      );
    }
    return TxDigestsPart(
      headerDigest: _digestHeader(
        version: data.version,
        branchId: branchId,
        locktime: data.locktime,
        expiryHeight: data.expiryHeight,
      ),
      transparentDigest: _digestTransparent(data.transparentBundle),
      orchardDigest: _digestOrchard(
        data.orchardBundle,
        version: data.version.type,
      ),
      ironwoodDigest: _digestIronwood(data.ironwoodBundle),
      saplingDigest: _digestSapling(
        data.saplingBundle,
        version: data.version.type,
      ),
    );
  }
}
