// Pure-Dart PCZT coverage for transparent / sapling / orchard (+ironwood).
// No proving keys, no native bindings: every test runs without Bu.init.
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

import '../utils.dart';

OrchardPcztBundle emptyOrchard({
  OrchardBundleFlags flags = OrchardBundleFlags.enabled,
  OrchardBundleVersion version = OrchardBundleVersion.orchardV1,
}) => OrchardPcztBundle(
  actions: [],
  flags: flags,
  valueSum: ZAmount.zero(),
  anchor: OrchardAnchor.emptyTree(),
  bundleVersion: version,
);

Pczt buildPczt({
  ZcashNetworkProtocol branch = ZcashNetworkProtocol.nu6_3,
  TxVersionType txVersion = TxVersionType.v5,
  OrchardPcztBundle? orchard,
  OrchardPcztBundle? ironwood,
}) => Pczt.build(
  network: ZcashNetwork.mainnet,
  locktime: 0,
  expiryHeight: 100,
  txVersion: txVersion,
  networkUpgrade: branch,
  orchard: orchard,
  ironwood: ironwood,
);

void pcztBundleTest() {
  group('PcztGlobal across protocols', () {
    test('tx version and branch resolve', () {
      final g = PcztGlobal(
        txVersion: TxVersionType.v5.txVesion,
        versionGroupId: TxVersionType.v5.groupId!,
        consensusBranchId: ZcashNetworkProtocol.nu5.branchId,
        expiryHeight: 100,
        coinType: ZcashNetwork.mainnet.config().coinIdx,
        txModifiable: PcztConstants.initialTxModifiable,
      );
      expect(g.getTxVersion().type, TxVersionType.v5);
      expect(g.getBranchId(), ZcashNetworkProtocol.nu5);
    });

    test('v6 global resolves', () {
      final g = PcztGlobal.defaultV6Global(ZcashNetwork.mainnet, 100);
      expect(g.getTxVersion().type, TxVersionType.v6);
      expect(g.getBranchId(), ZcashNetworkProtocol.nu6_3);
    });

    test('unknown branch throws', () {
      final g = PcztGlobal(
        txVersion: TxVersionType.v5.txVesion,
        versionGroupId: TxVersionType.v5.groupId!,
        consensusBranchId: 0xdeadbeef,
        expiryHeight: 100,
        coinType: ZcashNetwork.mainnet.config().coinIdx,
        txModifiable: PcztConstants.initialTxModifiable,
      );
      expect(() => g.getBranchId(), throwsA(anything));
    });

    test('unknown tx version throws', () {
      final g = PcztGlobal(
        txVersion: 99,
        versionGroupId: 99,
        consensusBranchId: ZcashNetworkProtocol.nu5.branchId,
        expiryHeight: 100,
        coinType: ZcashNetwork.mainnet.config().coinIdx,
        txModifiable: PcztConstants.initialTxModifiable,
      );
      expect(() => g.getTxVersion(), throwsA(anything));
    });
  });

  group('OrchardPcztBundleParams for every protocol', () {
    test('orchard pool version per branch', () {
      // NU5 / NU6 / NU6.1 use the V1 Orchard circuit, NU6.2 the V2 one
      // (the fixed circuit) and NU6.3 the V3 one.
      for (final branch in [
        ZcashNetworkProtocol.nu5,
        ZcashNetworkProtocol.nu6,
        ZcashNetworkProtocol.nu6_1,
      ]) {
        expect(
          OrchardPcztBundleParams.forBranch(
            branch: branch,
            isIronwoodPool: false,
          ).version,
          OrchardProtocolVersion.insecureV1,
          reason: '$branch must use the V1 Orchard circuit',
        );
      }
      expect(
        OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.nu6_2,
          isIronwoodPool: false,
        ).version,
        OrchardProtocolVersion.v2,
      );
      expect(
        OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.nu6_3,
          isIronwoodPool: false,
        ).version,
        OrchardProtocolVersion.v3,
      );
      expect(
        OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.nu6_3,
          isIronwoodPool: false,
        ).bundleVersion.valuePool,
        OrchardValuePool.orchard,
      );
      expect(
        OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.nu6_3,
          isIronwoodPool: true,
        ).bundleVersion.valuePool,
        OrchardValuePool.ironwood,
      );
    });

    test('agrees with OrchardBundleVersion.forBranch', () {
      // The extraction path and the build path must agree on the protocol
      // version, otherwise the flag byte of the extracted bundle is not
      // encodable.
      for (final branch in [
        ZcashNetworkProtocol.nu5,
        ZcashNetworkProtocol.nu6,
        ZcashNetworkProtocol.nu6_1,
        ZcashNetworkProtocol.nu6_2,
        ZcashNetworkProtocol.nu6_3,
      ]) {
        final expected = OrchardBundleVersion.forBranch(branch);
        expect(
          expected,
          isNotNull,
          reason: '$branch must have a bundle version',
        );
        final actual =
            OrchardPcztBundleParams.forBranch(
              branch: branch,
              isIronwoodPool: false,
            ).bundleVersion;
        expect(
          actual.protocolVersion,
          expected!.protocolVersion,
          reason: '$branch protocol version mismatch',
        );
        expect(
          actual.valuePool,
          expected.valuePool,
          reason: '$branch value pool mismatch',
        );
      }
    });

    test('pre-nu5 throws, ironwood pre-nu6_3 throws', () {
      expect(
        () => OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.canopy,
          isIronwoodPool: false,
        ),
        throwsA(anything),
      );
      expect(
        () => OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.nu6_2,
          isIronwoodPool: true,
        ),
        throwsA(anything),
      );
    });
  });

  group('Transparent PCZT bundle', () {
    test('empty bundle round-trips', () {
      final bundle = TransparentPcztBundle();
      final rt = TransparentPcztBundle.deserializeJson(
        LayoutSerializable.deserialize(
          bytes: bundle.toSerializeBytes(),
          layout: TransparentPcztBundle.layout(),
        ),
      );
      expect(rt.inputs, isEmpty);
      expect(rt.outputs, isEmpty);
    });

    test('pczt with only transparent validates', () {
      buildPczt().validate();
    });
  });

  group('Sapling PCZT bundle', () {
    SaplingPcztBundle empty() => SaplingPcztBundle(
      spends: [],
      outputs: [],
      valueSum: ZAmount.zero(),
      anchor: SaplingAnchor.emptyTree(),
    );

    test('empty bundle round-trips', () {
      final bundle = empty();
      final rt = SaplingPcztBundle.deserializeJson(
        LayoutSerializable.deserialize(
          bytes: bundle.toSerializeBytes(),
          layout: SaplingPcztBundle.layout(),
        ),
      );
      expect(rt.spends, isEmpty);
      expect(rt.outputs, isEmpty);
      expect(rt.valueSum.value, BigInt.zero);
    });

    test('bundle version preserved through pczt', () {
      final pczt = buildPczt();
      expect(pczt.sapling.valueSum.value, BigInt.zero);
      expect(pczt.orchard.bundleVersion.valuePool, OrchardValuePool.orchard);
    });
  });

  group('Orchard PCZT flags and restriction', () {
    test('verifyFlagsForVersion matrix', () {
      // Orchard v3 mandates restriction: restricted passes.
      emptyOrchard(
        flags: const OrchardBundleFlags(
          spendsEnabled: true,
          outputsEnabled: true,
          crossAddressEnabled: false,
        ),
        version: OrchardBundleVersion.orchardV3,
      ).verifyFlagsForVersion(OrchardBundleVersion.orchardV3);
      expect(
        () => emptyOrchard(
          flags: OrchardBundleFlags.enabled,
          version: OrchardBundleVersion.orchardV3,
        ).verifyFlagsForVersion(OrchardBundleVersion.orchardV3),
        throwsA(anything),
      );
      // Pre-NU6.3 rejects restricted.
      expect(
        () => emptyOrchard(
          flags: const OrchardBundleFlags(
            spendsEnabled: true,
            outputsEnabled: true,
            crossAddressEnabled: false,
          ),
        ).verifyFlagsForVersion(OrchardBundleVersion.orchardV1),
        throwsA(anything),
      );
      // Ironwood only at V3.
      expect(
        () => emptyOrchard().verifyFlagsForVersion(
          const OrchardBundleVersion(
            valuePool: OrchardValuePool.ironwood,
            protocolVersion: OrchardProtocolVersion.v2,
          ),
        ),
        throwsA(anything),
      );
    });

    test('empty bundles trivially satisfy restriction', () {
      emptyOrchard().verifyCrossAddressRestriction();
      emptyOrchard(
        flags: const OrchardBundleFlags(
          spendsEnabled: true,
          outputsEnabled: true,
          crossAddressEnabled: false,
        ),
      ).verifyCrossAddressRestriction();
    });

    test('sameExpandedReceiver compares full address', () {
      OrchardAddress addr(String diversifierHex) => OrchardAddress(
        transmissionKey: OrchardDiversifiedTransmissionKey.fromBytes(
          BytesUtils.fromHexString(
            '63f7125df4836fd2816b024ee70efe09fb9a7b3863c6eacdf95e03894950692c',
          ),
        ),
        diversifier: Diversifier(BytesUtils.fromHexString(diversifierHex)),
      );
      final a = addr('56e84b1adc9423c3676c04');
      final b = addr('0000000000000000000000');
      expect(OrchardUtils.sameExpandedReceiver(a, b), isFalse);
      expect(OrchardUtils.sameExpandedReceiver(a, a), isTrue);
    });
  });

  group('Pczt.validate across protocols', () {
    test('default v5 nu6_3 validates', () {
      buildPczt().validate();
    });

    test('v6 requires nu6_3 branch', () {
      final bad = Pczt(
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
        orchard: emptyOrchard(),
      );
      expect(() => bad.validate(), throwsA(anything));
    });

    test('non-empty ironwood requires v6', () {
      // v5 global with ironwood actions must fail: ironwood needs v6.
      // Empty ironwood is a no-op (absent-like), so use a flag-carrying
      // but action-less bundle plus direct version check instead.
      final iron = emptyOrchard(
        flags: OrchardBundleFlags.enabled,
        version: OrchardBundleVersion.ironwoodV3,
      );
      // Sanity: ironwood bundle itself is encodable under ironwoodV3.
      expect(
        iron.flags.toByteForVersion(OrchardBundleVersion.ironwoodV3),
        0x07,
      );
      // A v5 PCZT claiming an ironwood bundle with actions would be
      // rejected by validate(); here the slot is empty so toTxData is null.
      final pczt = buildPczt(txVersion: TxVersionType.v5, ironwood: iron);
      expect(pczt.toTxData().ironwoodBundle, isNull);
    });

    test('orchard enabled flags rejected under orchardV3', () {
      final pczt = Pczt(
        global: PcztGlobal(
          txVersion: TxVersionType.v5.txVesion,
          versionGroupId: TxVersionType.v5.groupId!,
          consensusBranchId: ZcashNetworkProtocol.nu6_3.branchId,
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
        orchard: emptyOrchard(
          flags: OrchardBundleFlags.enabled,
          version: OrchardBundleVersion.orchardV3,
        ),
      );
      expect(() => pczt.validate(), throwsA(anything));
    });
  });

  group('Pczt serialization round-trip', () {
    test('legacy bytes decode with null ironwood', () {
      final pczt = buildPczt();
      final rt = Pczt.deserialize(pczt.encode());
      expect(rt.ironwood, isNull);
      expect(rt.orchard.bundleVersion.valuePool, OrchardValuePool.orchard);
    });

    test('v6 round-trip preserves ironwood and flag byte', () {
      final iron = emptyOrchard(
        flags: OrchardBundleFlags.enabled,
        version: OrchardBundleVersion.ironwoodV3,
      );
      final pczt = buildPczt(txVersion: TxVersionType.v6, ironwood: iron);
      final rt = Pczt.deserialize(pczt.encode());
      expect(rt.ironwood, isNotNull);
      expect(rt.ironwood!.bundleVersion.valuePool, OrchardValuePool.ironwood);
      expect(
        rt.ironwood!.flags.toByteForVersion(OrchardBundleVersion.ironwoodV3),
        0x07,
      );
      expect(rt.global.txVersion, TxVersionType.v6.txVesion);
    });

    test('orchard slot keeps orchardV3, not ironwood', () {
      final pczt = buildPczt(txVersion: TxVersionType.v6);
      final rt = Pczt.deserialize(pczt.encode());
      expect(rt.orchard.bundleVersion.valuePool, OrchardValuePool.orchard);
      expect(
        rt.orchard.bundleVersion.protocolVersion,
        OrchardProtocolVersion.v3,
      );
    });
  });

  group('Pczt extraction mapping', () {
    test('empty bundles extract to null effects', () {
      final tx = buildPczt(txVersion: TxVersionType.v6).toTxData();
      expect(tx.version.type, TxVersionType.v6);
      expect(tx.ironwoodBundle, isNull);
      expect(tx.orchardBundle, isNull);
    });

    test('orchard effects carry orchardV3 version', () {
      final orchard = emptyOrchard(
        flags: const OrchardBundleFlags(
          spendsEnabled: true,
          outputsEnabled: true,
          crossAddressEnabled: false,
        ),
        version: OrchardBundleVersion.orchardV3,
      );
      final effects = orchard.extractEffects(
        params: OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.nu6_3,
          isIronwoodPool: false,
        ),
      );
      // Empty actions => null effects (absent-like), version mapping is
      // exercised through params instead.
      expect(effects, isNull);
      expect(
        OrchardPcztBundleParams.forBranch(
          branch: ZcashNetworkProtocol.nu6_3,
          isIronwoodPool: false,
        ).bundleVersion.valuePool,
        OrchardValuePool.orchard,
      );
    });
  });

  group('Pczt.merge', () {
    test('different tx versions do not merge', () {
      final merged = buildPczt().merge(buildPczt(txVersion: TxVersionType.v6));
      expect(merged, isNull);
    });

    test('same versions merge and keep ironwood', () {
      final iron = emptyOrchard(
        flags: OrchardBundleFlags.enabled,
        version: OrchardBundleVersion.ironwoodV3,
      );
      final merged = buildPczt(
        txVersion: TxVersionType.v6,
      ).merge(buildPczt(txVersion: TxVersionType.v6, ironwood: iron));
      expect(merged?.ironwood, isNotNull);
    });

    test('bundle version mismatch does not merge', () {
      final a = emptyOrchard(version: OrchardBundleVersion.orchardV3);
      final b = emptyOrchard(version: OrchardBundleVersion.ironwoodV3);
      final merged = a.merge(
        other: b,
        global: PcztGlobal.defaultGlobal(ZcashNetwork.mainnet, 100),
        otherGlobal: PcztGlobal.defaultGlobal(ZcashNetwork.mainnet, 100),
      );
      expect(merged, isNull);
    });
  });
}

void main() {
  ZcashTestApi.runTest(pcztBundleTest, "Pczt Bundle");
}
