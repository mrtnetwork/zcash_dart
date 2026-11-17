import 'package:zcash_dart/src/crypto/src/crypto.dart';
import 'package:zcash_dart/src/orchard/transaction/bundle.dart';
import 'package:zcash_dart/src/pczt/types/types.dart';
import 'package:zcash_dart/src/sapling/transaction/bundle.dart';

abstract mixin class PcztProver implements PcztV1 {
  Future<void> createOrchardProof({
    required ZcashCryptoContext context,
    required OrchardProtocolVersion version,
  }) {
    return orchard.createProof(context: context, version: version);
  }

  Future<void> createIronwoodProof({
    required ZcashCryptoContext context,
    required OrchardProtocolVersion version,
  }) {
    final ironwood = this.ironwood;
    if (ironwood == null) return Future.value();
    return ironwood.createProof(context: context, version: version);
  }

  Future<void> createSaplingProofs(ZcashCryptoContext context) {
    return sapling.createProofs(context);
  }

  void setOrchardProof(OrchardProof proof) => orchard.setZkProof(proof);

  void setIronwoodProof(OrchardProof proof) => ironwood?.setZkProof(proof);

  void setSaplingSpendProof(int index, GrothProofBytes proof) =>
      sapling.setSpendProof(index, proof);

  void setSaplingOutputProof(int index, GrothProofBytes proof) =>
      sapling.setOutputProof(index, proof);
}
