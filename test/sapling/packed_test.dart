import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

import '../utils.dart';

void packedTest() {
  // Packers are backend-independent (key helpers go through whichever
  // backend the harness selected).
  group('SaplingPackedWitness', () {
    List<int> fr(int v) => [...List<int>.filled(31, 0), v];

    // Official Zcash notes-encryption test diversifier (valid by construction).
    List<int> diversifierBytes() => [
      for (var i = 0; i < 'f19d9b797e39f337445839'.length; i += 2)
        int.parse('f19d9b797e39f337445839'.substring(i, i + 2), radix: 16),
    ];

    SaplingPaymentAddress address() {
      final a = SaplingPaymentAddress(
        transmissionKey: SaplingDiversifiedTransmissionKey.fromBytesUnchecked(
          List<int>.filled(32, 7),
        ),
        diversifier: Diversifier(diversifierBytes()),
      );
      a.gd();
      return a;
    }

    test('spend layout (1288 B)', () {
      final authPath = List.generate(
        32,
        (i) => (JubJubFq.fromBytes(fr(i + 1)), i.isEven),
      );
      final p = SaplingSpendParams(
        value: ZAmount(BigInt.parse('0102030405060708', radix: 16)),
        randomness: BuBytes.from(fr(1)),
        proofGenerationKey: SaplingProofGenerationKey(
          ak: RedJubJubSpendPublicKey.fromBytes(
            blockchainUtils.api.jubjub.generator(),
          ),
          nsk: BuBytes.from(fr(2)),
        ),
        paymentAddress: address(),
        commitmentRandomness: BuBytes.from(fr(3)),
        ar: BuBytes.from(fr(4)),
        authPath: authPath,
        anchor: SaplingAnchor(JubJubFq.fromBytes(fr(5))),
      );
      final packed = SaplingPackedWitness.packSpend(p);
      expect(packed.length, 1288);
      expect(packed.sublist(0, 8), [8, 7, 6, 5, 4, 3, 2, 1]);
      expect(packed.sublist(104, 136), p.paymentAddress.gd().toBytes());
      // pos bytes mirror the input bools (even indexes true here)
      final pos = packed.sublist(1224, 1256);
      for (var i = 0; i < 32; i++) {
        expect(pos[i], i.isEven ? 1 : 0);
      }
      expect(packed.sublist(1256), p.anchor.inner.toBytes());
    });

    test('output layout (168 B)', () {
      final to = address();
      final p = SaplingOutputParams(
        value: ZAmount(BigInt.one),
        randomness: BuBytes.from(fr(1)),
        paymentAddress: to,
        commitmentRandomness: SaplingNoteCommitTrapdoor(BuBytes.from(fr(2))),
        esk: BuBytes.from(fr(3)),
      );
      final packed = SaplingPackedWitness.packOutput(p);
      expect(packed.length, 168);
      expect(packed.sublist(0, 8), [1, 0, 0, 0, 0, 0, 0, 0]);
      expect(packed.sublist(40, 72), to.gd().toBytes());
      expect(packed.sublist(72, 104), to.transmissionKey.toBytes());
    });

    test('verify inputs concat (5 limbs)', () {
      final limbs = List.generate(5, (i) => JubJubFq.fromBytes(fr(i + 1)));
      final packed = SaplingPackedWitness.packVerifyInputs(
        SaplingVerifyInputs(
          proof: GrothProofBytes(List.filled(192, 0)),
          inputs: limbs,
        ),
      );
      expect(packed.length, 160);
      expect(packed.sublist(0, 32), fr(1));
      expect(packed.sublist(128), fr(5));
    });
  });
}

void main() {
  ZcashTestApi.runTest(packedTest, "Packed");
}
