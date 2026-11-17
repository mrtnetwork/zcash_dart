import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/sapling/sapling.dart';
import 'package:zcash_dart/src/serialization/tags/tags.dart';

class SaplingVerifyInputs with LayoutSerializable, CborTagSerializable {
  final GrothProofBytes proof;
  final List<JubJubFq> inputs;
  SaplingVerifyInputs._({required this.proof, required List<JubJubFq> inputs})
    : inputs = inputs.immutable;
  factory SaplingVerifyInputs({
    required GrothProofBytes proof,
    required List<JubJubFq> inputs,
  }) {
    if (inputs.length != 5 && inputs.length != 7) {
      throw BuError(
        DefaultErrorType.invalidLength,
        "Invalid sapling proof public inputs length.",
      );
    }
    return SaplingVerifyInputs._(proof: proof, inputs: inputs);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return LayoutConst.struct([
      GrothProofBytes.layout(property: "proof"),
      LayoutConst.array(
        LayoutConst.fixedBlob32(),
        inputs.length,
        property: "inputs",
      ),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "proof": proof.toSerializeJson(),
      "inputs": inputs.map((e) => e.toBytes()).toList(),
    };
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.saplingVerifyProofParams;

  @override
  List<CborObject?> get serializationItems => [
    CborBytesValue(proof.inner),
    CborTagSerializable.listFromDynamic(
      inputs.map((e) => CborBytesValue(e.toBytes())).toList(),
    ),
  ];
}
