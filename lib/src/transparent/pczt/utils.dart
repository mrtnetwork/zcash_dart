import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/transparent/exception/exception.dart';
import 'package:zcash_dart/src/transparent/pczt/pczt.dart';

class TransparentPcztUtils {
  /// Computes the effective locktime from a list of transparent inputs, falling back to a default if none are set.
  static int getTranspareentLocktime(
      int? fallbackLockTime, List<TransparentPcztInput> inputs) {
    final locktimes = inputs
        .where((e) => e.hasLocktime())
        .map((e) => e.getTimelock())
        .toList();
    final heightlocks = inputs
        .where((e) => e.hasHeightLock())
        .map((e) => e.getHeightlock())
        .toList();
    if (locktimes.isEmpty && heightlocks.isEmpty) {
      return fallbackLockTime ?? 0;
    }
    if (locktimes.isNotEmpty && heightlocks.isNotEmpty) {
      throw TransparentExceptoion.operationFailed("getTranspareentLocktime",
          reason: "Invalid Pczt locktime configuration.");
    }
    if (locktimes.isNotEmpty) {
      return locktimes.reduce((p, c) => IntUtils.max(p, c));
    }
    return heightlocks.reduce((p, c) => IntUtils.max(p, c));
  }

  /// find correct preimage for current SHA-256 script. throw if script invalid or no preimage found.
  static String getScriptSha256(
      {required TransparentPcztInput input,
      required Script script,
      required bool fake}) {
    if (!BitcoinScriptUtils.isSha256(script)) {
      throw TransparentExceptoion.operationFailed("getScriptSha256",
          reason: "Invalid script code.");
    }
    if (fake) return "0x${'0' * (QuickCrypto.sha256DigestSize * 2)}";
    final hashBytes = BytesUtils.tryFromHexString(script.script[1]);
    final hash = input.sha256Preimages
        .firstWhereNullable((e) => BytesUtils.bytesEqual(e.hash, hashBytes));
    if (hash == null) {
      throw TransparentExceptoion.operationFailed("getScriptSha256",
          reason: "Failed to find matching preimage for the current script.",
          details: {"scriptPubKey": input.scriptPubkey.toString()});
    }
    return hash.preImageHex();
  }

  /// find correct preimage for current HASH-256 script. throw if script invalid or no preimage found.
  static String getScriptHash256(
      {required TransparentPcztInput input,
      required Script script,
      required bool fake}) {
    if (!BitcoinScriptUtils.isHash256(script)) {
      throw TransparentExceptoion.operationFailed("getScriptHash256",
          reason: "Invalid script code.");
    }
    if (fake) return "0x${'0' * (QuickCrypto.sha256DigestSize * 2)}";
    final hashBytes = BytesUtils.tryFromHexString(script.script[1]);
    final hash = input.hash256Preimages
        .firstWhereNullable((e) => BytesUtils.bytesEqual(e.hash, hashBytes));
    if (hash == null) {
      throw TransparentExceptoion.operationFailed("getScriptHash256",
          reason: "Failed to find matching preimage for the current script.",
          details: {"scriptPubKey": input.scriptPubkey.toString()});
    }
    return hash.preImageHex();
  }

  /// find correct preimage for current HASH-160 script. throw if script invalid or no preimage found.
  static String getScriptHash160(
      {required TransparentPcztInput input,
      required Script script,
      required bool fake}) {
    if (!BitcoinScriptUtils.isHash160(script)) {
      throw TransparentExceptoion.operationFailed("getScriptHash160",
          reason: "Invalid script code.");
    }
    if (fake) return "0x${'0' * (QuickCrypto.hash160DigestSize * 2)}";
    final hashBytes = BytesUtils.tryFromHexString(script.script[1]);
    final hash = input.hash160Preimages
        .firstWhereNullable((e) => BytesUtils.bytesEqual(e.hash, hashBytes));
    if (hash == null) {
      throw TransparentExceptoion.operationFailed("getScriptHash160",
          reason: "Failed to find matching preimage for the current script.",
          details: {"scriptPubKey": input.scriptPubkey.toString()});
    }
    return hash.preImageHex();
  }

  /// find correct preimage for current Ripemd160 script. throw if script invalid or no preimage found.
  static String getScriptRipemd160(
      {required TransparentPcztInput input,
      required Script script,
      required bool fake}) {
    if (!BitcoinScriptUtils.isRipemd160(script)) {
      throw TransparentExceptoion.operationFailed("getScriptRipemd160",
          reason: "Invalid script code.");
    }
    if (fake) return "0x${'0' * (QuickCrypto.hash160DigestSize * 2)}";
    final hashBytes = BytesUtils.tryFromHexString(script.script[1]);
    final hash = input.ripemd160Preimages
        .firstWhereNullable((e) => BytesUtils.bytesEqual(e.hash, hashBytes));
    if (hash == null) {
      throw TransparentExceptoion.operationFailed("getScriptRipemd160",
          reason: "Failed to find matching preimage for the current script.",
          details: {"scriptPubKey": input.scriptPubkey.toString()});
    }
    return hash.preImageHex();
  }

  /// find correct signature for current script. throw if no signature found.
  static List<TransparentPcztPartialSignatures> getPartialSignatures({
    required List<ECPublic> publicKeys,
    required TransparentPcztInput input,
  }) {
    final partialSigs = input.partialSignatures
        .where((e) => publicKeys.contains(e.ecPublic))
        .toList();
    if (partialSigs.isEmpty) {
      throw TransparentExceptoion.operationFailed("getPartialSignatures",
          reason: "No valid signature found.",
          details: {"scriptPubKey": input.scriptPubkey.toString()});
    }
    return partialSigs;
  }

  /// find correct signatures for current script.
  static TransparentPcztPartialSignatures? getPartialSignatureOrNull(
      {required Script script, required TransparentPcztInput input}) {
    final partialSigs = input.partialSignatures.where((e) {
      return PsbtUtils.keyInScript(
          publicKey: e.ecPublic, script: script, type: PsbtTxType.legacy);
    }).toList();

    if (partialSigs.isEmpty) {
      return null;
    }
    return partialSigs.first;
  }

  /// find correct signature for current script. throw if not found.
  static TransparentPcztPartialSignatures getPartialSignature(
      {required Script script, required TransparentPcztInput input}) {
    var partialSigs = getPartialSignatureOrNull(script: script, input: input);
    if (partialSigs == null) {
      throw TransparentExceptoion.operationFailed("getPartialSignature",
          reason: "No valid signature found.",
          details: {"scriptPubkey": input.scriptPubkey.toString()});
    }
    return partialSigs;
  }

  static List<String> _finalizeMultisigScript({
    required Script script,
    required MultiSignatureAddress multisig,
    required TransparentPcztInput input,
    bool fake = false,
  }) {
    final multisigSigners =
        multisig.signers.map((e) => ECPublic.fromHex(e.publicKey)).toList();
    List<TransparentPcztPartialSignatures> validSignatures = [];
    if (!fake) {
      validSignatures =
          getPartialSignatures(input: input, publicKeys: multisigSigners);
    }
    List<String> signatures = [];
    final threshold = multisig.threshold;
    for (int i = 0; i < multisig.signers.length; i++) {
      if (signatures.length >= threshold) break;
      final pubKey = multisigSigners[i];
      final signer = multisig.signers[i];

      final signature = fake
          ? PsbtUtils.fakeECDSASignatureBytes
          : validSignatures.firstWhereNullable((e) {
              return e.ecPublic == pubKey;
            })?.signatureHex();
      if (signature != null) {
        for (int w = 0; w < signer.weight; w++) {
          signatures.add(signature);
          if (signatures.length >= threshold) break;
        }
      }
    }
    if (signatures.length < threshold) {
      throw TransparentExceptoion.operationFailed(
        "generateScriptSig",
        reason:
            "Missing multisig signatures: Required $threshold, but only ${signatures.length} provided.",
      );
    }
    return [
      if (BitcoinScriptUtils.hasOpCheckMultisig(script)) '',
      ...signatures,
      script.toHex()
    ];
  }

  static List<String> _generateScriptSigP2sh(
      {required TransparentPcztInput input,
      required Script script,
      bool fake = false}) {
    final scriptHex = script.toHex();
    if (BitcoinScriptUtils.isP2pkh(script)) {
      final signature = getPartialSignatureOrNull(input: input, script: script);
      final pubKey = signature == null
          ? null
          : PsbtUtils.findSciptKeyInfo(
              publicKey: signature.ecPublic,
              script: script,
              type: PsbtTxType.legacy);
      if (fake) {
        if (pubKey != null) {
          return [PsbtUtils.fakeECDSASignatureBytes, pubKey.key, scriptHex];
        }
        return [
          PsbtUtils.fakeECDSASignatureBytes,
          PsbtUtils.fakeUnCompresedEcdsaPubKey,
          scriptHex
        ];
      }
      if (signature == null || pubKey == null) {
        throw TransparentExceptoion.operationFailed(
          "generateScriptSig",
          reason: "Cannot find correct signature or public key in script.",
        );
      }
      return [signature.signatureHex(), pubKey.key, scriptHex];
    } else if (BitcoinScriptUtils.isP2pk(script)) {
      if (fake) {
        return [PsbtUtils.fakeECDSASignatureBytes, scriptHex];
      }
      final signature = getPartialSignature(input: input, script: script);
      return [signature.signatureHex(), scriptHex];
    }
    final multisig = BitcoinScriptUtils.parseMultisigScript(script);
    if (multisig != null) {
      return _finalizeMultisigScript(
          script: script, multisig: multisig, fake: fake, input: input);
    }
    if (script.script.isEmpty) {
      return [scriptHex];
    }
    if (BitcoinScriptUtils.isOpTrue(script)) {
      return [scriptHex];
    }
    if (BitcoinScriptUtils.isSha256(script)) {
      return [
        getScriptSha256(input: input, script: script, fake: fake),
        scriptHex
      ];
    }
    if (BitcoinScriptUtils.isHash256(script)) {
      return [
        getScriptHash256(input: input, script: script, fake: fake),
        scriptHex
      ];
    }
    if (BitcoinScriptUtils.isHash160(script)) {
      return [
        getScriptHash160(input: input, script: script, fake: fake),
        scriptHex
      ];
    }
    if (BitcoinScriptUtils.isRipemd160(script)) {
      return [
        getScriptRipemd160(input: input, script: script, fake: fake),
        scriptHex
      ];
    }
    if (BitcoinScriptUtils.isPubKeyOpCheckSig(script)) {
      final signature = getPartialSignatureOrNull(input: input, script: script);
      final pubKey = PsbtUtils.findSciptKeyInfo(
          publicKey: signature?.ecPublic,
          script: script,
          type: PsbtTxType.legacy);
      if (pubKey == null) {
        if (fake) {
          return [PsbtUtils.fakeUnCompresedEcdsaPubKey, scriptHex];
        }
        throw TransparentExceptoion.operationFailed(
          "generateScriptSig",
          reason: "Cannot find correct public key in script.",
        );
      }
      return [pubKey.key, scriptHex];
    }
    throw TransparentExceptoion.operationFailed("generateScriptSig",
        reason: "Unable to finalize custom script input.",
        details: {"scriptPubKey": input.scriptPubkey.toString()});
  }

  static List<String> _generateScriptSigNonP2sh({
    required Script script,
    required TransparentPcztInput input,
    bool fake = false,
  }) {
    if (BitcoinScriptUtils.isP2pk(script)) {
      if (fake) {
        return [PsbtUtils.fakeECDSASignatureBytes];
      }
      return [getPartialSignature(script: script, input: input).signatureHex()];
    } else if (BitcoinScriptUtils.isP2pkh(script)) {
      final sig = getPartialSignatureOrNull(script: script, input: input);
      final pk = sig == null
          ? null
          : PsbtUtils.findSciptKeyInfo(
              publicKey: sig.ecPublic, script: script, type: PsbtTxType.legacy);
      if (fake) {
        return [
          sig?.signatureHex() ?? PsbtUtils.fakeECDSASignatureBytes,
          pk?.key ?? PsbtUtils.fakeUnCompresedEcdsaPubKey
        ];
      }

      if (pk == null || sig == null) {
        throw TransparentExceptoion.operationFailed(
          "generateScriptSig",
          reason: "Cannot find correct signature or public key in script.",
        );
      }
      return [sig.signatureHex(), pk.key];
    }
    throw TransparentExceptoion.operationFailed(
      "generateScriptSig",
      reason: "Unable to finalize custom input.",
      details: {"scriptPubKey": input.scriptPubkey.toString()},
    );
  }

  /// generate scriptSig for input.
  /// [fake] helpfull for calculate script size.
  static Script generateScriptSig(TransparentPcztInput input,
      {bool fake = false}) {
    final redeemScript = input.redeemScript;
    if (redeemScript == null) {
      return Script(
          script: _generateScriptSigNonP2sh(
              script: input.scriptPubkey, input: input, fake: fake));
    }
    return Script(
        script: _generateScriptSigP2sh(
            script: redeemScript, input: input, fake: fake));
  }
}
