# ZCash Dart

**Zcash cryptography, transactions, and zero-knowledge proofs — implemented in Dart.**

`zcash_dart` is a low-level Dart library for building **Zcash wallets, SDKs, and protocol-level applications**.

It provides support for:

- Transparent transactions
- Sapling transactions
- Orchard transactions
- Zcash addresses and keys
- Zero-knowledge proof infrastructure

---

# Features

## Transactions

Support for Zcash transaction handling:

- Serialize and deserialize **all supported Zcash transaction versions**
- Create, sign, and verify:
  - Orchard bundles
  - Sapling bundles
  - Transparent transactions
- PCZT (**Partially Constructed Zcash Transaction**) support
- Dart implementation of the Zcash **Incremental Merkle Tree**

---

## Addresses & Keys

Support for Zcash key and address systems:

- Sprout addresses
- Sapling payment addresses
- Transparent addresses:
  - P2PKH
  - P2SH
- Unified Addresses
- ZIP-32 hierarchical deterministic wallets
- BIP-32 HD wallet support
- USK (**Unified Spending Key**)
- UFVK (**Unified Full Viewing Key**)
- UIVK (**Unified Incoming Viewing Key**)

---

# Zero-Knowledge Proofs

Support for Zcash zero-knowledge proof components:

- Orchard proving system
- Sapling proving system
- PLONK / Groth16 proof support

## Building ZK Provers

ZK proving code is located in the `zk` folder.

To compile ZK components for your target platform:

```bash
cd zk
cargo build --release [target]

```

Compile the prover for your required target:

- Native platforms
- WebAssembly (WASM)
- Other supported targets

---

# Cryptography

All Zcash-required cryptographic primitives are implemented in:

`blockchain_utils`

Supported primitives include:

- FF1 format-preserving encryption
- f4jumble
- BLS12-381
- Jubjub
- Pallas / Vesta curves
- Sinsemilla
- Poseidon hash

---

# Providers

Wallet integration support through:

- `walletd` provider

---

# Examples

See the [example](https://github.com/mrtnetwork/zcash_dart/blob/main/example/lib) folder for usage examples.

---

# Web Support

`zcash_dart` supports Dart Web.

Features:

- Core cryptographic primitives are implemented in pure Dart
- No native dependency is required for core cryptography
- Compatible with Dart Web
- Zero-knowledge components can be compiled to WebAssembly (WASM)

## Performance Considerations

Zcash cryptography and zero-knowledge proof generation are computationally expensive in Dart Web.

For production web applications:

- Compile heavy cryptographic operations to WASM
- Avoid blocking the browser main thread

---


# Contributing

Contributions are welcome.

1. Fork the repository
2. Create a feature branch
3. Ensure tests pass
4. Open a pull request with a clear description

---

# Bug Reports & Feature Requests

Please use the GitHub Issues tab for:

- Bug reports
- Feature requests
- Security concerns
- Improvement suggestions