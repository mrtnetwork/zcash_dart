import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/pczt/types/global.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/pczt/pczt/utils.dart';
import 'package:zcash_dart/src/transparent/keys/private_key.dart';
import 'package:zcash_dart/src/transparent/pczt/utils.dart';
import 'package:zcash_dart/src/transaction/transaction.dart';
import 'package:zcash_dart/src/transparent/pczt/exception.dart';
import 'package:zcash_dart/src/transparent/transaction/bundle.dart';
import 'package:zcash_dart/src/transparent/transaction/input.dart';
import 'package:zcash_dart/src/transparent/transaction/output.dart';
import 'package:zcash_dart/src/value/value.dart';

class TransparentPcztInput with LayoutSerializable {
  final ZCashTxId prevoutTxid;
  final int prevoutIndex;
  final int? sequence;
  final BigInt value;
  final Script scriptPubkey;
  final int sighashType;
  int? _requiredTimeLockTime;
  int? _requiredHeightLockTime;
  int? get requiredTimeLockTime => _requiredTimeLockTime;
  int? get requiredHeightLockTime => _requiredHeightLockTime;
  Script? _scriptSig;
  Script? get scriptSig => _scriptSig;
  Script? _redeemScript;
  Script? get redeemScript => _redeemScript;
  Set<TransparentPcztPartialSignatures> _partialSignatures;
  Set<TransparentPcztPartialSignatures> get partialSignatures =>
      _partialSignatures;
  Set<TransparentPcztBip32Derivation> _bip32Derivation;
  Set<TransparentPcztBip32Derivation> get bip32Derivation => _bip32Derivation;
  Set<TransparentPcztInputRipemd160> _ripemd160Preimages;
  Set<TransparentPcztInputRipemd160> get ripemd160Preimages =>
      _ripemd160Preimages;
  Set<TransparentPcztInputSha256> _sha256Preimages;
  Set<TransparentPcztInputSha256> get sha256Preimages => _sha256Preimages;
  Set<TransparentPcztInputHash160> _hash160Preimages;

  Set<TransparentPcztInputHash160> get hash160Preimages => _hash160Preimages;
  Set<TransparentPcztInputHash256> _hash256Preimages;

  Set<TransparentPcztInputHash256> get hash256Preimages => _hash256Preimages;
  Map<String, List<int>> _proprietary;
  Map<String, List<int>> get proprietary => _proprietary;

  /// Returns true if any time or height lock is set on this input.
  bool hasLocktime() =>
      _requiredTimeLockTime != null || _requiredHeightLockTime != null;

  /// Returns true if a time-based lock is set.
  bool hasTimelock() => _requiredTimeLockTime != null;

  /// Returns true if a block-height-based lock is set.
  bool hasHeightLock() => _requiredHeightLockTime != null;

  /// Returns the time lock value, or throws if not set.
  int getTimelock() {
    final timelock = _requiredTimeLockTime;
    if (timelock == null) {
      throw TransparentPcztException.operationFailed("getTimelock",
          reason: "Missing input time lock.");
    }
    return timelock;
  }

  /// Returns the height lock value, or throws if not set.
  int getHeightlock() {
    final timelock = _requiredHeightLockTime;
    if (timelock == null) {
      throw TransparentPcztException.operationFailed("getHeightlock",
          reason: "Missing input height lock.");
    }
    return timelock;
  }

  /// Signs the transaction input using the given private key and context, adding the partial signature.
  Future<void> sign({
    required List<int> sighash,
    required ZECPrivate sk,
    required ZCashCryptoContext context,
  }) async {
    final signature = TransparentPcztPartialSignatures(
        publicKey: sk.toPublicKey().toBytes(mode: PubKeyModes.compressed),
        signature:
            await context.signEcdsaDer(sk, sighash, sighash: sighashType));
    addPrtialSignature(signature);
  }

  TransparentPcztInput(
      {required this.prevoutTxid,
      required this.prevoutIndex,
      this.sequence,
      required this.value,
      required this.scriptPubkey,
      required this.sighashType,
      int? requiredTimeLockTime,
      int? requiredHeightLockTime,
      Script? scriptSig,
      Script? redeemScript,
      Set<TransparentPcztPartialSignatures> partialSignatures = const {},
      Set<TransparentPcztBip32Derivation> bip32Derivation = const {},
      Set<TransparentPcztInputRipemd160> ripemd160Preimages = const {},
      Set<TransparentPcztInputSha256> sha256Preimages = const {},
      Set<TransparentPcztInputHash160> hash160Preimages = const {},
      Set<TransparentPcztInputHash256> hash256Preimages = const {},
      Map<String, List<int>> proprietary = const {}})
      : _partialSignatures = partialSignatures.immutable,
        _bip32Derivation = bip32Derivation.immutable,
        _ripemd160Preimages = ripemd160Preimages.immutable,
        _sha256Preimages = sha256Preimages.immutable,
        _hash160Preimages = hash160Preimages.immutable,
        _hash256Preimages = hash256Preimages.immutable,
        _scriptSig = scriptSig,
        _requiredHeightLockTime = requiredHeightLockTime,
        _requiredTimeLockTime = requiredTimeLockTime,
        _proprietary =
            proprietary.map((k, v) => MapEntry(k, v.toImutableBytes)).immutable,
        _redeemScript = redeemScript;
  factory TransparentPcztInput.deserializeJson(Map<String, dynamic> json) {
    return TransparentPcztInput(
        prevoutTxid: ZCashTxId.deserializeJson(json.valueAs("prevout_txid")),
        prevoutIndex: json.valueAs("prevout_index"),
        sequence: json.valueAs("sequence"),
        requiredTimeLockTime: json.valueAs("required_time_lock_time"),
        requiredHeightLockTime: json.valueAs("required_height_lock_time"),
        scriptSig: json.valueTo<Script?, List<int>>(
            key: "script_sig", parse: (v) => Script.deserialize(bytes: v)),
        value: json.valueAs("value"),
        scriptPubkey:
            Script.deserialize(bytes: json.valueAsBytes("script_pubkey")),
        redeemScript: json.valueTo<Script?, List<int>>(
            key: "redeem_script", parse: (v) => Script.deserialize(bytes: v)),
        partialSignatures: json
            .valueEnsureAsList<Map<String, dynamic>>("partial_signatures")
            .map((e) => TransparentPcztPartialSignatures.deserializeJson(e))
            .toSet(),
        sighashType: json.valueAs("sighash_type"),
        bip32Derivation: json
            .valueEnsureAsList<Map<String, dynamic>>("bip32_derivation")
            .map((e) => TransparentPcztBip32Derivation.deserializeJson(e))
            .toSet(),
        ripemd160Preimages: json
            .valueEnsureAsList<Map<String, dynamic>>("ripemd160_preimages")
            .map((e) => TransparentPcztInputRipemd160.deserializeJson(e))
            .toSet(),
        hash256Preimages: json
            .valueEnsureAsList<Map<String, dynamic>>("hash256_preimages")
            .map((e) => TransparentPcztInputHash256.deserializeJson(e))
            .toSet(),
        hash160Preimages: json
            .valueEnsureAsList<Map<String, dynamic>>("hash160_preimages")
            .map((e) => TransparentPcztInputHash160.deserializeJson(e))
            .toSet(),
        sha256Preimages: json
            .valueEnsureAsList<Map<String, dynamic>>("sha256_preimages")
            .map((e) => TransparentPcztInputSha256.deserializeJson(e))
            .toSet(),
        proprietary: json.valueEnsureAsMap<String, List<int>>("proprietary"));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      ZCashTxId.layout(property: "prevout_txid"),
      LayoutConst.lebU32(property: "prevout_index"),
      LayoutConst.optional(LayoutConst.lebU32(), property: "sequence"),
      LayoutConst.optional(LayoutConst.lebU32(),
          property: "required_time_lock_time"),
      LayoutConst.optional(LayoutConst.lebU32(),
          property: "required_height_lock_time"),
      LayoutConst.optional(LayoutConst.bcsBytes(), property: "script_sig"),
      LayoutConst.lebU64(property: "value"),
      LayoutConst.bcsBytes(property: "script_pubkey"),
      LayoutConst.optional(LayoutConst.bcsBytes(), property: "redeem_script"),
      LayoutConst.bcsVector(TransparentPcztPartialSignatures.layout(),
          property: "partial_signatures"),
      LayoutConst.u8(property: "sighash_type"),
      LayoutConst.bcsVector(TransparentPcztBip32Derivation.layout(),
          property: "bip32_derivation"),
      LayoutConst.bcsVector(TransparentPcztInputRipemd160.layout(),
          property: "ripemd160_preimages"),
      LayoutConst.bcsVector(TransparentPcztInputSha256.layout(),
          property: "sha256_preimages"),
      LayoutConst.bcsVector(TransparentPcztInputHash160.layout(),
          property: "hash160_preimages"),
      LayoutConst.bcsVector(TransparentPcztInputHash256.layout(),
          property: "hash256_preimages"),
      LayoutConst.bscMap<String, List<int>>(
          LayoutConst.bcsString(), LayoutConst.bcsBytes(),
          property: "proprietary")
    ], property: property);
  }

  TransparentPcztInput clone() => TransparentPcztInput(
      prevoutTxid: prevoutTxid,
      prevoutIndex: prevoutIndex,
      value: value,
      scriptPubkey: scriptPubkey,
      sighashType: sighashType,
      bip32Derivation: bip32Derivation,
      hash160Preimages: hash160Preimages,
      hash256Preimages: hash256Preimages,
      partialSignatures: partialSignatures,
      proprietary: proprietary,
      redeemScript: redeemScript,
      requiredHeightLockTime: requiredHeightLockTime,
      requiredTimeLockTime: requiredHeightLockTime,
      ripemd160Preimages: ripemd160Preimages,
      scriptSig: scriptSig,
      sequence: sequence,
      sha256Preimages: sha256Preimages);

  /// Adds a proprietary key-value pair to the input.
  void addProprietary(String name, List<int> value) {
    final proprietary = this.proprietary.clone();
    proprietary[name] = value.clone();
    _proprietary = proprietary.immutable;
  }

  /// Adds a BIP32 derivation path to the input.
  void addBip32Derivation(TransparentPcztBip32Derivation bip32Derivation) {
    _bip32Derivation = {..._bip32Derivation, bip32Derivation}.immutable;
  }

  /// /// Sets the redeem script for a P2SH input, validating correctness.
  void setRedeemScript(Script? redeemScript) {
    if (redeemScript != null && !BitcoinScriptUtils.isP2sh(scriptPubkey)) {
      throw TransparentPcztException.operationFailed("setRedeemScript",
          reason: "No P2sh input.");
    }
    if (redeemScript != null &&
        P2shAddress.fromScript(script: redeemScript).toScriptPubKey() !=
            scriptPubkey) {
      throw TransparentPcztException.operationFailed("setRedeemScript",
          reason: "Invalid redeem script.");
    }
    _redeemScript = redeemScript;
  }

  /// Adds a RIPEMD160 preimage.
  void addRipemd160Preimages(TransparentPcztInputRipemd160 ripemd160) {
    _ripemd160Preimages = {..._ripemd160Preimages, ripemd160}.immutable;
  }

  /// Adds a HASH160 preimage.
  void addHash160Preimages(TransparentPcztInputHash160 hash160) {
    _hash160Preimages = {..._hash160Preimages, hash160}.immutable;
  }

  /// Adds a SHA256 preimage.
  void addSha256Preimages(TransparentPcztInputSha256 sha256) {
    _sha256Preimages = {..._sha256Preimages, sha256}.immutable;
  }

  /// Adds a HASH256 preimage.
  void addHash256Preimages(TransparentPcztInputHash256 hash256) {
    _hash256Preimages = {..._hash256Preimages, hash256}.immutable;
  }

  /// Adds a partial signature for the input.
  void addPrtialSignature(TransparentPcztPartialSignatures signature) {
    _partialSignatures = {..._partialSignatures, signature}.immutable;
  }

  /// Sets the scriptSig for the input.
  void setScriptSig(Script? scriptSig) {
    _scriptSig = scriptSig;
  }

  /// Returns true if the input scriptPubKey is P2PKH.
  bool isP2pkh() => BitcoinScriptUtils.isP2pkh(scriptPubkey);

  /// Returns true if the input scriptPubKey is P2SH.
  bool isP2sh() => BitcoinScriptUtils.isP2sh(scriptPubkey);

  /// verify redeem and scriptPubKey.
  void verify() {
    final redeemScript = this.redeemScript;
    if (BitcoinScriptUtils.isP2pkh(scriptPubkey) ||
        BitcoinScriptUtils.isP2pk(scriptPubkey)) {
      if (redeemScript != null) {
        throw TransparentPcztException.operationFailed("verify",
            reason: "Invalid input scipts.");
      }
    } else if (redeemScript != null) {
      if (!BitcoinScriptUtils.isP2sh(scriptPubkey) ||
          P2shAddress.fromScript(script: redeemScript).toScriptPubKey() !=
              scriptPubkey) {
        throw TransparentPcztException.operationFailed("verify",
            reason: "Invalid p2sh input redeem script.");
      }
    } else if (BitcoinScriptUtils.isP2sh(scriptPubkey)) {
      throw TransparentPcztException.operationFailed("verify",
          reason: "Missing input redeem script.");
    } else {
      throw TransparentPcztException.operationFailed("verify",
          reason: "Unsupported script pub key.");
    }
  }

  /// finalize inout
  void finalizeInput() {
    verify();
    final scriptSig = TransparentPcztUtils.generateScriptSig(this);
    setScriptSig(scriptSig);
    _requiredHeightLockTime = null;
    _requiredTimeLockTime = null;
    _redeemScript = null;
    _bip32Derivation = <TransparentPcztBip32Derivation>{}.immutable;
    _hash160Preimages = <TransparentPcztInputHash160>{}.immutable;
    _hash256Preimages = <TransparentPcztInputHash256>{}.immutable;
    _ripemd160Preimages = <TransparentPcztInputRipemd160>{}.immutable;
    _sha256Preimages = <TransparentPcztInputSha256>{}.immutable;
    _partialSignatures = <TransparentPcztPartialSignatures>{}.immutable;
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "prevout_txid": prevoutTxid.toSerializeJson(),
      "prevout_index": prevoutIndex,
      "sequence": sequence,
      "required_time_lock_time": requiredTimeLockTime,
      "required_height_lock_time": requiredHeightLockTime,
      "script_sig": scriptSig?.toBytes(),
      "value": value,
      "script_pubkey": scriptPubkey.toBytes(),
      "redeem_script": redeemScript?.toBytes(),
      "partial_signatures":
          partialSignatures.map((e) => e.toSerializeJson()).toList(),
      "sighash_type": sighashType,
      "bip32_derivation":
          bip32Derivation.map((e) => e.toSerializeJson()).toList(),
      "ripemd160_preimages":
          ripemd160Preimages.map((e) => e.toSerializeJson()).toList(),
      "sha256_preimages":
          sha256Preimages.map((e) => e.toSerializeJson()).toList(),
      "hash160_preimages":
          hash160Preimages.map((e) => e.toSerializeJson()).toList(),
      "hash256_preimages":
          hash256Preimages.map((e) => e.toSerializeJson()).toList(),
      "proprietary": proprietary
    };
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMerge(TransparentPcztInput other) {
    return PcztUtils.canMerge(sequence, other.sequence) &&
        PcztUtils.canMerge(
            requiredHeightLockTime, other.requiredHeightLockTime) &&
        PcztUtils.canMerge(requiredTimeLockTime, other.requiredTimeLockTime) &&
        PcztUtils.canMerge(redeemScript, other.redeemScript) &&
        PcztUtils.canMerge(scriptSig, other.scriptSig) &&
        PcztUtils.canMerge(prevoutIndex, other.prevoutIndex) &&
        PcztUtils.canMerge(prevoutTxid, other.prevoutTxid) &&
        PcztUtils.canMerge(value, other.value) &&
        PcztUtils.canMerge(scriptPubkey, other.scriptPubkey) &&
        PcztUtils.canMerge(sighashType, other.sighashType);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  TransparentPcztInput? merge(TransparentPcztInput other) {
    if (!canMerge(other)) return null;
    int? sequence = this.sequence ?? other.sequence;
    int? requiredHeightLockTime =
        this.requiredHeightLockTime ?? other.requiredHeightLockTime;
    int? requiredTimeLockTime =
        this.requiredTimeLockTime ?? other.requiredTimeLockTime;
    Script? redeemScript = this.redeemScript ?? other.redeemScript;
    Script? scriptSig = this.scriptSig ?? other.scriptSig;
    final proprietary =
        PcztUtils.mergeProprietary(this.proprietary, other.proprietary);
    final bip32Derivation =
        PcztUtils.mergeSet(this.bip32Derivation, other.bip32Derivation);
    final ripemd160Preimages =
        PcztUtils.mergeSet(this.ripemd160Preimages, other.ripemd160Preimages);
    final sha256Preimages =
        PcztUtils.mergeSet(this.sha256Preimages, other.sha256Preimages);
    final hash160Preimages =
        PcztUtils.mergeSet(this.hash160Preimages, other.hash160Preimages);
    final hash256Preimages =
        PcztUtils.mergeSet(this.hash256Preimages, other.hash256Preimages);
    final partialSignatures =
        PcztUtils.mergeSet(this.partialSignatures, other.partialSignatures);
    if (proprietary == null ||
        bip32Derivation == null ||
        ripemd160Preimages == null ||
        sha256Preimages == null ||
        hash160Preimages == null ||
        hash256Preimages == null ||
        partialSignatures == null) {
      return null;
    }
    return TransparentPcztInput(
        prevoutTxid: prevoutTxid,
        prevoutIndex: prevoutIndex,
        value: value,
        scriptPubkey: scriptPubkey,
        sighashType: sighashType,
        bip32Derivation: bip32Derivation,
        hash160Preimages: hash160Preimages,
        hash256Preimages: hash256Preimages,
        partialSignatures: partialSignatures,
        proprietary: proprietary,
        redeemScript: redeemScript,
        requiredHeightLockTime: requiredHeightLockTime,
        requiredTimeLockTime: requiredTimeLockTime,
        ripemd160Preimages: ripemd160Preimages,
        scriptSig: scriptSig,
        sequence: sequence,
        sha256Preimages: sha256Preimages);
  }
}

class TransparentPcztOutput with LayoutSerializable {
  final BigInt value;
  final Script scriptPubkey;
  Script? _redeemScript;
  Script? get redeemScript => _redeemScript;
  Set<TransparentPcztBip32Derivation> _bip32Derivation;
  Set<TransparentPcztBip32Derivation> get bip32Derivation => _bip32Derivation;
  String? _userAddress;
  String? get userAddress => _userAddress;
  Map<String, List<int>> _proprietary;
  Map<String, List<int>> get proprietary => _proprietary;
  TransparentPcztOutput(
      {required this.value,
      required this.scriptPubkey,
      Script? redeemScript,
      Set<TransparentPcztBip32Derivation> bip32Derivation = const {},
      String? userAddress,
      Map<String, List<int>> proprietary = const {}})
      : _bip32Derivation = bip32Derivation.immutable,
        _proprietary = proprietary
            .map((k, v) => MapEntry(k, v.asImmutableBytes))
            .immutable,
        _redeemScript = redeemScript,
        _userAddress = userAddress;
  factory TransparentPcztOutput.deserializeJson(Map<String, dynamic> json) {
    return TransparentPcztOutput(
        value: json.valueAs("value"),
        bip32Derivation: json
            .valueEnsureAsList<Map<String, dynamic>>("bip32_derivation")
            .map((e) => TransparentPcztBip32Derivation.deserializeJson(e))
            .toSet(),
        scriptPubkey:
            Script.deserialize(bytes: json.valueAsBytes("script_pubkey")),
        redeemScript: json.valueTo<Script?, List<int>>(
            key: "redeem_script", parse: (v) => Script.deserialize(bytes: v)),
        userAddress: json.valueAsString("user_address"),
        proprietary: json.valueEnsureAsMap<String, List<int>>("proprietary"));
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.lebU64(property: "value"),
      LayoutConst.bcsBytes(property: "script_pubkey"),
      LayoutConst.optional(LayoutConst.bcsBytes(), property: "redeem_script"),
      LayoutConst.bcsVector(TransparentPcztBip32Derivation.layout(),
          property: "bip32_derivation"),
      LayoutConst.optional(LayoutConst.bcsString(), property: "user_address"),
      LayoutConst.bscMap<String, List<int>>(
          LayoutConst.bcsString(), LayoutConst.bcsBytes(),
          property: "proprietary")
    ], property: property);
  }

  TransparentPcztOutput clone() => TransparentPcztOutput(
      value: value,
      scriptPubkey: scriptPubkey,
      bip32Derivation: bip32Derivation,
      proprietary: proprietary,
      redeemScript: redeemScript,
      userAddress: userAddress);

  void verify() {
    final redeemScript = this.redeemScript;
    if (BitcoinScriptUtils.isP2pkh(scriptPubkey)) {
      if (redeemScript != null) {
        throw TransparentPcztException.operationFailed("verify",
            reason: "No P2sh output.");
      }
    } else if (redeemScript != null) {
      if (!BitcoinScriptUtils.isP2sh(scriptPubkey) ||
          P2shAddress.fromScript(script: redeemScript).toScriptPubKey() !=
              scriptPubkey) {
        throw TransparentPcztException.operationFailed("verify",
            reason: "Invalid p2sh output.");
      }
    } else {
      throw TransparentPcztException.operationFailed("verify",
          reason: "Unsupported output script pub key.");
    }
  }

  /// Adds a proprietary key-value pair to the output.
  void addProprietary(String name, List<int> value) {
    final proprietary = this.proprietary.clone();
    proprietary[name] = value.clone();
    _proprietary = proprietary.immutable;
  }

  void addBip32Derivation(TransparentPcztBip32Derivation bip32Derivation) {
    _bip32Derivation = {..._bip32Derivation, bip32Derivation}.immutable;
  }

  void setRedeemScript(Script? redeemScript) {
    if (redeemScript != null && !BitcoinScriptUtils.isP2sh(scriptPubkey)) {
      throw TransparentPcztException.operationFailed("setRedeemScript",
          reason: "No P2sh output.");
    }
    if (!BitcoinScriptUtils.isP2sh(scriptPubkey)) {
      throw TransparentPcztException.operationFailed("setRedeemScript",
          reason: "No P2sh output.");
    }
    if (redeemScript != null &&
        P2shAddress.fromScript(script: redeemScript).toScriptPubKey() !=
            scriptPubkey) {
      throw TransparentPcztException.operationFailed("setRedeemScript",
          reason: "Invalid redeem script.");
    }
    _redeemScript = redeemScript;
  }

  void setUserAddress(String? userAddress) {
    _userAddress = userAddress;
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "value": value,
      "script_pubkey": scriptPubkey.toBytes(),
      "redeem_script": redeemScript?.toBytes(),
      "bip32_derivation":
          bip32Derivation.map((e) => e.toSerializeJson()).toList(),
      "user_address": userAddress,
      "proprietary": proprietary
    };
  }

  /// Checks if this can be merged with another based on all relevant fields.
  bool canMerge(TransparentPcztOutput other) {
    return PcztUtils.canMerge(redeemScript, other.redeemScript) &&
        PcztUtils.canMerge(userAddress, other.userAddress) &&
        PcztUtils.canMerge(redeemScript, other.redeemScript) &&
        PcztUtils.canMerge(value, other.value) &&
        PcztUtils.canMerge(scriptPubkey, other.scriptPubkey);
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  TransparentPcztOutput? merge(TransparentPcztOutput other) {
    if (!canMerge(other)) return null;
    final userAddress = this.userAddress ?? other.userAddress;
    final redeemScript = this.redeemScript ?? other.redeemScript;
    final proprietary =
        PcztUtils.mergeProprietary(this.proprietary, other.proprietary);
    final bip32Derivation =
        PcztUtils.mergeSet(this.bip32Derivation, other.bip32Derivation);
    if (proprietary == null || bip32Derivation == null) {
      return null;
    }
    return TransparentPcztOutput(
        value: value,
        scriptPubkey: scriptPubkey,
        bip32Derivation: bip32Derivation,
        proprietary: proprietary,
        redeemScript: redeemScript,
        userAddress: userAddress);
  }
}

class TransparentPcztBundle
    with
        LayoutSerializable
    implements
        PcztBundle<TransparentBundle, TransparentExtractedBundle,
            TransparentPcztBundle> {
  final List<TransparentPcztInput> inputs;
  final List<TransparentPcztOutput> outputs;

  TransparentPcztBundle(
      {List<TransparentPcztInput> inputs = const [],
      List<TransparentPcztOutput> outputs = const []})
      : inputs = inputs.immutable,
        outputs = outputs.immutable;
  factory TransparentPcztBundle.deserializeJson(Map<String, dynamic> json) {
    return TransparentPcztBundle(
      inputs: json
          .valueEnsureAsList<Map<String, dynamic>>("inputs")
          .map((e) => TransparentPcztInput.deserializeJson(e))
          .toList(),
      outputs: json
          .valueEnsureAsList<Map<String, dynamic>>("outputs")
          .map((e) => TransparentPcztOutput.deserializeJson(e))
          .toList(),
    );
  }
  static Layout<Map<String, dynamic>> layout({String? propery}) {
    return LayoutConst.struct([
      LayoutConst.bcsVector(TransparentPcztInput.layout(), property: "inputs"),
      LayoutConst.bcsVector(TransparentPcztOutput.layout(), property: "outputs")
    ], property: propery);
  }

  @override
  TransparentPcztBundle clone() =>
      TransparentPcztBundle(inputs: inputs, outputs: outputs);

  @override
  TransparentBundle extractEffects() => _toTxData(extract: false);
  @override
  TransparentExtractedBundle extract() =>
      TransparentExtractedBundle(bundle: _toTxData(), valueSum: valueSum);
  TransparentBundle _toTxData({bool extract = true}) {
    final inputs = this.inputs.map((e) {
      final scriptSig = e.scriptSig;
      if (extract && scriptSig == null) {
        throw TransparentPcztException.operationFailed("extract",
            reason: "Missing input scriptsig.");
      }
      final sequence = e.sequence;
      return TransparentTxInput(
          txId: e.prevoutTxid.txId,
          txIndex: e.prevoutIndex,
          scriptSig: scriptSig,
          sequance: sequence);
    }).toList();

    final outputs = this.outputs.map((e) {
      return TransparentTxOutput(amount: e.value, scriptPubKey: e.scriptPubkey);
    }).toList();
    return TransparentBundle(vin: inputs, vout: outputs);
  }

  void finalize() {
    for (final i in inputs) {
      final scriptSig = i.scriptSig;
      if (scriptSig != null) continue;
      i.finalizeInput();
    }
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(propery: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "inputs": inputs.map((e) => e.toSerializeJson()).toList(),
      "outputs": outputs.map((e) => e.toSerializeJson()).toList()
    };
  }

  /// Attempts to merge with another; returns null if merging is not possible.
  TransparentPcztBundle? merge(
      {required TransparentPcztBundle other,
      required PcztGlobal global,
      required PcztGlobal otherGlobal}) {
    List<TransparentPcztInput> inputs = this.inputs;
    List<TransparentPcztOutput> outputs = this.outputs;
    List<TransparentPcztInput> otherInputs = other.inputs;

    List<TransparentPcztOutput> otherOutputs = other.outputs;
    if (inputs.length != otherInputs.length) {
      if (!global.inputsModifiable() || !otherGlobal.inputsModifiable()) {
        return null;
      }
      if (otherInputs.length < inputs.length) {
        return null;
      }
      inputs = [...inputs, ...otherInputs.sublist(inputs.length)];
    }
    if (outputs.length != otherOutputs.length) {
      if (!global.outputsModifiable() || !otherGlobal.outputsModifiable()) {
        return null;
      }
      if (otherOutputs.length < outputs.length) {
        return null;
      }
      outputs = [...outputs, ...otherOutputs.sublist(outputs.length)];
    }
    List<TransparentPcztInput> mergedInputs = [];
    List<TransparentPcztOutput> mergedOutputs = [];
    for (final i in inputs.indexed) {
      final merge = i.$2.merge(inputs[i.$1]);
      if (merge == null) return null;
      mergedInputs.add(merge);
    }
    for (final i in outputs.indexed) {
      final merge = i.$2.merge(outputs[i.$1]);
      if (merge == null) return null;
      mergedOutputs.add(merge);
    }
    return TransparentPcztBundle(inputs: mergedInputs, outputs: mergedOutputs);
  }

  @override
  ZAmount get valueSum {
    return inputs.fold<ZAmount>(ZAmount.zero(), (p, c) => p + c.value) -
        outputs.fold<ZAmount>(ZAmount.zero(), (p, c) => p + c.value);
  }
}

/// Represents a partial ECDSA signature for a transparent input with the associated public key.
class TransparentPcztPartialSignatures
    with PartialEquality, LayoutSerializable {
  /// Lazily decodes the public key into an `ECPublic` object.
  late final ECPublic ecPublic = ECPublic.fromBytes(publicKey);

  /// The compressed public key bytes used for this partial signature.
  final List<int> publicKey;

  /// The DER-encoded ECDSA signature bytes.
  final List<int> signature;

  TransparentPcztPartialSignatures({
    required List<int> publicKey,
    required List<int> signature,
  })  : publicKey = publicKey
            .exc(
                length: EcdsaKeysConst.pubKeyCompressedByteLen,
                operation: "TransparentPcztPartialSignatures",
                reason: "Invalid compressed public key bytes length.")
            .asImmutableBytes,
        signature = signature.asImmutableBytes;

  factory TransparentPcztPartialSignatures.deserializeJson(
      Map<String, dynamic> json) {
    return TransparentPcztPartialSignatures(
        publicKey: json.valueAsBytes("public_key"),
        signature: json.valueAsBytes("signature"));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(EcdsaKeysConst.pubKeyCompressedByteLen,
          property: "public_key"),
      LayoutConst.bcsBytes(property: "signature"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"public_key": publicKey, "signature": signature};
  }

  String signatureHex() {
    return BytesUtils.toHexString(signature);
  }

  @override
  List<dynamic> get variables => [publicKey, signature];

  @override
  List<dynamic> get parts => [publicKey];
}

/// Represents a BIP32 derivation path with associated public key and seed fingerprint for transparent inputs.
class TransparentPcztBip32Derivation with PartialEquality, LayoutSerializable {
  final List<int> publicKey;
  final List<int> seedFingerprint;
  final List<Bip32KeyIndex> derivationPath;
  TransparentPcztBip32Derivation(
      {required List<int> seedFingerprint,
      required List<Bip32KeyIndex> derivationPath,
      required List<int> publicKey})
      : seedFingerprint = seedFingerprint
            .exc(
                length: 32,
                operation: "TransparentPcztBip32Derivation",
                reason: "Invalid seed fingerprint bytes length.")
            .asImmutableBytes,
        publicKey = publicKey
            .exc(
                length: EcdsaKeysConst.pubKeyCompressedByteLen,
                operation: "TransparentPcztBip32Derivation",
                reason: "Invalid public key bytes length.")
            .asImmutableBytes,
        derivationPath = derivationPath.immutable;

  factory TransparentPcztBip32Derivation.deserializeJson(
      Map<String, dynamic> json) {
    return TransparentPcztBip32Derivation(
        publicKey: json.valueAsBytes("public_key"),
        seedFingerprint: json.valueAsBytes("seed_fingerprint"),
        derivationPath: json
            .valueEnsureAsList<int>("derivation_path")
            .map((e) => Bip32KeyIndex(e))
            .toList());
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(EcdsaKeysConst.pubKeyCompressedByteLen,
          property: "public_key"),
      LayoutConst.fixedBlob32(property: "seed_fingerprint"),
      LayoutConst.bcsVector(LayoutConst.lebU32(), property: "derivation_path"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "public_key": publicKey,
      "seed_fingerprint": seedFingerprint,
      "derivation_path": derivationPath.map((e) => e.index).toList()
    };
  }

  @override
  List<dynamic> get variables => [seedFingerprint, publicKey, derivationPath];

  @override
  List<dynamic> get parts => [seedFingerprint];
}

class TransparentPcztInputRipemd160 with PartialEquality, LayoutSerializable {
  /// The hash preimage, encoded as a byte vector, which must equal the key when run through the RIPEMD160 algorithm
  final List<int> preimage;

  /// The resulting hash of the preimage
  final List<int> hash;
  String preImageHex() {
    return BytesUtils.toHexString(preimage);
  }

  TransparentPcztInputRipemd160(
      {required List<int> preimage, required List<int> hash})
      : preimage = preimage.asImmutableBytes,
        hash = hash
            .exc(
                length: QuickCrypto.hash160DigestSize,
                operation: "TransparentPcztInputRipemd160",
                reason: "Invalid hash bytes length")
            .asImmutableBytes;
  factory TransparentPcztInputRipemd160.fromPreImage(List<int> preimage) {
    return TransparentPcztInputRipemd160(
        preimage: preimage, hash: QuickCrypto.ripemd160Hash(preimage));
  }
  factory TransparentPcztInputRipemd160.deserializeJson(
      Map<String, dynamic> json) {
    return TransparentPcztInputRipemd160(
        preimage: json.valueAsBytes("preimage"),
        hash: json.valueAsBytes("hash"));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(QuickCrypto.hash160DigestSize, property: "hash"),
      LayoutConst.bcsBytes(property: "preimage")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"hash": hash, "preimage": preimage};
  }

  @override
  List<dynamic> get variables => [preimage, hash];

  @override
  List<dynamic> get parts => [hash];
}

class TransparentPcztInputSha256 with PartialEquality, LayoutSerializable {
  /// The hash preimage, encoded as a byte vector, which must equal the key when run through the SHA256 algorithm
  final List<int> preimage;

  /// The resulting hash of the preimage
  final List<int> hash;

  String preImageHex() {
    return BytesUtils.toHexString(preimage);
  }

  TransparentPcztInputSha256({
    required List<int> preimage,
    required List<int> hash,
  })  : preimage = preimage.asImmutableBytes,
        hash = hash
            .exc(
                length: QuickCrypto.sha256DigestSize,
                operation: "TransparentPcztInputSha256",
                reason: "Invalid hash bytes length.")
            .asImmutableBytes;

  factory TransparentPcztInputSha256.fromPreImage(List<int> preimage) {
    return TransparentPcztInputSha256(
        preimage: preimage, hash: QuickCrypto.sha256Hash(preimage));
  }

  factory TransparentPcztInputSha256.deserializeJson(
      Map<String, dynamic> json) {
    return TransparentPcztInputSha256(
        preimage: json.valueAsBytes("preimage"),
        hash: json.valueAsBytes("hash"));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(QuickCrypto.sha256DigestSize, property: "hash"),
      LayoutConst.bcsBytes(property: "preimage")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"hash": hash, "preimage": preimage};
  }

  @override
  List<dynamic> get variables => [preimage, hash];

  @override
  List<dynamic> get parts => [hash];
}

class TransparentPcztInputHash160 with PartialEquality, LayoutSerializable {
  /// The hash preimage, encoded as a byte vector, which must equal the key when run through the
  ///  SHA256 algorithm followed by the RIPEMD160 algorithm
  final List<int> preimage;

  /// The resulting hash of the preimage
  final List<int> hash;
  String preImageHex() {
    return BytesUtils.toHexString(preimage);
  }

  TransparentPcztInputHash160({
    required List<int> preimage,
    required List<int> hash,
  })  : preimage = preimage.asImmutableBytes,
        hash = hash
            .exc(
                length: QuickCrypto.hash160DigestSize,
                operation: "TransparentPcztInputHash160",
                reason: "Invalid hash bytes length.")
            .asImmutableBytes;

  factory TransparentPcztInputHash160.fromPreImage(List<int> preimage) {
    return TransparentPcztInputHash160(
        preimage: preimage, hash: QuickCrypto.hash160(preimage));
  }
  factory TransparentPcztInputHash160.deserializeJson(
      Map<String, dynamic> json) {
    return TransparentPcztInputHash160(
        preimage: json.valueAsBytes("preimage"),
        hash: json.valueAsBytes("hash"));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(QuickCrypto.hash160DigestSize, property: "hash"),
      LayoutConst.bcsBytes(property: "preimage")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"hash": hash, "preimage": preimage};
  }

  @override
  List<dynamic> get variables => [preimage, hash];

  @override
  List<dynamic> get parts => [hash];
}

class TransparentPcztInputHash256 with PartialEquality, LayoutSerializable {
  /// The hash preimage, encoded as a byte vector, which must equal the key when run through the SHA256 algorithm twice
  final List<int> preimage;

  /// The resulting hash of the preimage
  final List<int> hash;
  String preImageHex() {
    return BytesUtils.toHexString(preimage);
  }

  TransparentPcztInputHash256({
    required List<int> preimage,
    required List<int> hash,
  })  : preimage = preimage.asImmutableBytes,
        hash = hash
            .exc(
                length: QuickCrypto.sha256DigestSize,
                operation: "TransparentPcztInputHash256",
                reason: "Invalid hash bytes length.")
            .asImmutableBytes;

  factory TransparentPcztInputHash256.fromPreImage(List<int> preimage) {
    return TransparentPcztInputHash256(
        preimage: preimage, hash: QuickCrypto.sha256DoubleHash(preimage));
  }

  factory TransparentPcztInputHash256.deserializeJson(
      Map<String, dynamic> json) {
    return TransparentPcztInputHash256(
        preimage: json.valueAsBytes("preimage"),
        hash: json.valueAsBytes("hash"));
  }
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(QuickCrypto.sha256DigestSize, property: "hash"),
      LayoutConst.bcsBytes(property: "preimage")
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"hash": hash, "preimage": preimage};
  }

  @override
  List<dynamic> get variables => [preimage, hash];

  @override
  List<dynamic> get parts => [hash];
}

class TransparentExtractedBundle implements ExtractedBundle<TransparentBundle> {
  @override
  final TransparentBundle bundle;
  const TransparentExtractedBundle(
      {required this.bundle, required this.valueSum});

  @override
  final ZAmount valueSum;
}
