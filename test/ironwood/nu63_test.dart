import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:zcash_dart/zcash.dart';

import '../utils.dart';

// Pure-logic NU6.2 / NU6.3 (Ironwood) coverage. No proving keys or secure
// randomness required: live ZIP-229 proving vectors remain pending on the
// native crypto environment (see builder_test FF1/prng note).
void nu63Test() {
  ZcashTestApi.runTest(_run, "Ironwood NU6.3");
}

void main() {
  ZcashTestApi.runTest(nu63Test, "Nu63");
}

void _run() {
  group("Ironwood consensus parameters", () {
    test("branch ids resolve", () {
      expect(
        ZcashNetworkProtocol.fromId(0x5437f330),
        ZcashNetworkProtocol.nu6_2,
      );
      expect(
        ZcashNetworkProtocol.fromId(0x37a5165b),
        ZcashNetworkProtocol.nu6_3,
      );
    });

    test("activation boundaries", () {
      const provider = DefaultUpgradeActivationProvider();
      expect(
        provider.protocolFromHeight(ZcashNetwork.mainnet, 3364599),
        ZcashNetworkProtocol.nu6_1,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.mainnet, 3364600),
        ZcashNetworkProtocol.nu6_2,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.mainnet, 3428142),
        ZcashNetworkProtocol.nu6_2,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.mainnet, 3428143),
        ZcashNetworkProtocol.nu6_3,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.testnet, 4052000),
        ZcashNetworkProtocol.nu6_2,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.testnet, 4134000),
        ZcashNetworkProtocol.nu6_3,
      );
    });

    test("helpers", () {
      expect(ZcashNetworkProtocol.nu6_3.hasIronwood(), true);
      expect(ZcashNetworkProtocol.nu6_2.hasIronwood(), false);
      expect(ZcashNetworkProtocol.nu6_3.hasOrchard(), true);
      expect(ZcashNetworkProtocol.nu6_3.hasSapling(), true);
    });
  });

  group("NU7 activation", () {
    const provider = DefaultUpgradeActivationProvider();
    test("branch id resolves", () {
      expect(ZcashNetworkProtocol.fromId(0x77190AD9), ZcashNetworkProtocol.nu7);
    });

    test("activation boundaries", () {
      expect(
        provider.protocolFromHeight(ZcashNetwork.mainnet, 3543404),
        ZcashNetworkProtocol.nu6_3,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.mainnet, 3543405),
        ZcashNetworkProtocol.nu7,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.testnet, 4465025),
        ZcashNetworkProtocol.nu6_3,
      );
      expect(
        provider.protocolFromHeight(ZcashNetwork.testnet, 4465026),
        ZcashNetworkProtocol.nu7,
      );
      expect(ZcashNetworkProtocol.nu7.hasIronwood(), true);
      expect(ZcashNetworkProtocol.nu7.hasOrchard(), true);
    });

    test("transaction version unchanged", () {
      expect(
        TxVersionType.v5
            .suggestedVersionForBranch(ZcashNetworkProtocol.nu7)
            .type,
        TxVersionType.v6,
      );
      expect(TxVersionType.v6.validInBranch(ZcashNetworkProtocol.nu7), true);
      expect(TxVersionType.v5.validInBranch(ZcashNetworkProtocol.nu7), true);
    });
  });

  group("Transaction version 6", () {
    test("group id and suggestion", () {
      expect(TxVersionType.v6.groupId, 0xD884B698);
      expect(
        TxVersionType.v5
            .suggestedVersionForBranch(ZcashNetworkProtocol.nu6_3)
            .type,
        TxVersionType.v6,
      );
      expect(
        TxVersionType.v5
            .suggestedVersionForBranch(ZcashNetworkProtocol.nu6_2)
            .type,
        TxVersionType.v5,
      );
    });

    test("valid in branch", () {
      expect(TxVersionType.v6.validInBranch(ZcashNetworkProtocol.nu6_3), true);
      expect(TxVersionType.v6.validInBranch(ZcashNetworkProtocol.nu6_2), false);
      expect(TxVersionType.v5.validInBranch(ZcashNetworkProtocol.nu6_3), true);
      expect(
        const TxVersionV6().hasIronwood() &&
            const TxVersionV6().hasOrchard() &&
            !const TxVersionV6().hasSprout(),
        true,
      );
    });
  });

  group("Orchard versions and flags", () {
    test("bundle version resolution", () {
      expect(
        OrchardBundleVersion.forBranch(ZcashNetworkProtocol.nu6_1),
        OrchardBundleVersion.orchardV1,
      );
      expect(
        OrchardBundleVersion.forBranch(ZcashNetworkProtocol.nu6_2),
        OrchardBundleVersion.orchardV2,
      );
      expect(
        OrchardBundleVersion.forBranch(ZcashNetworkProtocol.nu6_3),
        OrchardBundleVersion.orchardV3,
      );
      expect(
        OrchardBundleVersion.forBranch(
          ZcashNetworkProtocol.nu6_3,
          isIronwoodPool: true,
        ),
        OrchardBundleVersion.ironwoodV3,
      );
      expect(
        OrchardBundleVersion.forBranch(
          ZcashNetworkProtocol.nu6_2,
          isIronwoodPool: true,
        ),
        null,
      );
    });

    test("flag byte encoding", () {
      const flags = OrchardBundleFlags(
        spendsEnabled: true,
        outputsEnabled: true,
        crossAddressEnabled: true,
      );
      const restricted = OrchardBundleFlags(
        spendsEnabled: true,
        outputsEnabled: true,
        crossAddressEnabled: false,
      );
      expect(flags.toByteForVersion(OrchardBundleVersion.ironwoodV3), 0x07);
      expect(restricted.toByteForVersion(OrchardBundleVersion.orchardV3), 0x03);
      // Orchard pool under V3 mandates the restriction: enabled is
      // unrepresentable (official Flags::to_byte returns None).
      expect(
        () => flags.toByteForVersion(OrchardBundleVersion.orchardV3),
        throwsA(anything),
      );
      expect(flags.toByte(), 0x03);
      expect(
        () => OrchardBundleFlags.fromByte(0x07, OrchardBundleVersion.orchardV3),
        throwsA(anything),
      );
      expect(
        OrchardBundleFlags.fromByte(
          0x07,
          OrchardBundleVersion.ironwoodV3,
        ).crossAddressEnabled,
        true,
      );
    });
  });

  group("ZIP 317 fees", () {
    test("ironwood actions cost one marginal fee", () {
      const fee = Zip317FeeRole.standard();
      ZAmount req({required int orchard, required int ironwood}) =>
          fee.feeRequired(
            network: null,
            targetHeight: 0,
            trasparentInputSizes: 0,
            transparentOutputSizes: 0,
            saplingInputCount: 0,
            saplingOutputCount: 0,
            orchardActionCount: orchard,
            ironwoodActionCount: ironwood,
          );
      expect(req(orchard: 2, ironwood: 0).value, BigInt.from(10000));
      expect(req(orchard: 0, ironwood: 2).value, BigInt.from(10000));
      expect(req(orchard: 1, ironwood: 2).value, BigInt.from(15000));
    });
  });

  group("Digests", () {
    test("empty v5 vs v6 txids differ", () {
      final v5tx = TransactionData(
        version: const TxVersionV5(),
        consensusBranchId: ZcashNetworkProtocol.nu6_2,
        locktime: 0,
        expiryHeight: 0,
      );
      final v6tx = TransactionData(
        version: const TxVersionV6(),
        consensusBranchId: ZcashNetworkProtocol.nu6_3,
        locktime: 0,
        expiryHeight: 0,
      );
      expect(v5tx.toTxId().txId == v6tx.toTxId().txId, false);
    });
  });

  group("PCZT ironwood slot", () {
    Pczt build({
      OrchardPcztBundle? ironwood,
      TxVersionType v = TxVersionType.v5,
    }) {
      return Pczt.build(
        network: ZcashNetwork.mainnet,
        locktime: 0,
        expiryHeight: 100,
        txVersion: v,
        networkUpgrade: ZcashNetworkProtocol.nu6_3,
        ironwood: ironwood,
      );
    }

    OrchardPcztBundle emptyBundle() => OrchardPcztBundle(
      actions: [],
      flags: OrchardBundleFlags.enabled,
      valueSum: ZAmount.zero(),
      anchor: OrchardAnchor.emptyTree(),
    );

    test("round trip preserves ironwood", () {
      final pczt = build(v: TxVersionType.v6, ironwood: emptyBundle());
      final rt = Pczt.deserialize(pczt.encode());
      expect(rt.ironwood != null, true);
      expect(rt.global.txVersion, 6);
    });

    test("legacy bytes decode with null ironwood", () {
      final legacy = build();
      final rt = Pczt.deserialize(legacy.encode());
      expect(rt.ironwood, null);
    });

    test("merge keeps ironwood", () {
      final merged = build().merge(
        build(v: TxVersionType.v6, ironwood: emptyBundle()),
      );
      // Different tx versions cannot merge.
      expect(merged, null);
      final same = build(
        v: TxVersionType.v6,
      ).merge(build(v: TxVersionType.v6, ironwood: emptyBundle()));
      expect(same?.ironwood != null, true);
    });

    test("toTxData maps ironwood slot", () {
      final tx = build(v: TxVersionType.v6, ironwood: emptyBundle()).toTxData();
      expect(tx.version.type, TxVersionType.v6);
      // Empty PCZT bundles extract to null effects.
      expect(tx.ironwoodBundle, null);
    });
  });

  group("Builder pool rules", () {
    OrchardBuilder builder({
      required OrchardValuePool pool,
      required ZcashNetworkProtocol branch,
      OrchardBundleType? type,
    }) {
      return OrchardBuilder(
        bundleType: type ?? OrchardBundleType.defaultBundle(),
        anchor: OrchardAnchor.emptyTree(),
        context: DefaultZcashCryptoContext.lazy(),
        pool: pool,
        networkUpgrade: branch,
      );
    }

    test("note and bundle versions follow pool", () {
      final iron = builder(
        pool: OrchardValuePool.ironwood,
        branch: ZcashNetworkProtocol.nu6_3,
      );
      expect(iron.noteVersion, OrchardNoteVersion.v3);
      expect(iron.bundleVersion, OrchardBundleVersion.ironwoodV3);
      final orch = builder(
        pool: OrchardValuePool.orchard,
        branch: ZcashNetworkProtocol.nu6_3,
      );
      expect(orch.noteVersion, OrchardNoteVersion.v2);
      expect(orch.bundleVersion, OrchardBundleVersion.orchardV3);
    });

    test("coinbase orchard outputs rejected under nu6_3", () {
      final b = builder(
        pool: OrchardValuePool.orchard,
        branch: ZcashNetworkProtocol.nu6_3,
        type: const OrchardBundleTypeCoinbase(),
      );
      final recipient = OrchardAddress(
        transmissionKey: OrchardDiversifiedTransmissionKey.fromBytes(
          BytesUtils.fromHexString(
            "63f7125df4836fd2816b024ee70efe09fb9a7b3863c6eacdf95e03894950692c",
          ),
        ),
        diversifier: Diversifier(
          BytesUtils.fromHexString("56e84b1adc9423c3676c04"),
        ),
      );
      b.addOutput(
        recipient: recipient,
        value: ZAmount(BigInt.one),
        memo: List<int>.filled(NoteEncryptionConst.memoLength, 0),
      );
      // Guard fires before any randomness is consumed.
      expect(() => b.build(), throwsA(anything));
    });
  });

  group("Cross-address restriction", () {
    OrchardAddress addr(String diversifierHex) {
      return OrchardAddress(
        transmissionKey: OrchardDiversifiedTransmissionKey.fromBytes(
          BytesUtils.fromHexString(
            "63f7125df4836fd2816b024ee70efe09fb9a7b3863c6eacdf95e03894950692c",
          ),
        ),
        diversifier: Diversifier(BytesUtils.fromHexString(diversifierHex)),
      );
    }

    test("compares (g_d, pk_d), not raw diversifier bytes", () {
      final a = addr("56e84b1adc9423c3676c04");
      final b = addr("0000000000000000000000");
      expect(OrchardUtils.sameExpandedReceiver(a, b), false);
      expect(OrchardUtils.sameExpandedReceiver(a, a), true);
    });

    test("permits cross per version", () {
      expect(
        OrchardBundleVersion.orchardV3.permitsCrossAddressTransfers,
        false,
      );
      expect(
        OrchardBundleVersion.ironwoodV3.permitsCrossAddressTransfers,
        true,
      );
      expect(OrchardBundleVersion.orchardV1.permitsCrossAddressTransfers, true);
      expect(
        OrchardBundleVersion.orchardV3.defaultFlags().crossAddressEnabled,
        false,
      );
      expect(
        OrchardBundleVersion.ironwoodV3.defaultFlags().crossAddressEnabled,
        true,
      );
    });

    test("restricted builder rejects plain outputs", () {
      final b = OrchardBuilder(
        bundleType: OrchardBundleType.defaultBundle(),
        anchor: OrchardAnchor.emptyTree(),
        context: DefaultZcashCryptoContext.lazy(),
        pool: OrchardValuePool.orchard,
        networkUpgrade: ZcashNetworkProtocol.nu6_3,
      );
      expect(b.isRestricted, true);
      expect(b.effectiveFlags.crossAddressEnabled, false);
      b.addOutput(
        recipient: addr("56e84b1adc9423c3676c04"),
        value: ZAmount(BigInt.one),
        memo: List<int>.filled(NoteEncryptionConst.memoLength, 0),
      );
      expect(() => b.build(), throwsA(anything));
    });

    test("verify flags for version", () {
      final bundle = OrchardPcztBundle(
        actions: [],
        flags: OrchardBundleFlags.enabled,
        valueSum: ZAmount.zero(),
        anchor: OrchardAnchor.emptyTree(),
      );
      // cross bit allowed for ironwood, rejected for orchard v3.
      bundle.verifyFlagsForVersion(OrchardBundleVersion.ironwoodV3);
      expect(
        () => bundle.verifyFlagsForVersion(OrchardBundleVersion.orchardV3),
        throwsA(anything),
      );
      // Empty bundles trivially satisfy the restriction.
      bundle.verifyCrossAddressRestriction();
    });
  });

  group("Pczt.validate", () {
    test("default v5 nu6_3 build validates", () {
      Pczt.build(
        network: ZcashNetwork.mainnet,
        locktime: 0,
        expiryHeight: 100,
      ).validate();
    });

    test("v6 invalid in nu6_2 branch", () {
      final pczt = Pczt(
        global: PcztGlobal(
          txVersion: TxVersionType.v6.txVesion,
          versionGroupId: TxVersionType.v6.groupId!,
          consensusBranchId: ZcashNetworkProtocol.nu6_2.branchId,
          expiryHeight: 100,
          coinType: ZcashNetwork.mainnet.config().coinIdx,
          txModifiable: PcztConstants.initialTxModifiable,
        ),
        transparent: TransparentPcztBundle(),
        sapling: SaplingPcztBundle(
          spends: [],
          outputs: [],
          valueSum: ZAmount.zero(),
          anchor: SaplingAnchor.emptyTree(),
        ),
        orchard: OrchardPcztBundle(
          actions: [],
          flags: OrchardBundleFlags.enabled,
          valueSum: ZAmount.zero(),
          anchor: OrchardAnchor.emptyTree(),
        ),
      );
      expect(() => pczt.validate(), throwsA(anything));
    });
  });
  group("Compact ironwood fields", () {
    test("chain metadata json round trip", () {
      const meta = ZWalletdChainMetadata(
        saplingCommitmentTreeSize: 100,
        orchardCommitmentTreeSize: 200,
        ironwoodCommitmentTreeSize: 300,
      );
      final rt = ZWalletdChainMetadata.fromJson(meta.toJson());
      expect(rt.ironwoodCommitmentTreeSize, 300);
      expect(rt.orchardCommitmentTreeSize, 200);
      expect(rt.saplingCommitmentTreeSize, 100);
    });

    test("compact tx ironwood actions json round trip", () {
      const action = ZWalletdCompactOrchardAction(
        nullifier: [1, 2, 3],
        cmx: [4, 5, 6],
        ephemeralKey: [7, 8, 9],
        ciphertext: [10, 11, 12],
      );
      final tx = ZWalletdCompactTx(ironwoodActions: const [action]);
      final rt = ZWalletdCompactTx.fromJson(tx.toJson());
      expect(rt.ironwoodActions.length, 1);
      expect(rt.actions.isEmpty, true);
      expect(rt.ironwoodActions.first.nullifier, [1, 2, 3]);
    });
  });

  group("Ironwood output trial-decryption", () {
    for (final version in OrchardNoteVersion.values) {
      test("v${version.value} output decrypts with its pool domain", () {
        final context = DefaultZcashCryptoContext.lazy();
        final keys = OrchardUtils.createDummySpendKey();
        final fvk = keys.fvk;
        final recipient = fvk.addressAt(
          j: DiversifierIndex.zero(),
          context: context,
          scope: Bip44Changes.chainExt,
        );
        final ivk = fvk.toIvk(Bip44Changes.chainExt, context: context).ivk;
        final value = ZAmount.from(10000);
        final info = OrchardOutputInfo(
          recipient: recipient,
          value: value,
          memo: List<int>.filled(512, 0),
        );
        final nfOld = OrchardNullifier.random();
        final build = info.build(
          cvNet: OrchardValueCommitment.derive(
            value: value,
            rcv: OrchardValueCommitTrapdoor.random(),
          ),
          nfOld: nfOld,
          context: context,
          version: version,
        );
        final compact = CompactAction(
          nf: nfOld,
          cmx: build.cmx,
          ephemeralKey: EphemeralKeyBytes(build.encryotedNote.epkBytes),
          encCiphertextCompact: build.encryotedNote.encCiphertext.sublist(
            0,
            NoteEncryptionConst.compactNoteSize,
          ),
          outputIndex: 0,
        );
        final domain = OrchardDomain(context, version: version);
        final decrypt = domain.batchIvkCompactNoteDecryption(
          ivks: [ivk],
          output: compact,
        );
        expect(
          decrypt,
          isNotNull,
          reason: "v${version.value} output must trial-decrypt.",
        );
        expect(decrypt!.note.version, version);
        expect(
          decrypt.note.commitment(context).toExtractedNoteCommitment(),
          build.cmx,
        );
      });
    }
  });

  group("Lightwalletd branch activation provider", () {
    test("parses consensus branch ids", () {
      expect(
        LightwalletdBranchActivationProvider.tryParseBranchId('37a5165b'),
        ZcashNetworkProtocol.nu6_3,
      );
      expect(
        LightwalletdBranchActivationProvider.tryParseBranchId('0x5437F330'),
        ZcashNetworkProtocol.nu6_2,
      );
      expect(
        LightwalletdBranchActivationProvider.tryParseBranchId('0x77190AD9'),
        ZcashNetworkProtocol.nu7,
      );
      expect(
        LightwalletdBranchActivationProvider.tryParseBranchId(null),
        isNull,
      );
      expect(
        LightwalletdBranchActivationProvider.tryParseBranchId('not-hex'),
        isNull,
      );
      expect(
        LightwalletdBranchActivationProvider.tryParseBranchId('deadbeef'),
        isNull,
      );
    });

    test("pins branch regardless of height", () {
      // Custom regtest chain with NU6.3 active from genesis: static tables
      // (regtest pinned to a mainnet height) would resolve NU6.2 here.
      const pinned = LightwalletdBranchActivationProvider(
        ZcashNetworkProtocol.nu6_3,
      );
      expect(
        pinned.protocolFromHeight(ZcashNetwork.regtest, 1),
        ZcashNetworkProtocol.nu6_3,
      );
      expect(
        pinned.protocolFromHeight(ZcashNetwork.mainnet, 1),
        ZcashNetworkProtocol.nu6_3,
      );
      // Everything else delegates to static defaults.
      expect(
        pinned.activationHeight(
          ZcashNetworkProtocol.nu6_3,
          ZcashNetwork.mainnet,
        ),
        3428143,
      );
      expect(
        pinned.zip212Enforcement(ZcashNetwork.mainnet, 1),
        Zip212Enforcement.on,
      );
    });
  });
} // _run
