import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/transaction/bundle.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';

abstract mixin class PcztProver implements PcztV1 {
  Future<void> createOrchardProof(ZcashCryptoContext context) {
    return orchard.createProof(context);
  }

  Future<void> createSaplingProofs(ZcashCryptoContext context) {
    return sapling.createProofs(context);
  }

  void setOrchardProof(OrchardProof proof) => orchard.setZkProof(proof);

  void setSaplingSpendProof(int index, GrothProofBytes proof) =>
      sapling.setSpendProof(index, proof);

  void setSaplingOutputProof(int index, GrothProofBytes proof) =>
      sapling.setOutputProof(index, proof);
}
