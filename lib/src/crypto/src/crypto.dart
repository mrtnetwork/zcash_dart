import 'dart:async';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/crypto/src/exception.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transparent/keys/private_key.dart';
import 'package:zcash_dart/src/zk_proof/lib/lib.dart';

/// Provides cryptographic primitives and precomputed tables required for
/// Zcash operations (e.g., Poseidon hash, Sinsemilla commitments, and
/// domain-separated commitments).
///
/// ⚠️ Expensive to instantiate: creating a `DefaultZcashCryptoContext` allocates
/// internal tables and constants, so it should be created **once** and
/// passed to any code that requires it, rather than recreated repeatedly.
///
/// For Sapling and Orchard proof creation and verification, use a [ZKLib] instance.
/// Pure Dart implementations of Groth16 and PLONK are very slow and may take
/// 30–120 seconds per proof with heavy computation.
/// Refer to the examples for configuring the prover and verifier.

/// Provides cryptographic primitives required for Zcash protocol operations.
abstract mixin class ZcashCryptoContext implements ZCryptoContext {
  const ZcashCryptoContext();

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
    List<SaplingSpendParams> args,
  );

  /// Creates Sapling output proofs.
  FutureOr<List<GrothProofBytes>> createSaplingOutputProofs(
    List<SaplingOutputParams> args,
  );

  /// Verifies an Orchard proof.
  FutureOr<bool> verifyOrchardProof(OrchardVerifyProofInputs args);

  /// Verifies Sapling spend proofs.
  FutureOr<bool> verifySaplingSpendProofs(List<SaplingVerifyInputs> proofs);

  /// Verifies Sapling output proofs.
  FutureOr<bool> verifySaplingOutputProofs(List<SaplingVerifyInputs> proofs);

  // // /// Returns a Pedersen hash implementation.
  // PedersenHashNative getPedersen();

  JubJubNativePoint pedersonHash({
    required List<bool> bits,
    required Personalization personalization,
  });

  /// Returns the Orchard Merkle hashable implementation.
  OrchardMerkleHashable orchardHashable();

  /// Returns the Sapling Merkle hashable implementation.
  SaplingMerkleHashable saplingHashable();
}

/// Default implementation of the Zcash cryptographic context.
class DefaultZcashCryptoContext extends ZcashCryptoContext {
  ZKLib? _lib;
  ZKLib? get lib => _lib;

  DefaultZcashCryptoContext({ZKLib? lib}) : _lib = lib;

  /// Creates a fully initialized crypto context with optional injected components.
  factory DefaultZcashCryptoContext.sync({
    P128Pow5T3NativeFp? spec,
    SaplingMerkleHashable? saplingMerkleHashable,
    OrchardMerkleHashable? orchardMerkleHashable,
    List<PallasNativePoint>? sinsemillaS,
    PedersenHashNative? pedersen,
    ZKLib? lib,
  }) {
    final context = DefaultZcashCryptoContext(lib: lib);
    context._orchardMerkleHashable = orchardMerkleHashable;
    context._pedersen = pedersen;
    context._spec = spec;
    context._saplingHashable = saplingMerkleHashable;
    context._sinsemillaS = sinsemillaS?.clone();
    return context;
  }

  /// Creates a lazily initialized crypto context with optional injected components.
  factory DefaultZcashCryptoContext.lazy({
    P128Pow5T3NativeFp? spec,
    SaplingMerkleHashable? saplingMerkleHashable,
    OrchardMerkleHashable? orchardMerkleHashable,
    List<PallasNativePoint>? sinsemillaS,
    PedersenHashNative? pedersen,
    ZKLib? lib,
  }) {
    final context = DefaultZcashCryptoContext(lib: lib);
    context._orchardMerkleHashable = orchardMerkleHashable;
    context._pedersen = pedersen;
    context._spec = spec;
    context._saplingHashable = saplingMerkleHashable;
    context._sinsemillaS = sinsemillaS?.clone();
    if (sinsemillaS != null) {
      context.getHashDomain("z.cash:Orchard-MerkleCRH");
    }
    return context;
  }

  final Map<String, CommitDomainNative> _cachedDomains = {};
  final Map<String, HashDomainNative> _cachedHashDomain = {};
  PedersenHashNative? _pedersen;
  SaplingMerkleHashable? _saplingHashable;
  OrchardMerkleHashable? _orchardMerkleHashable;
  P128Pow5T3NativeFp? _spec;
  List<PallasNativePoint>? _sinsemillaS;
  final Map<String, PallasAffineNativePoint> _hashDomainsQ = {};
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

  List<PallasNativePoint> getSinsemillaS() {
    return _sinsemillaS ??= HashDomainNative.generateSinsemillaS();
  }

  CommitDomainNative getCommitDomain(String domain) {
    return _cachedDomains[domain] ??= CommitDomainNative.create(
      domain,
      sinsemillaS: getSinsemillaS(),
    );
  }

  P128Pow5T3NativeFp getPoseidonSpec() {
    return _spec ??= P128Pow5T3NativeFp();
  }

  PoseidonHash<PallasNativeFp> getPoseidonHash() {
    return PoseidonHash(getPoseidonSpec());
  }

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
    final proof = await _getlib().createOrchardProof(args);
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
  FutureOr<bool> verifyOrchardProof(OrchardVerifyProofInputs args) {
    final verifier = _getlib();
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

  PedersenHashNative getPedersen() {
    return _pedersen ??= PedersenHashNative();
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

  ZKLib _getlib() {
    final prover = lib;
    if (prover == null) {
      throw ZcashCryptoContextException("Missing zk liberary.");
    }
    return prover;
  }

  T _foldZkLib<T>({
    required T Function(ZKLib lib) onZkLib,
    required T Function() onMissing,
  }) {
    final lib = this.lib;
    if (lib != null) {
      return onZkLib(lib);
    }
    return onMissing();
  }

  @override
  FutureOr<List<GrothProofBytes>> createSaplingSpendProofs(
    List<SaplingSpendParams> args,
  ) async {
    if (args.isEmpty) return [];
    final lib = _getlib();
    final result = await lib.createSpendProofs(args);
    if (result.length != args.length) {
      throw ZcashCryptoContextException("Unexcpected proof response.");
    }
    return result;
  }

  @override
  FutureOr<List<GrothProofBytes>> createSaplingOutputProofs(
    List<SaplingOutputParams> args,
  ) async {
    if (args.isEmpty) return [];
    final lib = _getlib();
    final result = await lib.createOutputProofs(args);
    if (result.length != args.length) {
      throw ZcashCryptoContextException("Unexcpected proof response.");
    }
    return result;
  }

  @override
  FutureOr<bool> verifySaplingOutputProofs(List<SaplingVerifyInputs> proofs) {
    final lib = _getlib();
    return lib.verifyOutputProofs(proofs);
  }

  @override
  FutureOr<bool> verifySaplingSpendProofs(List<SaplingVerifyInputs> proofs) {
    final lib = _getlib();
    return lib.verifySpendProofs(proofs);
  }

  @override
  Future<List<int>> signEcdsaDer(
    ZECPrivate sk,
    List<int> message, {
    int? sighash,
  }) async {
    return sk.signECDSA(message, sighash: sighash);
  }

  @override
  PallasNativeFp pseudoRando({
    required PallasNativeFp nk,
    required PallasNativeFp rho,
  }) {
    return getPoseidonHash().hash([nk, rho]);
  }

  @override
  PallasNativeFp? sinsemillaShortCommit({
    required VestaNativeFq r,
    required List<bool> bits,
    String domain = "z.cash:Orchard-CommitIvk",
  }) {
    return _foldZkLib(
      onZkLib: (lib) {
        try {
          final result = lib.sendRequest(
            ZKRequestCommitmentShortDomain(
              ZKCommitmentShortDomain(
                r: r.toBytes(),
                bits: bits,
                domain: domain,
              ),
            ),
          );
          return PallasNativeFp.fromBytes(result);
        } on ZKLibException catch (e) {
          if (e.code == ZKLibResponseCode.hashError) {
            return null;
          }
          rethrow;
        }
      },
      onMissing: () {
        final donmain = getCommitDomain(domain);
        return donmain.shortCommit(msg: bits, r: r);
      },
    );
  }

  @override
  PallasNativePoint? sinsemillaCommit({
    required VestaNativeFq r,
    required List<bool> bits,
    String domain = "z.cash:Orchard-CommitIvk",
  }) {
    return _foldZkLib(
      onZkLib: (lib) {
        try {
          final result = lib.sendRequest(
            ZKRequestCommitmentDomain(
              ZKCommitmentDomain(r: r.toBytes(), bits: bits, domain: domain),
            ),
          );
          return PallasNativePoint.fromBytes(result);
        } on ZKLibException catch (e) {
          if (e.code == ZKLibResponseCode.hashError) {
            return null;
          }
          rethrow;
        }
      },
      onMissing: () {
        final donmain = getCommitDomain(domain);
        return donmain.commit(msg: bits, r: r);
      },
    );
  }

  @override
  JubJubNativePoint pedersonHash({
    required List<bool> bits,
    required Personalization personalization,
  }) {
    return _foldZkLib(
      onZkLib: (lib) {
        int? merkleSize;
        if (personalization case PersonalizationMerkleTree(:final size)) {
          merkleSize = size;
        }
        final result = lib.sendRequest(
          ZKRequestPedersenHash(
            ZKPedersenHash(bits: bits, merkleTreeSize: merkleSize),
          ),
        );
        return JubJubNativePoint.fromBytes(result);
      },
      onMissing: () {
        final donmain = getPedersen();
        return donmain.hash(inputBits: bits, personalization: personalization);
      },
    );
  }
}
