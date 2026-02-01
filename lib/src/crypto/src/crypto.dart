import 'dart:async';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/exception.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/pedersen_hash/src/hash.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transparent/keys/private_key.dart';
import 'package:zcash_dart/src/zk_proof/bellman/bellman.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/proof.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/sapling/verifier.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/constants/fixed_bases.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/prover.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/verifier.dart';

/// Provides cryptographic primitives and precomputed tables required for
/// ZCash operations (e.g., Poseidon hash, Sinsemilla commitments, and
/// domain-separated commitments).
///
/// ⚠️ Expensive to instantiate: creating a `DefaultZCashCryptoContext` allocates
/// internal tables and constants, so it should be created **once** and
/// passed to any code that requires it, rather than recreated repeatedly.
///
/// For Sapling and Orchard proof creation and verification, use a [ZKLib] instance.
/// Pure Dart implementations of Groth16 and PLONK are very slow and may take
/// 30–120 seconds per proof with heavy computation.
/// Refer to the examples for configuring the prover and verifier.

/// Provides cryptographic primitives required for Zcash protocol operations.
abstract mixin class ZCashCryptoContext implements ZCryptoContext {
  const ZCashCryptoContext();

  /// Returns a hash domain for the given domain string.
  HashDomainNative getHashDomain(String domain, {bool withSeperator = false});

  /// Returns the domain separation base point for the given domain.
  PallasAffineNativePoint getDomainPoint(
    String domain, {
    bool withSeperator = true,
  });

  /// Returns fixed-base constants used for Orchard circuit operations.
  (List<List<PallasNativeFp>>, List<int>) getFixedConstants(
    OrchardFixedBases base,
  );

  /// Signs a message using RedPallas.
  FutureOr<ReddsaSignature> signRedPallas(
    OrchardSigningKey sk,
    List<int> message,
  );

  /// Verifies a RedPallas signature.
  FutureOr<bool> verifyRedPallasSignature({
    required OrchardVerifyingKey vk,
    required ReddsaSignature signature,
    required List<int> message,
  });

  /// Signs a message using RedJubJub.
  FutureOr<ReddsaSignature> signRedJubJub(
    SaplingSpendAuthorizingKey sk,
    List<int> message,
  );

  /// Verifies a RedJubJub signature
  FutureOr<bool> verifyRedJubJubSignature({
    required SaplingVerifyingKey vk,
    required ReddsaSignature signature,
    required List<int> message,
  });

  /// Signs a message using ECDSA and returns a DER-encoded signature.
  Future<List<int>> signEcdsaDer(
    ZECPrivate sk,
    List<int> message, {
    int? sighash = BitcoinOpCodeConst.sighashAll,
  });

  /// Creates Orchard zero-knowledge proofs.
  FutureOr<OrchardProof> createOrchardProof(List<OrchardProofInputs> args);

  /// Creates Sapling spend proofs.
  FutureOr<List<GrothProofBytes>> createSaplingSpendProofs(
    List<SaplingProofInputs<SaplingSpend>> args,
  );

  /// Creates Sapling output proofs.
  FutureOr<List<GrothProofBytes>> createSaplingOutputProofs(
    List<SaplingProofInputs<SaplingOutput>> args,
  );

  /// Verifies an Orchard proof.
  FutureOr<bool> verifyOrchardProof(OrchardVerifyInputs args);

  /// Verifies Sapling spend proofs.
  FutureOr<bool> verifySaplingSpendProofs(List<SaplingVerifyInputs> proofs);

  /// Verifies Sapling output proofs.
  FutureOr<bool> verifySaplingOutputProofs(List<SaplingVerifyInputs> proofs);

  /// Returns a Pedersen hash implementation.
  PedersenHashNative getPedersen();

  /// Returns an Orchard prover instance.
  BaseOrchardProver orchardProver();

  /// Returns an Orchard verifier instance.
  BaseOrchardVerifier orchardVerifier();

  /// Returns a Sapling prover instance.
  BaseSaplingProver saplingProver();

  /// Returns a Sapling verifier instance.
  BaseSaplingVerifier saplingVerifier();

  /// Returns the Orchard Merkle hashable implementation.
  OrchardMerkleHashable orchardHashable();

  /// Returns the Sapling Merkle hashable implementation.
  SaplingMerkleHashable saplingHashable();

  /// Returns the Poseidon hash specification.
  P128Pow5T3NativeFp getPoseidonSpec();

  /// Returns Sinsemilla generator points.
  List<PallasAffineNativePoint> getSinsemillaS();
}

/// Default implementation of the Zcash cryptographic context.
class DefaultZCashCryptoContext extends ZCashCryptoContext {
  /// Enables or disables Dart-based PLONK proof generation.
  final bool enableDartPlonk;

  DefaultZCashCryptoContext._({this.enableDartPlonk = false});

  /// Creates a fully initialized crypto context with optional injected components.
  factory DefaultZCashCryptoContext.sync({
    bool enableDartPlonk = false,
    BaseOrchardProver? orchardProver,
    BaseOrchardVerifier? orchardVerifier,
    P128Pow5T3NativeFp? spec,
    SaplingMerkleHashable? saplingMerkleHashable,
    OrchardMerkleHashable? orchardMerkleHashable,
    List<PallasAffineNativePoint>? sinsemillaS,
    PedersenHashNative? pedersen,
    BaseSaplingProver? saplingProver,
    BaseSaplingVerifier? saplingVerifier,
  }) {
    final context = DefaultZCashCryptoContext._(
      enableDartPlonk: enableDartPlonk,
    );
    context._orchardMerkleHashable = orchardMerkleHashable;
    context._pedersen = pedersen;
    context._orchardProver = orchardProver;
    context._orchardVerifier = orchardVerifier;
    context._saplingProver = saplingProver;
    context._saplingVerifier = saplingVerifier;
    context._spec = spec;
    context._saplingHashable = saplingMerkleHashable;
    context._sinsemillaS = sinsemillaS?.clone();
    if (enableDartPlonk) {
      context.orchardProver();
      context.orchardVerifier();
    }
    return context;
  }

  /// Creates a lazily initialized crypto context with optional injected components.
  factory DefaultZCashCryptoContext.lazy({
    bool enableDartPlonk = false,
    P128Pow5T3NativeFp? spec,
    SaplingMerkleHashable? saplingMerkleHashable,
    OrchardMerkleHashable? orchardMerkleHashable,
    List<PallasAffineNativePoint>? sinsemillaS,
    BaseOrchardProver? orchardProver,
    BaseOrchardVerifier? orchardVerifier,
    PedersenHashNative? pedersen,
    BaseSaplingProver? saplingProver,
    BaseSaplingVerifier? saplingVerifier,
  }) {
    final context = DefaultZCashCryptoContext._(
      enableDartPlonk: enableDartPlonk,
    );
    context._orchardMerkleHashable = orchardMerkleHashable;
    context._pedersen = pedersen;
    context._orchardProver = orchardProver;
    context._orchardVerifier = orchardVerifier;
    context._spec = spec;
    context._saplingHashable = saplingMerkleHashable;
    context._sinsemillaS = sinsemillaS?.clone();
    context._saplingProver = saplingProver;
    context._saplingVerifier = saplingVerifier;
    if (sinsemillaS != null) {
      context.getHashDomain("z.cash:Orchard-MerkleCRH");
    }
    return context;
  }

  final Map<String, CommitDomainNative> _cachedDomains = {};
  final Map<String, HashDomainNative> _cachedHashDomain = {};
  BaseOrchardProver? _orchardProver;
  BaseOrchardVerifier? _orchardVerifier;
  PedersenHashNative? _pedersen;
  SaplingMerkleHashable? _saplingHashable;
  OrchardMerkleHashable? _orchardMerkleHashable;
  P128Pow5T3NativeFp? _spec;
  List<PallasAffineNativePoint>? _sinsemillaS;

  BaseSaplingProver? _saplingProver;
  BaseSaplingVerifier? _saplingVerifier;

  final Map<OrchardFixedBases, (List<List<PallasNativeFp>>, List<int>)>
  _fixedConstants = {};

  (List<List<PallasNativeFp>>, List<int>) _buildConstants(
    OrchardFixedBases base,
  ) {
    final lagrangeCoeffs = base.lagrangeCoeffs();
    final z = base.z();
    return (lagrangeCoeffs, z);
  }

  final Map<String, PallasAffineNativePoint> _hashDomainsQ = {};
  @override
  PallasAffineNativePoint getDomainPoint(
    String domain, {
    bool withSeperator = true,
  }) {
    if (withSeperator) {
      domain += "-M";
    }
    final point =
        _hashDomainsQ[domain] ??= () {
          final message = StringUtils.encode(domain);
          final point = PallasNativePoint.hashToCurve(
            domainPrefix: HashDomainConst.qPersonalization,
            message: message,
          );
          return point.toAffine();
        }();
    return point;
  }

  @override
  (List<List<PallasNativeFp>>, List<int>) getFixedConstants(
    OrchardFixedBases base,
  ) {
    final constants = _fixedConstants[base] ??= _buildConstants(base);
    return constants;
  }

  @override
  List<PallasAffineNativePoint> getSinsemillaS() {
    return _sinsemillaS ??= HashDomainNative.generateSinsemillaS();
  }

  @override
  CommitDomainNative getCommitDomain(String domain) {
    return _cachedDomains[domain] ??= CommitDomainNative.create(
      domain,
      sinsemillaS: getSinsemillaS(),
    );
  }

  @override
  P128Pow5T3NativeFp getPoseidonSpec() {
    return _spec ??= P128Pow5T3NativeFp();
  }

  @override
  PoseidonHash<PallasNativeFp> getPoseidonHash() {
    return PoseidonHash(getPoseidonSpec());
  }

  @override
  HashDomainNative getHashDomain(String domain, {bool withSeperator = false}) {
    final name = "$withSeperator-$domain";
    return _cachedHashDomain[name] ??= HashDomainNative.fromDomain(
      domain,
      withSeperator: withSeperator,
      sinsemillaS: getSinsemillaS(),
    );
  }

  @override
  FutureOr<ReddsaSignature> signRedJubJub(
    SaplingSpendAuthorizingKey sk,
    List<int> message,
  ) {
    return sk.sign(message);
  }

  @override
  FutureOr<ReddsaSignature> signRedPallas(
    OrchardSigningKey sk,
    List<int> message,
  ) {
    return sk.sign(message);
  }

  @override
  FutureOr<OrchardProof> createOrchardProof(
    List<OrchardProofInputs> args,
  ) async {
    final proof = await orchardProver().createOrchardProof(args);
    return OrchardProof(proof);
  }

  @override
  FutureOr<bool> verifyRedPallasSignature({
    required OrchardVerifyingKey<OrchardVerifyingKey<dynamic>> vk,
    required ReddsaSignature signature,
    required List<int> message,
  }) {
    return vk.verifySignature(signature, message);
  }

  @override
  FutureOr<bool> verifyOrchardProof(OrchardVerifyInputs args) {
    final verifier = orchardVerifier();
    return verifier.verifyOrchardProof(args);
  }

  @override
  FutureOr<bool> verifyRedJubJubSignature({
    required SaplingVerifyingKey vk,
    required ReddsaSignature signature,
    required List<int> message,
  }) {
    return vk.verifySignature(signature, message);
  }

  @override
  PedersenHashNative getPedersen() {
    return _pedersen ??= PedersenHashNative();
  }

  @override
  BaseOrchardProver orchardProver() {
    final prover = _orchardProver;
    if (prover != null) return prover;
    if (!enableDartPlonk) {
      throw ZCashCryptoContextException("Missing orchard prover.");
    }
    return _orchardProver ??= DefaultOrchardProver.build(this);
  }

  @override
  SaplingMerkleHashable saplingHashable() {
    return _saplingHashable ??= SaplingMerkleHashable(getPedersen());
  }

  @override
  OrchardMerkleHashable orchardHashable() {
    return _orchardMerkleHashable ??= OrchardMerkleHashable(
      domain: getHashDomain("z.cash:Orchard-MerkleCRH"),
    );
  }

  @override
  BaseOrchardVerifier orchardVerifier() {
    final verifier = _orchardVerifier;
    if (verifier != null) return verifier;
    final prover = _orchardProver;
    if (prover != null && prover is DefaultOrchardProver) {
      return prover.toVerifier();
    }
    if (!enableDartPlonk) {
      throw ZCashCryptoContextException("Missing orchard proof verifier.");
    }
    return _orchardVerifier ??= DefaultOrchardVerifier.build(this);
  }

  @override
  BaseSaplingProver saplingProver() {
    final prover = _saplingProver;
    if (prover == null) {
      throw ZCashCryptoContextException("Missing sapling spend prover.");
    }
    return prover;
  }

  @override
  BaseSaplingVerifier saplingVerifier() {
    final verifier = _saplingVerifier;
    if (verifier == null) {
      throw ZCashCryptoContextException(
        "Missing sapling spend proof verifier.",
      );
    }
    return verifier;
  }

  @override
  FutureOr<List<GrothProofBytes>> createSaplingSpendProofs(
    List<SaplingProofInputs<SaplingSpend>> args,
  ) async {
    if (args.isEmpty) return [];
    final prover = saplingProver();
    final result = await prover.createSpendProofs(args);
    if (result.length != args.length) {
      throw ZCashCryptoContextException("Unexcpected proof response.");
    }
    return result;
  }

  @override
  FutureOr<List<GrothProofBytes>> createSaplingOutputProofs(
    List<SaplingProofInputs<SaplingOutput>> args,
  ) async {
    if (args.isEmpty) return [];
    final prover = saplingProver();
    final result = await prover.createOutputProofs(args);
    if (result.length != args.length) {
      throw ZCashCryptoContextException("Unexcpected proof response.");
    }
    return result;
  }

  @override
  FutureOr<bool> verifySaplingOutputProofs(List<SaplingVerifyInputs> proofs) {
    return saplingVerifier().verifyOutputProofs(proofs);
  }

  @override
  FutureOr<bool> verifySaplingSpendProofs(List<SaplingVerifyInputs> proofs) {
    return saplingVerifier().verifySpendProofs(proofs);
  }

  @override
  Future<List<int>> signEcdsaDer(
    ZECPrivate sk,
    List<int> message, {
    int? sighash,
  }) async {
    return sk.signECDSA(message, sighash: sighash);
  }
}
