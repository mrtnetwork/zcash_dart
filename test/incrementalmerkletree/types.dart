import 'package:blockchain_utils/crypto/quick_crypto.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/merkle/tree/prunable.dart';

class StringHashable extends Hashable<String> {
  static String fromU64(int value) {
    if (value < 0) {
      throw ArgumentError('value must be non-negative');
    }

    // 'a' Unicode code point is 97
    final codePoint = 'a'.codeUnitAt(0) + value;

    // Same assumption as Rust: value stays in a valid range
    return String.fromCharCode(codePoint);
  }

  String root(
    List<String> inputLeaves,
    int depth,
  ) {
    final emptyLeaf = this.emptyLeaf();

    // Pad leaves with empty_leaf up to 2^depth
    final targetSize = 1 << depth;
    final leaves = <String>[
      ...inputLeaves,
      ...List<String>.filled(
        (targetSize - inputLeaves.length).clamp(0, targetSize),
        emptyLeaf,
      ),
    ];

    var currentLeaves = List<String>.from(leaves);
    var level = TreeLevel.zero;

    while (currentLeaves.length != 1) {
      final next = <String>[];

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

  String combineAll(int depth, List<int> values) {
    return root(values.map((e) => fromU64(e)).toList(), depth);
  }

  @override
  String combine(
      {required TreeLevel level, required String a, required String b}) {
    return a + b;
  }

  @override
  String emptyLeaf() {
    return "_";
  }
}

final hashable = StringHashable();

PrunableTree<String> leaf(String value, RetentionFlags flags) {
  return PrunableTree(
      node: NodeLeaf(value: PrunableValue(value: value, flags: flags)),
      hashContext: hashable);
}

PrunableTree<String> nil() {
  return PrunableTree(node: NodeNil(), hashContext: hashable);
}

PrunableTree<String> parent(
    {required PrunableTree<String> left,
    required PrunableTree<String> right,
    String? ann}) {
  return PrunableTree(
      node: NodeParent(ann: ann, left: left, right: right),
      hashContext: hashable);
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

PrunableTree<String> arbTree<H extends Object>({
  required int depth,
  required int size,
}) {
  String generateRandomString(
    int length, {
    String charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
  }) {
    final characters = List.generate(
      length,
      (_) => charset[QuickCrypto.prng.nextInt(charset.length)],
    );
    return characters.join();
  }

  PrunableTree<String> gen(int currentDepth) {
    // Base case
    if (currentDepth <= 0 || size <= 0) {
      if (QuickCrypto.generateRandoomBool()) {
        return PrunableTree(node: NodeNil(), hashContext: hashable);
      } else {
        return PrunableTree(
            node: NodeLeaf(
                value: PrunableValue(
                    value:
                        generateRandomString(QuickCrypto.generateRandomInt(16)),
                    flags: randomRetentionFlags())),
            hashContext: hashable);
      }
    }

    // Recursive case
    final left = gen(currentDepth - 1);
    final right = gen(currentDepth - 1);
    if (left.node.isNil() && right.node.isNil()) {
      return PrunableTree<String>.empty(hashable);
    }

    return PrunableTree.parent(
        left: left,
        right: right,
        ann: QuickCrypto.generateRandoomBool()
            ? QuickCrypto.generateRandomString(
                QuickCrypto.generateRandomInt(16))
            : null);
  }

  return gen(depth);
}
