# ZCash Dart

Low-level Dart library for Zcash wallets, SDKs, and protocol-level applications: transparent, Sapling, and Orchard transactions, unified addresses and keys, note scanning, PCZT, and zero-knowledge proving.

This package is the continuation of the original
[mrtnetwork/zcash_dart](https://github.com/mrtnetwork/zcash_dart).

## Crypto engine: `blockchain_utils` dual backend

All cryptography and proving delegate to
[`blockchain_utils`](https://github.com/mrtnetwork/blockchain_utils): pure
Dart by default, optional Rust backend (FFI on native, WASM on web). Details
live in the
[`blockchain_utils` README](https://github.com/mrtnetwork/blockchain_utils);
the Rust core is maintained at
[mrtnetwork/blockchain-utils](https://github.com/mrtnetwork/blockchain-utils).

> Proving (Sapling / Orchard) runs on `blockchainUtils.api` — select the Rust
> backend first, as pure-Dart Groth16 / Halo2 proving is unavailable:
>
> ```dart
> blockchainUtils.setRustApi();
> ```

## Supported networks

| Network | Transparent | Sapling | Orchard |
|---|---|---|---|
| Mainnet | ✅ | ✅ | ✅ |
| Testnet | ✅ | ✅ | ✅ |
| Regtest | ✅ (examples + local node) | ✅ | ✅ |

> Regtest activation heights default to `1` (`ProtocolActivationHeights`
> `regtest: 1`) — a non-standard testing default, not a real chain schedule.
> If your regtest node activates upgrades at different heights, provide your
> own `UpgradeActivationProvider` (see `DefaultUpgradeActivationProvider`) and
> pass it to `ZcashBlockProcessorConfig`.

## Features

### Transactions

| Area | Support |
|---|---|
| Versions | All supported Zcash transaction versions incl. NU7 (ZIP 259, v6), serialize/deserialize |
| Bundles | Transparent, Sapling, and Orchard create / sign / verify |
| PCZT | Partially Constructed Zcash Transactions (build, combine, finalize) |
| Merkle | Incremental Merkle tree + bridges, anchor checks, multi-account merge |

### Addresses & keys

| Area | Support |
|---|---|
| Transparent | P2PKH, P2SH |
| Shielded | Sprout, Sapling payment addresses |
| Unified | UA (receivers), USK / UFVK / UIVK |
| HD | ZIP-32, BIP-32 |

### Notes & scanning

| Area | Support |
|---|---|
| Notes | Sapling / Orchard note encryption, decryption, nullifiers |
| Scanner | Block processor + trial decryption, overlap scans, spent tracking |

### Zero-knowledge proving

| Area | Support |
|---|---|
| Sapling | Prove via `blockchainUtils.api.sapling` (Rust backend) |
| Orchard | Prove via `blockchainUtils.api.orchard` (Rust Halo2 bridge) |
| Primitives | BLS12-381, JubJub, Pallas/Vesta, Sinsemilla, Poseidon, FF1, f4jumble (all in `blockchain_utils`) |

### Providers

| API | Support |
|---|---|
| `walletd` | Wallet integration provider |
| Local node | Regtest + local-node example flows |

## Examples

See [`example/`](https://github.com/mrtnetwork/zcash_dart/tree/main/example)
(transparent, Sapling, Orchard, multi-account Merkle merge, anchor checks,
validation suite, address examples, local node).

## Testing

```sh
dart test            # unit + backend-parity suites
```

Backend-parity one-shot suites (`one_shot_suite.dart`, `test_backend.dart`)
exercise both the pure-Dart and Rust/WASM backends; browser WASM tests need
the built `test/wasm_assets`.

## Web support

Core cryptography runs in pure Dart with no native dependency, so the web
build works out of the box. Proof generation is computationally heavy —
select the WASM Rust backend and keep proving off the browser main thread.

## Contributing

Contributions are welcome.

1. Fork the repository
2. Create a feature branch
3. Ensure tests pass
4. Open a pull request with a clear description

## Bug Reports & Feature Requests

Please use the GitHub Issues tab for:

- Bug reports
- Feature requests
- Security concerns
- Improvement suggestions
