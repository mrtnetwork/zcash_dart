// Zcash regtest: keys and addresses (offline, no network).

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:example/examples/local/zcash_node.dart';
import 'package:zcash_dart/zcash.dart';

Future<void> main() async {
  final net = await ZcashRegtest.connect();
  final context = net.context;

  print('Zcash regtest: keys and addresses');
  print(field('network', 'regtest'));
  print(
    field(
      'consensus branch',
      '${net.branch.name} '
          '(0x${net.branch.branchId.toRadixString(16)})',
    ),
  );
  print(field('sapling params', 'downloaded on first proof'));
  print('');

  final alice = ZcashExampleAccount.fromSeed(context, index: 0);
  final bob = ZcashExampleAccount.fromSeed(context, index: 1);

  print('alice (index 0)');
  print(field('  transparent', alice.transparentAddress.address));
  print(field('  transparent change', alice.transparentChangeAddress.address));
  print(field('  sapling', alice.saplingAddress));
  print(field('  orchard', alice.orchardAddress));
  print(field('  unified', alice.unifiedAddress));

  print('');
  print('bob (index 1)');
  print(field('  transparent', bob.transparentAddress.address));
  print(field('  sapling', bob.saplingAddress));

  print('');
  print('the two accounts are unrelated:');
  print(
    field(
      '  same transparent',
      '${alice.transparentAddress.address == bob.transparentAddress.address}',
    ),
  );
  print(
    field('  same sapling', '${alice.saplingAddress == bob.saplingAddress}'),
  );

  print('');
  print('the unified address carries every receiver:');
  final decoded = ZcashAddress(alice.unifiedAddress);
  final unified = decoded as ZcashUnifiedAddress;
  print(field('  receivers', '${unified.receivers.length}'));
  for (final receiver in unified.receivers) {
    print(field('    ${receiver.type.name}', '${receiver.data.length} bytes'));
  }
  print(
    field(
      '  protocols',
      unified.supportedProtocols.map((e) => e.name).join(', '),
    ),
  );

  print('');
  print('the orchard-only address decodes back to the same key:');
  final orchard = ZcashAddress(alice.orchardAddress);
  print(field('  type', '${orchard.addressType}'));
  print(field('  protocol', '${orchard.supportedProtocols}'));
  final orchardReceiver = unified.receivers.firstWhere(
    (e) => e.type == Typecode.orchard,
  );
  print(
    field('  matches orchard receiver', '${orchardReceiver.data.length == 43}'),
  );

  print('');
  print('the transparent address is a P2PKH on the regtest prefix:');
  final transparent = ZcashAddress(alice.transparentAddress.address);
  print(field('  type', '${transparent.addressType}'));
  print(
    field('  starts with', alice.transparentAddress.address.substring(0, 2)),
  );

  net.close();
  print('');
  print('done.');
}
