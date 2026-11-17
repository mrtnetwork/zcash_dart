import 'dart:async';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/transparent/keys/private_key.dart';

/// Provides cryptographic primitives required for Zcash protocol operations.
abstract mixin class ZcashCryptoContext implements ZCryptoContext {
  const ZcashCryptoContext();

  /// Signs a message using RedPallas.
  FutureOr<ReddsaSignature> signRedPallas(
    BaseRedPallasPrivateKey sk,
    List<int> message,
  );

  /// Verifies a RedPallas signature.
  FutureOr<bool> verifyRedPallasSignature({
    required BaseRedPallasPublicKey vk,
    required ReddsaSignature signature,
    required List<int> message,
  });

  /// Signs a message using RedJubJub.
  FutureOr<ReddsaSignature> signRedJubJub(
    RedJubJubSpendPrivateKey sk,
    List<int> message,
  );

  /// Verifies a RedJubJub signature
  FutureOr<bool> verifyRedJubJubSignature({
    required BaseRedJubJubPublicKey vk,
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
  ///
  /// [version] is the circuit version (0 insecure pre-NU6.2, 1 fixed
  /// post-NU6.2, 2 NU6.3) and [disableCrossAddress] must match the key
  /// (applies to version 2 only). No default: consensus decides.
  FutureOr<OrchardProof> createOrchardProof(
    List<OrchardProofInputs> args, {
    required OrchardProtocolVersion version,
    bool disableCrossAddress = false,
  });

  /// Creates Sapling spend proofs.
  FutureOr<List<GrothProofBytes>> createSaplingSpendProofs(
    List<SaplingSpendParams> args,
  );

  /// Creates Sapling output proofs.
  FutureOr<List<GrothProofBytes>> createSaplingOutputProofs(
    List<SaplingOutputParams> args,
  );

  /// Verifies an Orchard proof (same [version]/[disableCrossAddress] rules
  /// as [createOrchardProof]).
  FutureOr<bool> verifyOrchardProof(
    OrchardVerifyProofInputs args, {
    required OrchardProtocolVersion version,
    bool disableCrossAddress = false,
  });

  /// Verifies Sapling spend proofs.
  FutureOr<bool> verifySaplingSpendProofs(List<SaplingVerifyInputs> proofs);

  /// Verifies Sapling output proofs.
  FutureOr<bool> verifySaplingOutputProofs(List<SaplingVerifyInputs> proofs);

  BuBytes pedersonHash({
    required List<bool> bits,
    required Personalization personalization,
  });

  /// Returns the Orchard Merkle hashable implementation.
  OrchardMerkleHashable orchardHashable();

  /// Returns the Sapling Merkle hashable implementation.
  SaplingMerkleHashable saplingHashable();
}

/// Default implementation of the Zcash cryptographic context.
///
/// Proving (Sapling/Orchard) runs on `blockchainUtils.api` (Rust backend — call
/// `blockchainUtils.setRustApi(...)` first). Sapling ceremony params are resolved per batch
/// from [saplingSpendParamsBytes]/[saplingOutputParamsBytes] or downloaded
/// via [paramsDownloader] (+ optional URL overrides).
class DefaultZcashCryptoContext extends ZcashCryptoContext {
  /// Explicit Sapling params bytes (preferred: no download).
  List<int>? saplingSpendParamsBytes;
  List<int>? saplingOutputParamsBytes;

  /// Optional runtime params downloader (used only when bytes are absent).
  ZcashDownloadService? paramsDownloader;
  Uri? spendParamsUrl;
  Uri? outputParamsUrl;

  DefaultZcashCryptoContext({
    this.saplingSpendParamsBytes,
    this.saplingOutputParamsBytes,
    this.paramsDownloader,
    this.spendParamsUrl,
    this.outputParamsUrl,
  });

  /// Creates a fully initialized crypto context with optional injected components.
  factory DefaultZcashCryptoContext.sync({
    SaplingMerkleHashable? saplingMerkleHashable,
    OrchardMerkleHashable? orchardMerkleHashable,
    PedersenHash? pedersen,
    List<int>? saplingSpendParamsBytes,
    List<int>? saplingOutputParamsBytes,
    ZcashDownloadService? paramsDownloader,
    Uri? spendParamsUrl,
    Uri? outputParamsUrl,
  }) {
    final context = DefaultZcashCryptoContext(
      saplingSpendParamsBytes: saplingSpendParamsBytes,
      saplingOutputParamsBytes: saplingOutputParamsBytes,
      paramsDownloader: paramsDownloader,
      spendParamsUrl: spendParamsUrl,
      outputParamsUrl: outputParamsUrl,
    );
    context._orchardMerkleHashable = orchardMerkleHashable;
    context._pedersen = pedersen;
    context._saplingHashable = saplingMerkleHashable;
    return context;
  }

  /// Creates a lazily initialized crypto context with optional injected components.
  factory DefaultZcashCryptoContext.lazy({
    SaplingMerkleHashable? saplingMerkleHashable,
    OrchardMerkleHashable? orchardMerkleHashable,
    PedersenHash? pedersen,
    List<int>? saplingSpendParamsBytes,
    List<int>? saplingOutputParamsBytes,
    ZcashDownloadService? paramsDownloader,
    Uri? spendParamsUrl,
    Uri? outputParamsUrl,
  }) {
    final context = DefaultZcashCryptoContext(
      saplingSpendParamsBytes: saplingSpendParamsBytes,
      saplingOutputParamsBytes: saplingOutputParamsBytes,
      paramsDownloader: paramsDownloader,
      spendParamsUrl: spendParamsUrl,
      outputParamsUrl: outputParamsUrl,
    );
    context._orchardMerkleHashable = orchardMerkleHashable;
    context._pedersen = pedersen;
    context._saplingHashable = saplingMerkleHashable;
    return context;
  }

  PedersenHash? _pedersen;
  SaplingMerkleHashable? _saplingHashable;
  OrchardMerkleHashable? _orchardMerkleHashable;
  final Map<String, PallasAffinePoint> _hashDomainsQ = {};
  PallasAffinePoint getDomainPoint(String domain, {bool withSeperator = true}) {
    if (withSeperator) {
      domain += "-M";
    }
    final point =
        _hashDomainsQ[domain] ??= () {
          final message = StringUtils.encode(domain);
          final point = PallasPoint.hashToCurve(
            domainPrefix: HashDomainConst.qPersonalization,
            message: message,
          );
          return point.toAffine();
        }();
    return point;
  }

  @override
  FutureOr<ReddsaSignature> signRedJubJub(
    RedJubJubSpendPrivateKey sk,
    List<int> message,
  ) {
    return sk.sign(RedJubJubSigningParams(message));
  }

  @override
  FutureOr<ReddsaSignature> signRedPallas(
    BaseRedPallasPrivateKey sk,
    List<int> message,
  ) {
    return sk.sign(RedPallasSigningParams(message));
  }

  @override
  FutureOr<OrchardProof> createOrchardProof(
    List<OrchardProofInputs> args, {
    required OrchardProtocolVersion version,
    bool disableCrossAddress = false,
  }) async {
    if (args.isEmpty) {
      throw BuError(
        DefaultErrorType.invalidArgument,
        "No Orchard actions to prove.",
      );
    }
    _ensureSeeded();
    final packed = OrchardPackedCircuit.packActions(args);
    final seed = QuickCrypto.generateRandom(length: 32);
    final pk = _call('pkNew', () => _orchard.pkNew(version: version.version));
    try {
      final blob = _call(
        'createProof',
        () => _orchard.createProof(
          pk: pk,
          inputs: packed.inputs,
          instances: packed.instances,
          seed: seed.toList(),
          version: version.version,
          disableCrossAddress: disableCrossAddress,
        ),
      );
      return OrchardProof(blob.toList());
    } finally {
      _orchard.pkFree(pk);
    }
  }

  @override
  FutureOr<bool> verifyRedPallasSignature({
    required BaseRedPallasPublicKey vk,
    required ReddsaSignature signature,
    required List<int> message,
  }) {
    return vk.verify(RedPallasVerifyingParams(message, signature));
  }

  @override
  FutureOr<bool> verifyOrchardProof(
    OrchardVerifyProofInputs args, {
    required OrchardProtocolVersion version,
    bool disableCrossAddress = false,
  }) async {
    if (args.instances.isEmpty) return false;
    final instances = <int>[];
    for (final e in args.instances) {
      for (final b in e.instances()) {
        if (b.length != 32) {
          throw BuError(
            DefaultErrorType.invalidLength,
            "Bad instance limb length.",
          );
        }
        instances.addAll(b);
      }
    }
    // pkNew errors (bad version) propagate; a failed verification below
    // simply returns false.
    final pk = _call('pkNew', () => _orchard.pkNew(version: version.version));
    try {
      _call(
        'verifyProof',
        () => _orchard.verifyProof(
          pk: pk,
          proof: BuBytes(args.proofBytes),
          instances: BuBytes(instances),
          version: version.version,
          disableCrossAddress: disableCrossAddress,
        ),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      _orchard.pkFree(pk);
    }
  }

  @override
  FutureOr<bool> verifyRedJubJubSignature({
    required BaseRedJubJubPublicKey vk,
    required ReddsaSignature signature,
    required List<int> message,
  }) {
    return vk.verify(RedJubJubVerifyingParams(message, signature));
  }

  PedersenHash getPedersen() {
    return _pedersen ??= PedersenHash();
  }

  @override
  SaplingMerkleHashable saplingHashable() {
    return _saplingHashable ??= SaplingMerkleHashable(getPedersen());
  }

  @override
  OrchardMerkleHashable orchardHashable() {
    return _orchardMerkleHashable ??= OrchardMerkleHashable(
      domain: HashDomain.fromDomain("z.cash:Orchard-MerkleCRH"),
    );
  }

  SaplingApi get _sapling => blockchainUtils.api.sapling;
  OrchardApi get _orchard => blockchainUtils.api.orchard;

  static T _call<T>(String op, T Function() run) {
    try {
      return run();
    } on BuError catch (e) {
      if (e.type == DefaultErrorType.crypto) {
        throw BuError(
          ZcashErrorType.cryptoContext,
          "Backend $op failed: ${e.message}",
        );
      }
      rethrow;
    }
  }

  /// Resolve Sapling params bytes (explicit first, download fallback).
  Future<List<int>> _saplingParams(
    ZcashSaplingParameter type,
    List<int>? explicit,
  ) {
    return SaplingParamFetcher.getAndValidate(
      type: type,
      bytes: explicit,
      spendUrl: spendParamsUrl,
      outputUrl: outputParamsUrl,
      downloadService: paramsDownloader,
    );
  }

  /// Ensure the backend RNG is seeded (Rust falls back to a zero seed,
  /// which is unsafe for proving). Idempotent: only the first call seeds.
  void _ensureSeeded() {
    final rng = blockchainUtils.api.rng;
    if (rng.isSeeded) return;
    _call('seed', () {
      rng.seed(seed32: QuickCrypto.generateRandom(length: 32));
    });
  }

  /// Load params, run [fn] with the handle, always free it.
  Future<T> _withSaplingParams<T>(
    ZcashSaplingParameter type,
    List<int>? explicit,
    FutureOr<T> Function(Object handle) fn,
  ) async {
    final bytes = await _saplingParams(type, explicit);
    final Object handle;
    if (type == ZcashSaplingParameter.spend) {
      handle = _call('setSpendParams', () => _sapling.setSpendParams(bytes));
    } else {
      handle = _call('setOutputParams', () => _sapling.setOutputParams(bytes));
    }
    try {
      return await fn(handle);
    } finally {
      _sapling.paramsFree(handle);
    }
  }

  @override
  FutureOr<List<GrothProofBytes>> createSaplingSpendProofs(
    List<SaplingSpendParams> args,
  ) async {
    if (args.isEmpty) return [];
    _ensureSeeded();
    return _withSaplingParams(
      ZcashSaplingParameter.spend,
      saplingSpendParamsBytes,
      (handle) async {
        final out = <GrothProofBytes>[];
        for (final a in args) {
          final witness = SaplingPackedWitness.packSpend(a);
          final r = _call(
            'prove',
            () => _sapling.prove(
              handle: handle,
              kind: SaplingApi.spend,
              witness: witness,
            ),
          );
          out.add(GrothProofBytes(r.proof));
        }
        return out;
      },
    );
  }

  @override
  FutureOr<List<GrothProofBytes>> createSaplingOutputProofs(
    List<SaplingOutputParams> args,
  ) async {
    if (args.isEmpty) return [];
    _ensureSeeded();
    return _withSaplingParams(
      ZcashSaplingParameter.output,
      saplingOutputParamsBytes,
      (handle) async {
        final out = <GrothProofBytes>[];
        for (final a in args) {
          final witness = SaplingPackedWitness.packOutput(a);
          final r = _call(
            'prove',
            () => _sapling.prove(
              handle: handle,
              kind: SaplingApi.output,
              witness: witness,
            ),
          );
          out.add(GrothProofBytes(r.proof));
        }
        return out;
      },
    );
  }

  FutureOr<bool> _verifySapling(
    ZcashSaplingParameter type,
    int kind,
    List<SaplingVerifyInputs> proofs,
  ) async {
    if (proofs.isEmpty) return false;
    // Pack first: malformed inputs throw here instead of reading as failure.
    final packed = [
      for (final p in proofs)
        (
          proof: p.proof.inner,
          inputs: SaplingPackedWitness.packVerifyInputs(p),
        ),
    ];
    final bytes =
        type == ZcashSaplingParameter.spend
            ? saplingSpendParamsBytes
            : saplingOutputParamsBytes;
    return _withSaplingParams(type, bytes, (handle) async {
      try {
        for (final p in packed) {
          _sapling.verify(
            handle: handle,
            kind: kind,
            proof: BuBytes(p.proof),
            inputs: BuBytes(p.inputs),
          );
        }
        return true;
      } on BuError {
        return false;
      }
    }).catchError((_) => false);
  }

  @override
  FutureOr<bool> verifySaplingOutputProofs(List<SaplingVerifyInputs> proofs) {
    return _verifySapling(
      ZcashSaplingParameter.output,
      SaplingApi.output,
      proofs,
    );
  }

  @override
  FutureOr<bool> verifySaplingSpendProofs(List<SaplingVerifyInputs> proofs) {
    return _verifySapling(
      ZcashSaplingParameter.spend,
      SaplingApi.spend,
      proofs,
    );
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
  BuBytes pseudoRando({required List<int> nk, required List<int> rho}) {
    return blockchainUtils.api.hash.pseudoRando(nk: nk, rho: rho);
  }

  @override
  BuBytes? sinsemillaShortCommit({
    required List<int> r,
    required List<bool> bits,
    String domain = "z.cash:Orchard-CommitIvk",
  }) {
    return blockchainUtils.api.hash.sinsemillaShortCommit(
      r: r,
      bits: bits,
      domain: domain,
    );
  }

  @override
  BuBytes? sinsemillaCommit({
    required List<int> r,
    required List<bool> bits,
    String domain = "z.cash:Orchard-CommitIvk",
  }) {
    return blockchainUtils.api.hash.sinsemillaCommit(
      r: r,
      bits: bits,
      domain: domain,
    );
  }

  @override
  BuBytes pedersonHash({
    required List<bool> bits,
    required Personalization personalization,
  }) {
    // Routed through the hash backend (pure-Dart or native Rust).
    final (personal, layer) = switch (personalization) {
      PersonalizationNoteCommitment() => (0, 0),
      PersonalizationMerkleTree(:final size) => (1, size),
    };
    return blockchainUtils.api.hash.pedersenHashBitstring(
      personal: personal,
      layer: layer,
      bits: bits,
    );
  }
}
