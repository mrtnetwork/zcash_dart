import 'package:blockchain_utils/blockchain_utils.dart';

import 'package:zcash_dart/zcash.dart';

class ZcashTestAccount with Equality {
  final UnifiedSpendingKey usk;
  final SaplingExpandedSpendingKey saplingSk;
  final OrchardSpendingKey orchardSk;
  final List<SaplingIncomingViewingKey> saplingIvks;
  final List<OrchardIncomingViewingKey> orchardIvks;
  final SaplingDiversifiableFullViewingKey saplingFvk;
  final OrchardFullViewingKey orchardFvk;
  final Bip32Slip10Secp256k1 transparent;
  final Bip32Slip10Secp256k1 transparentSk;
  final UnifiedFullViewingKey ufvk;
  final UnifiedIncomingViewingKey uivk;
  final UnifiedIncomingViewingKey uivkInternal;
  final ZcashUnifiedAddress address;
  @override
  List<dynamic> get variables => [
    usk,
    saplingSk,
    saplingIvks,
    orchardIvks,
    saplingFvk,
    orchardFvk,
    transparent,
    transparentSk,
    ufvk,
    uivk,
    uivkInternal,
  ];

  const ZcashTestAccount({
    required this.saplingSk,
    required this.orchardSk,
    required this.saplingIvks,
    required this.orchardIvks,
    required this.saplingFvk,
    required this.orchardFvk,
    required this.transparent,
    required this.transparentSk,
    required this.ufvk,
    required this.uivk,
    required this.uivkInternal,
    required this.usk,
    required this.address,
  });
  factory ZcashTestAccount.fromUskHex(String sk, ZCryptoContext context) {
    final toBytes = BytesUtils.fromHexString(sk);
    return ZcashTestAccount.fromUsk(
      UnifiedSpendingKey.fromUnifiedSpendKeyBytes(
        uskBytes: toBytes,
        network: ZcashNetwork.testnet,
        context: context,
      ),
      context,
    );
  }
  factory ZcashTestAccount.fromUsk(
    UnifiedSpendingKey sk,
    ZCryptoContext context,
  ) {
    final ufvk = sk.toUnifiedFullViewingKey();
    final uivk = ufvk.toUnifiedIncomingViewingKey(context);
    final uivkInternal = ufvk.toUnifiedIncomingViewingKey(
      context,
      scope: Bip44Changes.chainInt,
    );

    final fvk = ufvk.getOrchard();

    final saplingFvk = ufvk.getSapling();
    final transparentFVK = ufvk.getTransparent();
    final saplingIVKs = [
      saplingFvk.toIvk(Bip44Changes.chainExt, context: context),
      saplingFvk.toIvk(Bip44Changes.chainInt, context: context),
    ];
    final orchardIvks = [
      fvk.toIvk(Bip44Changes.chainExt, context: context),
      fvk.toIvk(Bip44Changes.chainInt, context: context),
    ];
    return ZcashTestAccount(
      saplingSk: sk.sapling.privateKey.sk,
      orchardSk: sk.orchard.privateKey.sk,
      saplingIvks: saplingIVKs,
      orchardIvks: orchardIvks,
      saplingFvk: saplingFvk,
      orchardFvk: fvk,
      transparent: transparentFVK,
      transparentSk: sk.transparent,
      ufvk: ufvk,
      uivk: uivk,
      uivkInternal: uivkInternal,
      usk: sk,
      address: ZcashUnifiedAddress(
        ufvk.defaultAddress(context: context).address,
      ),
    );
  }

  String toHex() {
    return BytesUtils.toHexString(usk.encodeUnifiedSpeningKeyBytes());
  }

  factory ZcashTestAccount.fromSeed(
    ZcashCryptoContext context, {
    Bip32KeyIndex? accountIndex,
    List<int>? seed,
    ZcashNetwork network = ZcashNetwork.regtest,
  }) {
    final account = ZcashAccount.fromSeed(
      seedBytes: seed ?? List<int>.filled(32, 12),
      config: ZcashAccountConfig(network: network, transparent: true),
      context: context,
      accountIndex: accountIndex,
    );

    return ZcashTestAccount.fromUsk(account.toUnifiedSpendKey(), context);
  }
}
