@TestOn('browser')
@Tags(['wasm'])
library;

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:test/test.dart';
import 'package:zcash_dart/zcash.dart';

import 'utils.dart';

void main() {
  setUpAll(() async {
    // Shared harness: injects the glue script (served by the dart-test
    // static handler from test/wasm_assets/), waits for bootstrap, then
    // selects the Rust backend. No .so involved.
    await ZcashTestApi.initWasmBrowser();
  });

  group('wasm backend smoke (zcash_dart)', () {
    test('sha256 empty (shared backend)', () {
      expect(
        BytesUtils.toHexString(QuickCrypto.sha256Hash([])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
    test('transparent p2pkh address roundtrip', () {
      const addr = 't1V9mnyk5Z5cTNMCkLbaDwSskgJZucTLdgW';
      expect(ZcashP2pkhAddress(addr).address, addr);
    });
  });
}
