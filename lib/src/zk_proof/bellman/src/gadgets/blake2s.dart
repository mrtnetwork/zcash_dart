import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/constraint.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/boolean.dart';
import 'package:zcash_dart/src/zk_proof/bellman/src/gadgets/uint32.dart';

class GBlake2sUtils {
  static const List<List<int>> _sigma = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  ];
  static void _mixingG(BellmanConstraintSystem<MultiEq> cs, List<GUInt32> v,
      (int, int, int, int) idx, GUInt32 x, GUInt32 y) {
    const int r1 = 16;
    const int r2 = 12;
    const int r3 = 8;
    const int r4 = 7;

    final (a, b, c, d) = idx;

    v[a] = GUInt32.addMany(cs, [v[a], v[b], x]);
    v[d] = v[d].xor(cs, v[a]).rotr(r1);
    v[c] = GUInt32.addMany(cs, [v[c], v[d]]);
    v[b] = v[b].xor(cs, v[c]).rotr(r2);
    v[a] = GUInt32.addMany(cs, [v[a], v[b], y]);
    v[d] = v[d].xor(cs, v[a]).rotr(r3);
    v[c] = GUInt32.addMany(cs, [v[c], v[d]]);

    v[b] = v[b].xor(cs, v[c]).rotr(r4);
  }

  static void _blake2sCompression(
    BellmanConstraintSystem cs,
    List<GUInt32> h,
    List<GUInt32> m,
    int t,
    bool f,
  ) {
    assert(h.length == 8);
    assert(m.length == 16);
    final List<GUInt32> v = [];
    v.addAll(h);
    v.add(GUInt32.constant(0x6A09E667));
    v.add(GUInt32.constant(0xBB67AE85));
    v.add(GUInt32.constant(0x3C6EF372));
    v.add(GUInt32.constant(0xA54FF53A));
    v.add(GUInt32.constant(0x510E527F));
    v.add(GUInt32.constant(0x9B05688C));
    v.add(GUInt32.constant(0x1F83D9AB));
    v.add(GUInt32.constant(0x5BE0CD19));
    // t low / high
    v[12] = v[12].xor(cs, GUInt32.constant(t));

    v[13] = v[13].xor(cs, GUInt32.constant(t >> 32));

    if (f) {
      v[14] = v[14].xor(cs, GUInt32.constant(BinaryOps.maxUint32));
    }
    // Rounds
    {
      var me = MultiEq(cs);

      for (var i = 0; i < 10; i++) {
        final s = _sigma[i % 10];

        _mixingG(me, v, (0, 4, 8, 12), m[s[0]], m[s[1]]);
        _mixingG(me, v, (1, 5, 9, 13), m[s[2]], m[s[3]]);
        _mixingG(me, v, (2, 6, 10, 14), m[s[4]], m[s[5]]);
        _mixingG(me, v, (3, 7, 11, 15), m[s[6]], m[s[7]]);
        _mixingG(me, v, (0, 5, 10, 15), m[s[8]], m[s[9]]);
        _mixingG(me, v, (1, 6, 11, 12), m[s[10]], m[s[11]]);
        _mixingG(me, v, (2, 7, 8, 13), m[s[12]], m[s[13]]);
        _mixingG(me, v, (3, 4, 9, 14), m[s[14]], m[s[15]]);
      }

      me.close();
    }
    for (var i = 0; i < 8; i++) {
      h[i] = h[i].xor(cs, v[i]);
      h[i] = h[i].xor(cs, v[i + 8]);
    }
  }

  static List<GBoolean> blake2s(BellmanConstraintSystem cs,
      List<GBoolean> input, List<int> personalization) {
    if (input.length % 8 != 0) {
      throw ArgumentException.invalidOperationArguments("blake2s",
          reason: "Invalid blake2s input length.");
    }
    if (personalization.length != 8) {
      throw ArgumentException.invalidOperationArguments("blake2s",
          reason: "Invalid personalization bytes length.");
    }

    final List<GUInt32> h = [
      GUInt32.constant(0x6A09E667 ^ 0x01010000 ^ 32),
      GUInt32.constant(0xBB67AE85),
      GUInt32.constant(0x3C6EF372),
      GUInt32.constant(0xA54FF53A),
      GUInt32.constant(0x510E527F),
      GUInt32.constant(0x9B05688C),
      GUInt32.constant(0x1F83D9AB ^ BinaryOps.readUint32LE(personalization, 0)),
      GUInt32.constant(0x5BE0CD19 ^ BinaryOps.readUint32LE(personalization, 4)),
    ];

    final List<List<GUInt32>> blocks = [];

    // Convert input bits into message blocks
    for (var i = 0; i < input.length; i += 512) {
      final block =
          input.sublist(i, (i + 512 <= input.length) ? i + 512 : input.length);
      final List<GUInt32> thisBlock = [];
      for (var j = 0; j < block.length; j += 32) {
        final tmp = <GBoolean>[];
        tmp.addAll(
            block.sublist(j, (j + 32 <= block.length) ? j + 32 : block.length));
        while (tmp.length < 32) {
          tmp.add(GBooleanConstant(false));
        }
        thisBlock.add(GUInt32.fromBits(tmp));
      }
      while (thisBlock.length < 16) {
        thisBlock.add(GUInt32.constant(0));
      }
      blocks.add(thisBlock);
    }
    // Ensure at least one block
    if (blocks.isEmpty) {
      blocks.add(List<GUInt32>.generate(16, (_) => GUInt32.constant(0)));
    }
    for (var i = 0; i < blocks.length - 1; i++) {
      _blake2sCompression(cs, h, blocks[i], i + 1 * 64, false);
    }
    _blake2sCompression(cs, h, blocks.last, input.length ~/ 8, true);
    final List<GBoolean> out = [];
    for (final word in h) {
      out.addAll(word.intoBits());
    }
    return out;
  }
}
