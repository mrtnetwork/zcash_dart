# ZCash Dart

**Zcash cryptography, transactions, and zero-knowledge proofs — in Dart.**

`zcash_dart` is a low-level Dart package for building **Zcash wallets, SDKs, and protocol tooling**.  
It supports **Sapling**, **Orchard**, and **Transparent** transactions, with both **pure Dart** and **Rust-accelerated (FFI / WASM)** implementations.

Built for correctness first — performance where it matters.

---

> ⚠️ **Early Release**
>
> This project is in an initial stage.  
> Not production-ready. Expect bugs, breaking changes, and incomplete test coverage.


## Features

### Transactions
- Serialize and deserialize **all Zcash transaction versions**
- Create, sign, and verify:
  - Orchard bundles
  - Sapling bundles
  - Transparent transactions
- PCZT (Partially Constructed Zcash Transaction) support
- Dart port of Zcash **incremental Merkle tree**

---

### Addresses & Keys
- Sapling payment addresses
- Transparent addresses (P2SH/P2PKH)
- Sprout addresses
- P2PKH & P2SH
- Unified Addresses
- ZIP-32 / BIP-32 HD wallet support
- USK, UFVK, and UIVK support

---

### Zero-Knowledge Proofs

#### PLONK
- Pure Dart implementation (⚠️ slow: ~30–40s per proof)
- High-performance Rust backend (FFI / WASM)

#### Groth16
- Pure Dart implementation (⚠️ slow: ~30–40s per proof)
- High-performance Rust backend (FFI / WASM)

> ⚠️ **Production note**: Rust backends are strongly recommended for proof generation.

---

### Cryptography

All Zcash-required cryptographic primitives are implemented in `blockchain_utils`:

- FF1
- f4jumble
- BLS12-381
- Jubjub
- Vesta–Pallas
- Sinsemilla
- Poseidon

---

### Providers
- Wallet integration via **walletd provider**

---

## Examples

- **Transfer**
  - https://github.com/mrtnetwork/zcash_dart/blob/main/example/lib/example/transfer_example.dart
- **ZKLib**
  - https://github.com/mrtnetwork/zcash_dart/blob/main/example/lib/example/zk_lib_example.dart
- **Address Management**
  - https://github.com/mrtnetwork/zcash_dart/blob/main/example/lib/example/addreses.dart
- **Provider Usage**
  - https://github.com/mrtnetwork/zcash_dart/blob/main/example/lib/example/clinet/

---

## Contributing

Contributions are welcome.

1. Fork the repository
2. Create a feature branch
3. Ensure tests pass
4. Open a pull request with a clear description

---

## Bug Reports & Feature Requests

Please use the GitHub Issues tab.

---

## License

Specify your license (e.g. MIT, Apache-2.0).
