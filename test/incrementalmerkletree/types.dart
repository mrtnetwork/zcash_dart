import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';

class SerialzableString extends MerkleNodeValue {
  final String value;
  const SerialzableString(this.value);

  @override
  List<dynamic> get variables => [value];

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return LayoutConst.struct([LayoutConst.bcsString(property: "value")]);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"value": value};
  }

  @override
  BuBytes toBytes() {
    throw UnimplementedError();
  }
}

extension TOSERIALIZABLE on String {
  SerialzableString toSerializable() => SerialzableString(this);
}

class StringHashable extends Hashable<SerialzableString> {
  static SerialzableString fromU64(int value) {
    if (value < 0) {
      throw ArgumentError('value must be non-negative');
    }

    // 'a' Unicode code point is 97
    final codePoint = 'a'.codeUnitAt(0) + value;

    // Same assumption as Rust: value stays in a valid range
    return SerialzableString(String.fromCharCode(codePoint));
  }

  SerialzableString root(List<SerialzableString> inputLeaves, int depth) {
    final emptyLeaf = this.emptyLeaf();

    // Pad leaves with empty_leaf up to 2^depth
    final targetSize = 1 << depth;
    final leaves = <SerialzableString>[
      ...inputLeaves,
      ...List<SerialzableString>.filled(
        (targetSize - inputLeaves.length).clamp(0, targetSize),
        emptyLeaf,
      ),
    ];

    var currentLeaves = List<SerialzableString>.from(leaves);
    var level = TreeLevel.zero;

    while (currentLeaves.length != 1) {
      final next = <SerialzableString>[];

      for (int i = 0; i < currentLeaves.length; i += 2) {
        final left = currentLeaves[i];
        final right = currentLeaves[i + 1];
        next.add(combine(level: level, a: left, b: right));
      }

      currentLeaves = next;
      level = level + 1;
    }

    return currentLeaves.first;
  }

  SerialzableString combineAll(int depth, List<int> values) {
    return root(values.map((e) => fromU64(e)).toList(), depth);
  }

  @override
  SerialzableString combine({
    required TreeLevel level,
    required SerialzableString a,
    required SerialzableString b,
  }) {
    return SerialzableString(a.value + b.value);
  }

  @override
  SerialzableString emptyLeaf() {
    return SerialzableString("_");
  }
}

final hashable = StringHashable();

PrunableTree<SerialzableString> leaf(
  SerialzableString value,
  RetentionFlags flags,
) {
  return PrunableTree(
    node: NodeLeaf(value: PrunableValue(value: value, flags: flags)),
    hashContext: hashable,
  );
}

PrunableTree<SerialzableString> nil() {
  return PrunableTree(node: NodeNil(), hashContext: hashable);
}

PrunableTree<SerialzableString> parent({
  required PrunableTree<SerialzableString> left,
  required PrunableTree<SerialzableString> right,
  SerialzableString? ann,
}) {
  return PrunableTree(
    node: NodeParent(ann: ann, left: left, right: right),
    hashContext: hashable,
  );
}

typedef Generator<T> = T Function();
RetentionFlags randomRetentionFlags() {
  final values = <RetentionFlags>[
    RetentionFlags.ephemeral,
    RetentionFlags.checkpoint,
    RetentionFlags.marked,
    RetentionFlags.checkpoint | RetentionFlags.marked,
  ];

  return values[QuickCrypto.generateRandomInt(values.length)];
}

PrunableTree<SerialzableString> arbTree<H extends Object>({
  required int depth,
  required int size,
}) {
  SerialzableString generateRandomString(
    int length, {
    String charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
  }) {
    final characters = List.generate(
      length,
      (_) => charset[QuickCrypto.prng.nextInt(charset.length)],
    );
    return SerialzableString(characters.join());
  }

  PrunableTree<SerialzableString> gen(int currentDepth) {
    // Base case
    if (currentDepth <= 0 || size <= 0) {
      if (QuickCrypto.generateRandoomBool()) {
        return PrunableTree(node: NodeNil(), hashContext: hashable);
      } else {
        return PrunableTree(
          node: NodeLeaf(
            value: PrunableValue(
              value: generateRandomString(QuickCrypto.generateRandomInt(16)),
              flags: randomRetentionFlags(),
            ),
          ),
          hashContext: hashable,
        );
      }
    }

    // Recursive case
    final left = gen(currentDepth - 1);
    final right = gen(currentDepth - 1);
    if (left.node.isNil() && right.node.isNil()) {
      return PrunableTree<SerialzableString>.empty(hashable);
    }

    return PrunableTree.parent(
      left: left,
      right: right,
      ann:
          QuickCrypto.generateRandoomBool()
              ? QuickCrypto.generateRandomString(
                QuickCrypto.generateRandomInt(16),
              ).toSerializable()
              : null,
    );
  }

  return gen(depth);
}
