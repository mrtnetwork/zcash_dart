# ZKLib

**ZKLib** provides the **Rust implementation of Zcash zero-knowledge proof APIs**
used by `zcash_dart`.

It exposes high-performance proof generation for:
- Sapling
- Orchard
- PLONK / Groth16

and is consumed from Dart via **FFI** and **WASM**.

---

## Build Instructions

### Native (FFI)

Compile the native library for your target platform:

```sh
cargo build --release --target <target-triple>
```

### Web (WASM)

```sh
cargo build --release --target <target-triple>

cargo build --release --target wasm32-unknown-unknown

wasm-bindgen \
  ./target/wasm32-unknown-unknown/release/zk.wasm \
  --out-dir ./pkg \
  --target web
  
```