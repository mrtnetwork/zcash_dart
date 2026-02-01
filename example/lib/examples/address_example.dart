// ignore_for_file: unused_local_variable

import 'package:blockchain_utils/bip/bip/bip39/bip39.dart';
import 'package:zcash_dart/zcash.dart';

/// Example: Creating a Zcash account and deriving keys & addresses
///
/// This demonstrates:
/// - Generating a BIP39 mnemonic and seed
/// - Creating a Zcash account from seed
/// - Deriving Unified Spending / Viewing / Incoming Viewing keys
/// - Accessing Sapling, Orchard, and Transparent components
void main() {
  /// Lazily initialized cryptographic context
  /// (curves, hashers, parameters are loaded on demand)
  final context = DefaultZCashCryptoContext.lazy();

  /// Generate a 12-word BIP39 mnemonic
  final mnemonic = Bip39MnemonicGenerator().fromWordsNumber(
    Bip39WordsNum.wordsNum12,
  );

  /// Generate seed bytes from mnemonic
  final seed = Bip39SeedGenerator(mnemonic).generate();

  /// Create a Zcash account from seed
  /// - Testnet network
  /// - Transparent support enabled
  final account = ZCashAccount.fromSeed(
    seedBytes: seed,
    config: ZCashAccountConfig(
      network: ZCashNetwork.testnet,
      transparent: true,
      orchard: true,
      sapling: true,
    ),
    context: context,
    accountIndex: Bip32KeyIndex.hardenIndex(1),
  );

  /// Unified Spending Key (USK)
  /// Controls all shielded and transparent funds
  final sk = account.toUnifiedSpendKey();

  /// Unified Full Viewing Key (UFVK)
  /// Can view all transactions but cannot spend
  final ufvk = sk.toUnifiedFullViewingKey();

  /// Unified Incoming Viewing Key (UIVK) — external (receiving) scope
  final uivk = ufvk.toUnifiedIncomingViewingKey(context);

  /// Unified Incoming Viewing Key (UIVK) — internal (change) scope
  final uivkInternal = ufvk.toUnifiedIncomingViewingKey(
    context,
    scope: Bip44Changes.chainInt,
  );

  /// Orchard Full Viewing Key
  final orchardFvk = ufvk.getOrchard();

  /// Sapling Full Viewing Key
  final saplingFvk = ufvk.getSapling();

  /// Transparent Full Viewing Key
  final transparentFvk = ufvk.getTransparent();

  /// Sapling Incoming Viewing Keys (external + internal)
  final saplingIVKs = [
    saplingFvk.toIvk(Bip44Changes.chainExt),
    saplingFvk.toIvk(Bip44Changes.chainInt),
  ];

  /// Orchard Incoming Viewing Keys (external + internal)
  final orchardIvks = [
    orchardFvk.toIvk(scope: Bip44Changes.chainExt, context: context),
    orchardFvk.toIvk(scope: Bip44Changes.chainInt, context: context),
  ];

  /// Default unified address (contains Orchard, Sapling, Transparent receivers)
  final address = ufvk.defaultAddress(context: context);

  /// Encode as a standard Zcash address string
  final zcashAddress = ZCashAddress(address.address);

  // Example:
  // print("Mnemonic: $mnemonic");
  // print("Unified Address: $zcashAddress");
}
