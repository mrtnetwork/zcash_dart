import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';
import 'constraint.dart';

class ExpressionSelector extends Expression {
  final Selector selector;
  const ExpressionSelector(this.selector);
  factory ExpressionSelector.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ExpressionSelector(Selector.deserialize(decode.getBytes(2)));
  }

  @override
  int degree() {
    return 1;
  }

  @override
  ExpressionTypes get type => ExpressionTypes.selector;
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.message(2),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [type.value, selector];

  @override
  List<dynamic> get variables => [selector];

  @override
  String toDebugString() {
    return 'Selector(Selector(${selector.offset}, ${selector.isSimple}))';
  }
}

class ExpressionQuery with Equality {
  final int index;
  final int columnIndex;
  final Rotation rotation;
  ExpressionQuery(
      {required this.index, required this.columnIndex, required this.rotation});

  static List<ProtoFieldConfig> get bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.int32(2),
        ProtoFieldConfig.int32(3),
        ProtoFieldConfig.int32(4),
      ];

  @override
  List<dynamic> get variables => [index, columnIndex, rotation];
}

class ExpressionFixedQuery extends Expression {
  final ExpressionQuery query;
  const ExpressionFixedQuery(this.query);
  factory ExpressionFixedQuery.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(
        bytes, ExpressionQuery.bufferFields);
    return ExpressionFixedQuery(ExpressionQuery(
        index: decode.getInt(2),
        columnIndex: decode.getInt(3),
        rotation: Rotation(decode.getInt(4))));
  }

  @override
  int degree() {
    return 1;
  }

  @override
  String toDebugString() {
    return 'Fixed { query_index: ${query.index}, column_index: ${query.columnIndex}, rotation: ${query.rotation.toDebugString()} }';
  }

  @override
  ExpressionTypes get type => ExpressionTypes.fixed;

  @override
  List<ProtoFieldConfig> get bufferFields => ExpressionQuery.bufferFields;

  @override
  List<Object?> get bufferValues =>
      [type.value, query.index, query.columnIndex, query.rotation.location];

  @override
  List<dynamic> get variables => [query];
}

class ExpressionAdviceQuery extends Expression {
  final ExpressionQuery query;
  const ExpressionAdviceQuery(this.query);
  factory ExpressionAdviceQuery.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(
        bytes, ExpressionQuery.bufferFields);
    return ExpressionAdviceQuery(ExpressionQuery(
        index: decode.getInt(2),
        columnIndex: decode.getInt(3),
        rotation: Rotation(decode.getInt(4))));
  }

  @override
  int degree() {
    return 1;
  }

  @override
  String toDebugString() =>
      'Advice { query_index: ${query.index}, column_index: ${query.columnIndex}, rotation: ${query.rotation.toDebugString()} }';

  @override
  List<ProtoFieldConfig> get bufferFields => ExpressionQuery.bufferFields;

  @override
  List<Object?> get bufferValues =>
      [type.value, query.index, query.columnIndex, query.rotation.location];
  @override
  ExpressionTypes get type => ExpressionTypes.advice;

  @override
  List<dynamic> get variables => [query];
}

class ExpressionInstanceQuery extends Expression {
  final ExpressionQuery query;
  const ExpressionInstanceQuery(this.query);
  factory ExpressionInstanceQuery.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(
        bytes, ExpressionQuery.bufferFields);
    return ExpressionInstanceQuery(ExpressionQuery(
        index: decode.getInt(2),
        columnIndex: decode.getInt(3),
        rotation: Rotation(decode.getInt(4))));
  }

  @override
  int degree() {
    return 1;
  }

  @override
  String toDebugString() =>
      'Instance { query_index: ${query.index}, column_index: ${query.columnIndex}, rotation: ${query.rotation.toDebugString()} }';

  @override
  ExpressionTypes get type => ExpressionTypes.instance;

  @override
  List<ProtoFieldConfig> get bufferFields => ExpressionQuery.bufferFields;

  @override
  List<Object?> get bufferValues =>
      [type.value, query.index, query.columnIndex, query.rotation.location];

  @override
  List<dynamic> get variables => [query];
}

enum ExpressionTypes {
  constant(1),
  negated(2),
  sum(3),
  product(4),
  scaled(6),
  fixed(7),
  advice(8),
  instance(9),
  selector(10);

  final int value;
  const ExpressionTypes(this.value);
  static ExpressionTypes fromValue(int? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () =>
          throw ItemNotFoundException(value: value, name: "ExpressionTypes"),
    );
  }
}

sealed class Expression with Equality, ProtobufEncodableMessage {
  const Expression();
  factory Expression.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(
        bytes, [ProtoFieldConfig.int32(1)]);
    final type = ExpressionTypes.fromValue(decode.getInt(1));
    return switch (type) {
      ExpressionTypes.selector => ExpressionSelector.deserialize(bytes),
      ExpressionTypes.advice => ExpressionAdviceQuery.deserialize(bytes),
      ExpressionTypes.instance => ExpressionInstanceQuery.deserialize(bytes),
      ExpressionTypes.fixed => ExpressionFixedQuery.deserialize(bytes),
      ExpressionTypes.sum => ExpressionSum.deserialize(bytes),
      ExpressionTypes.negated => ExpressionNegated.deserialize(bytes),
      ExpressionTypes.product => ExpressionProduct.deserialize(bytes),
      ExpressionTypes.scaled => ExpressionScaled.deserialize(bytes),
      ExpressionTypes.constant => ExpressionConstant.deserialize(bytes),
    };
  }
  ExpressionTypes get type;
  String toDebugString();

  int degree();
  T evaluate<T>({
    required T Function(PallasNativeFp) constant,
    required T Function(Selector) selectorColumn,
    required T Function(ExpressionQuery) fixedColumn,
    required T Function(ExpressionQuery) adviceColumn,
    required T Function(ExpressionQuery) instanceColumn,
    required T Function(T) negated,
    required T Function(T, T) sum,
    required T Function(T, T) product,
    required T Function(T, PallasNativeFp) scaled,
  }) {
    switch (this) {
      case ExpressionConstant(:final inner):
        return constant(inner);

      case ExpressionSelector(:final selector):
        return selectorColumn(selector);

      case ExpressionFixedQuery(:final query):
        return fixedColumn(query);

      case ExpressionAdviceQuery(:final query):
        return adviceColumn(query);

      case ExpressionInstanceQuery(:final query):
        return instanceColumn(query);

      case ExpressionNegated(:final poly):
        final av = poly.evaluate(
            constant: constant,
            selectorColumn: selectorColumn,
            fixedColumn: fixedColumn,
            adviceColumn: adviceColumn,
            instanceColumn: instanceColumn,
            negated: negated,
            sum: sum,
            product: product,
            scaled: scaled);
        return negated(av);

      case ExpressionSum(a: final a, b: final b):
        final av = a.evaluate(
          constant: constant,
          selectorColumn: selectorColumn,
          fixedColumn: fixedColumn,
          adviceColumn: adviceColumn,
          instanceColumn: instanceColumn,
          negated: negated,
          sum: sum,
          product: product,
          scaled: scaled,
        );
        final bv = b.evaluate(
          constant: constant,
          selectorColumn: selectorColumn,
          fixedColumn: fixedColumn,
          adviceColumn: adviceColumn,
          instanceColumn: instanceColumn,
          negated: negated,
          sum: sum,
          product: product,
          scaled: scaled,
        );
        return sum(av, bv);

      case ExpressionProduct(a: final a, b: final b):
        final av = a.evaluate(
          constant: constant,
          selectorColumn: selectorColumn,
          fixedColumn: fixedColumn,
          adviceColumn: adviceColumn,
          instanceColumn: instanceColumn,
          negated: negated,
          sum: sum,
          product: product,
          scaled: scaled,
        );
        final bv = b.evaluate(
          constant: constant,
          selectorColumn: selectorColumn,
          fixedColumn: fixedColumn,
          adviceColumn: adviceColumn,
          instanceColumn: instanceColumn,
          negated: negated,
          sum: sum,
          product: product,
          scaled: scaled,
        );
        return product(av, bv);

      case ExpressionScaled(poly: final poly, b: final b):
        final av = poly.evaluate(
          constant: constant,
          selectorColumn: selectorColumn,
          fixedColumn: fixedColumn,
          adviceColumn: adviceColumn,
          instanceColumn: instanceColumn,
          negated: negated,
          sum: sum,
          product: product,
          scaled: scaled,
        );
        return scaled(av, b);
    }
  }

  /// Returns whether or not this expression contains a simple `Selector`.
  bool containsSimpleSelector() {
    return evaluate<bool>(
        constant: (_) => false,
        selectorColumn: (selector) => selector.isSimple,
        fixedColumn: (_) => false,
        adviceColumn: (_) => false,
        instanceColumn: (_) => false,
        negated: (a) => a,
        sum: (a, b) => a || b,
        product: (a, b) => a || b,
        scaled: (a, _) => a);
  }

  /// Extracts a simple selector from this gate, if present
  Selector? extractSimpleSelector() {
    Selector? op(Selector? a, Selector? b) {
      if (a != null && b == null) return a;
      if (a == null && b != null) return b;
      if (a != null && b != null) {
        throw Halo2Exception.operationFailed("extractSimpleSelector",
            reason: "Two simple selectors cannot be in the same expression.");
      }
      return null;
    }

    return evaluate<Selector?>(
        constant: (_) => null,
        selectorColumn: (selector) {
          if (selector.isSimple) {
            return selector;
          } else {
            return null;
          }
        },
        fixedColumn: (_) => null,
        adviceColumn: (_) => null,
        instanceColumn: (_) => null,
        negated: (a) => a,
        sum: op,
        product: op,
        scaled: (a, _) => a);
  }

  /// Unary negation
  Expression operator -() {
    return ExpressionNegated(this);
  }

  /// Addition
  Expression operator +(Expression rhs) {
    if (containsSimpleSelector() || rhs.containsSimpleSelector()) {
      throw Halo2Exception.operationFailed("addition",
          reason: "Attempted to use a simple selector in an addition.");
    }
    return ExpressionSum(a: this, b: rhs);
  }

  /// Subtraction
  Expression operator -(Expression rhs) {
    if (containsSimpleSelector() || rhs.containsSimpleSelector()) {
      throw Halo2Exception.operationFailed("subtraction",
          reason: "Attempted to use a simple selector in an subtraction.");
    }
    return ExpressionSum(a: this, b: -rhs);
  }

  Expression operator *(Object other) {
    return switch (other) {
      final Expression other => () {
          if (containsSimpleSelector() && other.containsSimpleSelector()) {
            throw Halo2Exception.operationFailed("subtraction",
                reason:
                    "Attempted to multiply two expressions containing simple selectors.");
          }
          // ExpressionScaled()
          return ExpressionProduct(a: this, b: other);
        }(),
      final PallasNativeFp f => ExpressionScaled(poly: this, b: f),
      _ => throw Halo2Exception.operationFailed("Multiplication",
          reason: "Unsupported object.")
    };
  }

  /// Scaling (Expression * Field)
  Expression scale(PallasNativeFp rhs) {
    return ExpressionScaled(poly: this, b: rhs);
  }

  Expression square() => this * this;
}

class ExpressionConstant extends Expression {
  final PallasNativeFp inner;
  const ExpressionConstant(this.inner);
  factory ExpressionConstant.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ExpressionConstant(PallasNativeFp.fromBytes(decode.getBytes(2)));
  }

  @override
  int degree() {
    return 0;
  }

  @override
  String toDebugString() {
    return "Constant(${BytesUtils.toHexString(inner.toBytes().reversed.toList(), prefix: "0x")})";
  }

  @override
  ExpressionTypes get type => ExpressionTypes.constant;
  static List<ProtoFieldConfig> get _bufferFields =>
      [ProtoFieldConfig.int32(1), ProtoFieldConfig.bytes(2)];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [type.value, inner.toBytes()];

  @override
  List<dynamic> get variables => [inner];
}

class ExpressionNegated extends Expression {
  final Expression poly;
  const ExpressionNegated(this.poly);
  factory ExpressionNegated.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ExpressionNegated(Expression.deserialize(decode.getBytes(2)));
  }

  @override
  int degree() {
    return poly.degree();
  }

  @override
  String toDebugString() => 'Negated(${poly.toDebugString()})';

  @override
  ExpressionTypes get type => ExpressionTypes.negated;
  static List<ProtoFieldConfig> get _bufferFields =>
      [ProtoFieldConfig.int32(1), ProtoFieldConfig.message(2)];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [type.value, poly];

  @override
  List<dynamic> get variables => [poly];
}

class ExpressionSum extends Expression {
  final Expression a;
  final Expression b;
  const ExpressionSum({required this.a, required this.b});
  factory ExpressionSum.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ExpressionSum(
        a: Expression.deserialize(decode.getBytes(2)),
        b: Expression.deserialize(decode.getBytes(3)));
  }

  @override
  int degree() {
    return IntUtils.max(a.degree(), b.degree());
  }

  @override
  String toDebugString() => 'Sum(${a.toDebugString()}, ${b.toDebugString()})';

  @override
  ExpressionTypes get type => ExpressionTypes.sum;
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.message(2),
        ProtoFieldConfig.message(3)
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [type.value, a, b];

  @override
  List<dynamic> get variables => [a, b];
}

class ExpressionProduct extends Expression {
  final Expression a;
  final Expression b;
  const ExpressionProduct({required this.a, required this.b});
  factory ExpressionProduct.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ExpressionProduct(
        a: Expression.deserialize(decode.getBytes(2)),
        b: Expression.deserialize(decode.getBytes(3)));
  }

  @override
  int degree() {
    return a.degree() + b.degree();
  }

  @override
  String toDebugString() =>
      'Product(${a.toDebugString()}, ${b.toDebugString()})';

  @override
  ExpressionTypes get type => ExpressionTypes.product;
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.message(2),
        ProtoFieldConfig.message(3)
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [type.value, a, b];

  @override
  List<dynamic> get variables => [a, b];
}

class ExpressionScaled extends Expression {
  final Expression poly;
  final PallasNativeFp b;
  const ExpressionScaled({required this.poly, required this.b});
  factory ExpressionScaled.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ExpressionScaled(
        poly: Expression.deserialize(decode.getBytes(2)),
        b: PallasNativeFp.fromBytes(decode.getBytes(3)));
  }

  @override
  int degree() {
    return poly.degree();
  }

  @override
  String toDebugString() =>
      'Scaled(${poly.toDebugString()}, ${BytesUtils.toHexString(b.toBytes().reversed.toList(), prefix: "0x")})';

  @override
  ExpressionTypes get type => ExpressionTypes.scaled;
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.message(2),
        ProtoFieldConfig.bytes(3)
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [type.value, poly, b.toBytes()];

  @override
  List<dynamic> get variables => [poly, b];
}
