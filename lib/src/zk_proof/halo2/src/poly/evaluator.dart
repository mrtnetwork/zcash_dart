import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/domain.dart';

class Evaluator<B extends Basis> {
  final List<Polynomial<PallasNativeFp, B>> polys;
  Evaluator({List<Polynomial<PallasNativeFp, B>>? polys}) : polys = polys ?? [];

  /// Registers a polynomial and returns an AST leaf for it
  AstLeaf registerPoly(Polynomial<PallasNativeFp, B> poly) {
    final index = polys.length;
    polys.add(poly);
    return AstLeaf(index, Rotation.cur());
  }

  /// Returns the chunk size and number of chunks for a polynomial of length [polyLen].
  (int, int) getChunkParams({required int polyLen, int numThreads = 1}) {
    // AstScale by a constant factor for better load balancing
    final numChunks = numThreads * 4;

    // Ceiling division to calculate chunk size
    final chunkSize = ((polyLen + numChunks - 1) / numChunks).ceil();

    // Recalculate number of chunks from actual chunk size
    final adjustedNumChunks = ((polyLen + chunkSize - 1) / chunkSize).ceil();

    return (chunkSize, adjustedNumChunks);
  }

  static List<PallasNativeFp> runRecurse<B extends Basis>(AstContext<B> ctx) {
    return recurse(ctx.ast, ctx, ctx.ops);
  }

  static List<PallasNativeFp> recurse<B extends Basis>(
      Ast<B> node, AstContext<B> ctx, BasisOps<B> ops) {
    switch (node) {
      case AstPoly<B>(value: final leaf):
        return ops.getChunkOfRotated(
          ctx.domain,
          ctx.chunkSize,
          ctx.chunkIndex,
          ctx.polys[leaf.index],
          leaf.rotation,
        );

      case AstAdd<B>(left: final a, right: final b):
        final lhs = recurse(a, ctx, ops);
        final rhs = recurse(b, ctx, ops);
        for (var i = 0; i < lhs.length; i++) {
          lhs[i] += rhs[i];
        }
        return lhs;
      case AstMul<B>(left: final a, right: final b):
        final lhs = recurse(a, ctx, ops);
        final rhs = recurse(b, ctx, ops);
        for (var i = 0; i < lhs.length; i++) {
          lhs[i] *= rhs[i];
        }
        return lhs;

      case AstScale<B>(node: final a, factor: final scalar):
        final lhs = recurse(a, ctx, ops);
        for (var i = 0; i < lhs.length; i++) {
          lhs[i] *= scalar;
        }
        return lhs;

      case AstDistributePowers<B>(nodes: final terms, factor: final base):
        var acc = ops.constantTerm(
          ctx.polyLen,
          ctx.chunkSize,
          ctx.chunkIndex,
          PallasNativeFp.zero(),
        );
        for (final term in terms) {
          final t = recurse(term, ctx, ops);
          for (var i = 0; i < acc.length; i++) {
            acc[i] = acc[i] * base + t[i];
          }
        }
        return acc;
      case LinearTerm<B>(coefficient: final c):
        return ops.linearTerm(
            ctx.domain, ctx.polyLen, ctx.chunkSize, ctx.chunkIndex, c);

      case AstConstantTerm<B>(value: final v):
        return ops.constantTerm(ctx.polyLen, ctx.chunkSize, ctx.chunkIndex, v);
    }
  }

  List<AstContext> buildContext(
      Ast<B> ast, EvaluationDomain domain, BasisOps<B> ops,
      {int numThreads = 4}) {
    if (polys.isEmpty) {
      throw Halo2Exception.operationFailed("evaluate",
          reason: "No polynomials registered.");
    }

    final polyLen = polys.first.values.length;
    final (chunkSize, _) =
        getChunkParams(polyLen: polyLen, numThreads: numThreads);

    // Compute result polynomial
    List<AstContext> ctxs = [];
    // For simplicity, we process chunks sequentially here
    final numChunks = (polyLen / chunkSize).ceil();
    for (var chunkIndex = 0; chunkIndex < numChunks; chunkIndex++) {
      final ctx = AstContext(
          domain: domain,
          polyLen: polyLen,
          chunkSize: chunkSize,
          chunkIndex: chunkIndex,
          numThreads: numThreads,
          ast: ast,
          ops: ops,
          polys: polys);
      ctxs.add(ctx);
    }
    return ctxs;
  }

  /// Evaluates the given AST in this context
  Polynomial<PallasNativeFp, B> evaluate(
      Ast<B> ast, EvaluationDomain domain, BasisOps<B> ops) {
    if (polys.isEmpty) {
      throw Halo2Exception.operationFailed("evaluate",
          reason: "No polynomials registered.");
    }

    final polyLen = polys.first.values.length;
    final (chunkSize, _) = getChunkParams(polyLen: polyLen, numThreads: 1);

    // Compute result polynomial
    final result = ops.emptyPoly(domain);

    // For simplicity, we process chunks sequentially here
    final numChunks = (polyLen / chunkSize).ceil();
    for (var chunkIndex = 0; chunkIndex < numChunks; chunkIndex++) {
      final ctx = AstContext(
          domain: domain,
          polyLen: polyLen,
          chunkSize: chunkSize,
          chunkIndex: chunkIndex,
          numThreads: 1,
          ast: ast,
          ops: ops,
          polys: polys);
      final chunk = recurse(ast, ctx, ops);
      final start = chunkIndex * chunkSize;
      for (var i = 0; i < chunk.length; i++) {
        result.values[start + i] = chunk[i];
      }
    }
    return result;
  }

  Polynomial<PallasNativeFp, B> combine(
      AstContextResult ctx, EvaluationDomain domain, BasisOps<B> ops) {
    if (polys.isEmpty) {
      throw Halo2Exception.operationFailed("evaluate",
          reason: "No polynomials registered.");
    }

    // final polyLen = polys.first.values.length;
    // final (chunkSize, _) = getChunkParams(polyLen: polyLen, numThreads: 4);

    // Compute result polynomial
    final result = ops.emptyPoly(domain);

    // For simplicity, we process chunks sequentially here
    final numChunks = (ctx.polyLen / ctx.chunkSize).ceil();
    for (var chunkIndex = 0; chunkIndex < numChunks; chunkIndex++) {
      final chunk = ctx.values[chunkIndex];
      final start = chunkIndex * ctx.chunkSize;
      for (var i = 0; i < chunk.length; i++) {
        result.values[start + i] = chunk[i];
      }
    }
    return result;
  }
}

sealed class Ast<B extends Basis> {
  const Ast();

  // Unary negation
  Ast<B> operator -() => AstScale<B>(this, -PallasNativeFp.one());

  // Addition with another AST
  Ast<B> operator +(Object other) {
    return switch (other) {
      Ast<B> r => AstAdd<B>(this, r),
      AstLeaf r => AstAdd<B>(this, AstPoly<B>(r)),
      _ => throw Halo2Exception.operationFailed("Addition",
          reason: "Unsupported object.")
    };
  }

  // Subtraction with another AST
  Ast<B> operator -(Object other) {
    return switch (other) {
      Ast<B> r => this + (-r),
      AstLeaf r => this + (-AstPoly<B>(r)),
      _ => throw Halo2Exception.operationFailed("Subtraction",
          reason: "Unsupported object.")
    };
  }

  // Multiplication with another AST
  Ast<B> operator *(Object other) {
    return switch (other) {
      final Ast<B> rhs => AstMul<B>(this, rhs),
      final AstLeaf rhs => AstMul<B>(this, AstPoly<B>(rhs)),
      final PallasNativeFp rhs => AstScale(this, rhs),
      _ => throw Halo2Exception.operationFailed("Multiplication",
          reason: "Unsupported object.")
    };
  }

  // Multiplication with a scalar
  Ast<B> scale(PallasNativeFp factor) => AstScale<B>(this, factor);
}

class AstLeaf {
  final int index;
  final Rotation rotation;
  const AstLeaf(this.index, this.rotation);
  AstLeaf withRotation(Rotation rotation) {
    return AstLeaf(index, rotation);
  }
}

// Leaf node
class AstPoly<B extends Basis> extends Ast<B> {
  final AstLeaf value;
  const AstPoly(this.value);
}

// Addition node
class AstAdd<B extends Basis> extends Ast<B> {
  final Ast<B> left;
  final Ast<B> right;
  const AstAdd(this.left, this.right);
}

// Multiplication node
class AstMul<B extends Basis> extends Ast<B> {
  final Ast<B> left;
  final Ast<B> right;

  const AstMul(this.left, this.right);
}

// Scaling node
class AstScale<B extends Basis> extends Ast<B> {
  final Ast<B> node;
  final PallasNativeFp factor;
  const AstScale(this.node, this.factor);
}

// Distribute powers node
class AstDistributePowers<B extends Basis> extends Ast<B> {
  final List<Ast<B>> nodes;
  final PallasNativeFp factor;
  const AstDistributePowers(this.nodes, this.factor);
}

// Linear term (degree-1)
class LinearTerm<B extends Basis> extends Ast<B> {
  final PallasNativeFp coefficient;
  const LinearTerm(this.coefficient);
}

class AstConstantTerm<B extends Basis> extends Ast<B> {
  final PallasNativeFp value;
  const AstConstantTerm(this.value);
  factory AstConstantTerm.one() => AstConstantTerm<B>(PallasNativeFp.one());
}

abstract class BasisOps<B extends Basis> implements Basis {
  Polynomial<PallasNativeFp, B> emptyPoly(EvaluationDomain domain);

  List<PallasNativeFp> constantTerm(
      int polyLen, int chunkSize, int chunkIndex, PallasNativeFp scalar);

  List<PallasNativeFp> linearTerm(EvaluationDomain domain, int polyLen,
      int chunkSize, int chunkIndex, PallasNativeFp scalar);

  List<PallasNativeFp> getChunkOfRotated(EvaluationDomain domain, int chunkSize,
      int chunkIndex, Polynomial<PallasNativeFp, B> poly, Rotation rotation);
}

class CoeffOps extends Coeff implements BasisOps<Coeff> {
  @override
  Polynomial<PallasNativeFp, Coeff> emptyPoly(EvaluationDomain domain) =>
      domain.emptyCoeff();

  @override
  List<PallasNativeFp> constantTerm(
      int polyLen, int chunkSize, int chunkIndex, PallasNativeFp scalar) {
    final size = (polyLen - chunkSize * chunkIndex).clamp(0, chunkSize);
    final chunk = List<PallasNativeFp>.filled(size, PallasNativeFp.zero());
    if (chunkIndex == 0 && chunk.isNotEmpty) {
      chunk[0] = scalar;
    }
    return chunk;
  }

  @override
  List<PallasNativeFp> linearTerm(EvaluationDomain domain, int polyLen,
      int chunkSize, int chunkIndex, PallasNativeFp scalar) {
    final size = (polyLen - chunkSize * chunkIndex).clamp(0, chunkSize);
    final chunk = List<PallasNativeFp>.filled(size, PallasNativeFp.zero());

    if (chunkSize == 1 && chunkIndex == 1 && chunk.isNotEmpty) {
      chunk[0] = scalar;
    } else if (chunkIndex == 0 && chunk.length > 1) {
      chunk[1] = scalar;
    }

    return chunk;
  }

  @override
  List<PallasNativeFp> getChunkOfRotated(
          EvaluationDomain domain,
          int chunkSize,
          int chunkIndex,
          Polynomial<PallasNativeFp, Coeff> poly,
          Rotation rotation) =>
      throw Halo2Exception.operationFailed("getChunkOfRotated",
          reason: "Unsupported object.");
}

class LagrangeCoeffOps extends LagrangeCoeff
    implements BasisOps<LagrangeCoeff> {
  @override
  Polynomial<PallasNativeFp, LagrangeCoeff> emptyPoly(
          EvaluationDomain domain) =>
      domain.emptyLagrange();

  @override
  List<PallasNativeFp> constantTerm(
      int polyLen, int chunkSize, int chunkIndex, PallasNativeFp scalar) {
    return List<PallasNativeFp>.filled(
        (polyLen - chunkSize * chunkIndex).clamp(0, chunkSize), scalar);
  }

  @override
  List<PallasNativeFp> linearTerm(EvaluationDomain domain, int polyLen,
      int chunkSize, int chunkIndex, PallasNativeFp scalar) {
    final omega = domain.omega;
    final start = chunkSize * chunkIndex;
    final size = (polyLen - start).clamp(0, chunkSize);

    PallasNativeFp acc = omega.pow(BigInt.from(start)) * scalar;
    final result = <PallasNativeFp>[];
    for (int i = 0; i < size; i++) {
      result.add(acc);
      acc *= omega;
    }
    return result;
  }

  @override
  List<PallasNativeFp> getChunkOfRotated(
          EvaluationDomain domain,
          int chunkSize,
          int chunkIndex,
          Polynomial<PallasNativeFp, LagrangeCoeff> poly,
          Rotation rotation) =>
      poly.getChunkOfRotated(rotation, chunkSize, chunkIndex);
}

class ExtendedLagrangeCoeffOps extends ExtendedLagrangeCoeff
    implements BasisOps<ExtendedLagrangeCoeff> {
  @override
  Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> emptyPoly(
          EvaluationDomain domain) =>
      domain.emptyExtended();

  @override
  List<PallasNativeFp> constantTerm(
          int polyLen, int chunkSize, int chunkIndex, PallasNativeFp scalar) =>
      List<PallasNativeFp>.filled(
          (polyLen - chunkSize * chunkIndex).clamp(0, chunkSize), scalar);

  @override
  List<PallasNativeFp> linearTerm(EvaluationDomain domain, int polyLen,
      int chunkSize, int chunkIndex, PallasNativeFp scalar) {
    final omega = domain.extendedOmega;
    final start = chunkSize * chunkIndex;
    final size = (polyLen - start).clamp(0, chunkSize);

    PallasNativeFp acc =
        omega.pow(BigInt.from(start)) * PallasNativeFp.zeta() * scalar;
    final result = <PallasNativeFp>[];
    for (int i = 0; i < size; i++) {
      result.add(acc);
      acc *= omega;
    }
    return result;
  }

  @override
  List<PallasNativeFp> getChunkOfRotated(
          EvaluationDomain domain,
          int chunkSize,
          int chunkIndex,
          Polynomial<PallasNativeFp, ExtendedLagrangeCoeff> poly,
          Rotation rotation) =>
      domain.getChunkOfRotatedExtended(poly, rotation, chunkSize, chunkIndex);
}

class AstContext<B extends Basis> {
  final EvaluationDomain domain;
  final int polyLen;
  final int chunkSize;
  final int chunkIndex;
  final List<Polynomial<PallasNativeFp, B>> polys;
  final Ast<B> ast;
  final BasisOps<B> ops;
  final int numThreads;
  AstContext(
      {required this.domain,
      required this.polyLen,
      required this.chunkSize,
      required this.chunkIndex,
      required this.polys,
      required this.ast,
      required this.ops,
      required this.numThreads});
  AstChunkInfoContext toInfo() {
    return AstChunkInfoContext(polyLen, chunkIndex, chunkSize);
  }
}

class AstContextResult {
  final int polyLen;
  final int chunkSize;
  final int numThreads;
  final List<List<PallasNativeFp>> values;
  const AstContextResult(
      {required this.polyLen,
      required this.chunkSize,
      required this.numThreads,
      required this.values});
}

class AstChunkInfoContext {
  final int polyLen;
  final int chunkSize;
  final int chunkIndex;
  const AstChunkInfoContext(this.polyLen, this.chunkIndex, this.chunkSize);
  // final List<Polynomial<PallasNativeFp, B>> polys;
  // final Ast<B> ast;
  // final BasisOps<B> ops;
  // AstContext(
  //     {required this.domain,
  //     required this.polyLen,
  //     required this.chunkSize,
  //     required this.chunkIndex,
  //     required this.polys,
  //     required this.ast,
  //     required this.ops});
}
