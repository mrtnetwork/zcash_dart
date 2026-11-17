## 0.3.0
- Network Upgrade 7 (NU7, ZIP 259): consensus branch, activation heights, and v6 transaction mapping. Regtest heights default to 1 (non-standard testing default — override `UpgradeActivationProvider` via `ZcashBlockProcessorConfig` for custom regtest schedules).
- Proving (Sapling/Orchard) now runs on the `blockchain_utils` dual backend; select it with `blockchainUtils.setRustApi()` (pure-Dart Groth16/Halo2 proving unavailable).
- Dual-backend test parity (pure Dart + Rust/WASM one-shot suites).
- Block processor with note scanning, overlap scans, and multi-account Merkle merge.

## 0.2.0

- Initial version.
