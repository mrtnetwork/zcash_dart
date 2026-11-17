import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:zcash_dart/src/error/zcash_error.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/address/src/zcash_address.dart';

abstract class TransparentMultiSignatureSigner {}

/// TransparentMultiSignatureSignerDefault is an interface that defines methods required for representing
/// signers in a multi-signature scheme. A multi-signature signer typically includes
/// information about their public key and weight within the scheme.
class TransparentMultiSignatureSignerDefault
    implements TransparentMultiSignatureSigner {
  TransparentMultiSignatureSignerDefault.unsafe({
    required this.publicKey,
    required int weight,
  }) : keyType = BtcUtils.determinatePubKeyModeHex(publicKey),
       weight = weight.asU8;

  /// PublicKey returns the public key associated with the signer.
  final String publicKey;

  /// Weight returns the weight or significance of the signer within the multi-signature scheme.
  /// The weight is used to determine the number of signatures required for a valid transaction.
  final int weight;

  final PublicKeyType keyType;

  /// creates a new instance of a multi-signature signer with the
  /// specified public key and weight.
  factory TransparentMultiSignatureSignerDefault({
    required String publicKey,
    required int weight,
  }) {
    if (weight > 16 || weight < 1) {
      throw ZcashErrors.transparentMultisigFailed(
        'The weight should be between 1 and 16',
      );
    }
    final pubkeyMode = BtcUtils.determinatePubKeyModeHex(publicKey);

    return TransparentMultiSignatureSignerDefault.unsafe(
      publicKey: ECPublic.fromHex(publicKey).toHex(mode: pubkeyMode),
      weight: weight,
    );
  }
}

/// TransparentMultiSignatureAddress represents a multi-signature transparent address configuration, including
/// information about the required signers, threshold, the address itself,
/// and the script details used for multi-signature transactions.
class TransparentMultiSignatureAddress {
  /// Signers is a collection of signers participating in the multi-signature scheme.
  final List<TransparentMultiSignatureSigner> signers;

  /// Threshold is the minimum number of signatures required to spend the transparent associated
  /// with this address.
  final int threshold;

  /// ScriptDetails provides details about the multi-signature script used in transactions,
  /// including "OP_M", compressed public keys, "OP_N", and "OP_CHECKMULTISIG."
  final Script multiSigScript;

  const TransparentMultiSignatureAddress.unsafe({
    required this.signers,
    required this.threshold,
    required this.multiSigScript,
  });

  /// CreateMultiSignatureAddress creates a new instance of a TransparentMultiSignatureAddress, representing
  /// a multi-signature transparent address configuration. It allows you to specify the minimum number
  /// of required signatures (threshold), provide the collection of signers participating in the
  /// multi-signature scheme, and specify the address type.
  factory TransparentMultiSignatureAddress({
    required int threshold,
    required List<TransparentMultiSignatureSignerDefault> signers,
  }) {
    final sumWeight = signers.fold<int>(
      0,
      (sum, signer) => sum + signer.weight,
    );
    final opN = BitcoinOpcode.opNum(threshold);
    final opW = BitcoinOpcode.opNum(sumWeight);
    if (opN == null || threshold == 0) {
      throw ZcashErrors.transparentMultisigFailed(
        'The threshold should be between 1 and 16',
      );
    }
    if (opW == null) {
      throw ZcashErrors.transparentMultisigFailed(
        'The total weight of the owners should not exceed 16',
      );
    }
    if (sumWeight < threshold) {
      throw ZcashErrors.transparentMultisigFailed(
        'The total weight of the signatories should reach the threshold',
      );
    }
    final multiSigScript = <Object>[opN];
    for (final signer in signers) {
      for (var w = 0; w < signer.weight; w++) {
        multiSigScript.add(signer.publicKey);
      }
    }
    multiSigScript.addAll([opW, BitcoinOpcode.opCheckMultiSig.name]);
    final script = Script(script: multiSigScript);
    return TransparentMultiSignatureAddress.unsafe(
      signers: signers,
      threshold: threshold,
      multiSigScript: script,
    );
  }

  /// geneerate transparent p2sh address for selected network
  ZcashP2shAddress toTransparentAddress({
    P2shAddressType addressType = P2shAddressType.p2pkhInP2sh,
    ZcashNetwork network = ZcashNetwork.mainnet,
  }) {
    return ZcashP2shAddress.fromScript(
      script: multiSigScript,
      type: addressType,
      network: network,
    );
  }
}
