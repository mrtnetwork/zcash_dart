import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/poly.dart';

enum ColumnTypeNames {
  advice(0),
  fixed(1),
  instance(2),
  anyInstance(3),
  anyAdvice(4),
  anyFixed(5);

  const ColumnTypeNames(this.value);
  final int value;
  static ColumnTypeNames froValue(int? v) {
    return values.firstWhere((e) => e.value == v,
        orElse: () =>
            throw ItemNotFoundException(value: v, name: "ColumnTypeNames"));
  }
}

sealed class ColumnType with Equality {
  ColumnTypeNames get name;
  const ColumnType();
  String toDebugString();
  @override
  List<dynamic> get variables => [name];
  Any toAny();

  T cast<T extends ColumnType>() {
    if (this is T) return this as T;
    throw CastFailedException(value: this);
  }
}

class Column<C extends ColumnType>
    with Equality, ProtobufEncodableMessage
    implements Comparable<Column<C>> {
  final int index;
  final C columnType;
  const Column({required this.index, required this.columnType});
  factory Column.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    final int name = decode.getInt(2);
    final type = ColumnTypeNames.froValue(name);
    return Column(
        index: decode.getInt(1),
        columnType: switch (type) {
          ColumnTypeNames.advice => Advice(),
          ColumnTypeNames.instance => Instance(),
          ColumnTypeNames.fixed => Fixed(),
          ColumnTypeNames.anyAdvice => AnyAdvice(),
          ColumnTypeNames.anyInstance => AnyInstance(),
          ColumnTypeNames.anyFixed => AnyFixed()
        }
            .cast<C>());
  }

  String toDebugString() =>
      "Column { index: $index, column_type: ${columnType.toDebugString()} }";

  @override
  List<dynamic> get variables => [index, columnType];

  Column<Any> toAny() {
    return Column(index: index, columnType: columnType.toAny());
  }

  @override
  int compareTo(Column<C> other) {
    final c = columnType.toAny().compareTo(other.columnType.toAny());
    if (c == 0) return index.compareTo(other.index);
    return c;
  }

  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.int32(1),
        ProtoFieldConfig.int32(2),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [index, columnType.name.value];
}

class ColumnWithRotation<C extends ColumnType>
    with Equality, ProtobufEncodableMessage {
  final Column<C> column;
  final Rotation rotation;
  const ColumnWithRotation(this.column, this.rotation);
  factory ColumnWithRotation.deserialize(List<int> bytes) {
    final decode = ProtobufEncodableMessage.deserialize(bytes, _bufferFields);
    return ColumnWithRotation(
        Column<C>.deserialize(decode.getBytes(1)), Rotation(decode.getInt(2)));
  }
  static List<ProtoFieldConfig> get _bufferFields => [
        ProtoFieldConfig.message(1),
        ProtoFieldConfig.int32(2),
      ];
  @override
  List<ProtoFieldConfig> get bufferFields => _bufferFields;

  @override
  List<Object?> get bufferValues => [column, rotation.location];

  String toDebugString() =>
      "(${column.toDebugString()}, ${rotation.toDebugString()})";

  @override
  List<dynamic> get variables => [column, rotation];
}

class TableColumn with Equality implements Comparable<TableColumn> {
  final Column<Fixed> inner;
  const TableColumn(this.inner);

  @override
  List<dynamic> get variables => [inner];

  @override
  int compareTo(TableColumn other) {
    return inner.compareTo(other.inner);
  }
}

class Advice extends ColumnType {
  const Advice._();
  static const _instance = Advice._();
  factory Advice() => _instance;
  @override
  AnyAdvice toAny() => AnyAdvice();

  @override
  String toDebugString() {
    return "Advice";
  }

  @override
  ColumnTypeNames get name => ColumnTypeNames.advice;
}

class Fixed extends ColumnType {
  const Fixed._();
  static const _instance = Fixed._();
  factory Fixed() => _instance;
  @override
  AnyFixed toAny() => AnyFixed();

  @override
  String toDebugString() {
    return "Fixed";
  }

  @override
  ColumnTypeNames get name => ColumnTypeNames.fixed;
}

class Instance extends ColumnType {
  const Instance._();
  static const _instance = Instance._();
  factory Instance() => _instance;
  @override
  AnyInstance toAny() => AnyInstance();

  @override
  String toDebugString() {
    return "Instance";
  }

  @override
  ColumnTypeNames get name => ColumnTypeNames.instance;
}

sealed class Any extends ColumnType implements Comparable<Any> {
  const Any();
  int get rank;

  @override
  int compareTo(Any other) => rank.compareTo(other.rank);
  @override
  Any toAny() {
    return this;
  }
}

class AnyInstance extends Any {
  const AnyInstance._();
  static const _instance = AnyInstance._();
  factory AnyInstance() => _instance;
  @override
  int get rank => 0;

  @override
  String toDebugString() {
    return "Instance";
  }

  @override
  ColumnTypeNames get name => ColumnTypeNames.anyInstance;
}

class AnyAdvice extends Any {
  const AnyAdvice._();
  static const _instance = AnyAdvice._();
  factory AnyAdvice() => _instance;
  @override
  int get rank => 1;

  @override
  String toDebugString() {
    return "Advice";
  }

  @override
  ColumnTypeNames get name => ColumnTypeNames.anyAdvice;
}

class AnyFixed extends Any {
  const AnyFixed._();
  static const _instance = AnyFixed._();
  factory AnyFixed() => _instance;
  @override
  int get rank => 2;

  @override
  String toDebugString() {
    return "Fixed";
  }

  @override
  ColumnTypeNames get name => ColumnTypeNames.anyFixed;
}
