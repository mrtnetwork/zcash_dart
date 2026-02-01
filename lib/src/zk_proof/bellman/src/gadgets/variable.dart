import 'package:blockchain_utils/blockchain_utils.dart';

sealed class GIndex with Equality {
  abstract final int input;
  const GIndex();
}

class GIndexInput extends GIndex {
  @override
  final int input;
  const GIndexInput(this.input);
  @override
  String toString() {
    return "Input($input)";
  }

  @override
  List<dynamic> get variables => [input];
}

class GIndexAux extends GIndex {
  @override
  final int input;
  const GIndexAux(this.input);
  @override
  String toString() {
    return "Aux($input)";
  }

  @override
  List<dynamic> get variables => [input];
}

class GVariable with Equality {
  final GIndex index;
  const GVariable(this.index);
  bool isInput() {
    return switch (index) {
      final GIndexInput _ => true,
      _ => false,
    };
  }

  int get input => index.input;
  @override
  String toString() {
    return "GVariable($index)";
  }

  @override
  List<dynamic> get variables => [index];
}
