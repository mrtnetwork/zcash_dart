import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/zcash.dart';

//
class OrchardVerifyProofInputs with LayoutSerializable, CborTagSerializable {
  final List<int> proofBytes;
  final List<OrchardCircuitInstance> instances;
  const OrchardVerifyProofInputs({
    required this.proofBytes,
    required this.instances,
  });
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.vecU8(property: "proof"),
      LayoutConst.vec(
        LayoutConst.array(LayoutConst.fixedBlob32(), 9),
        property: "instances",
      ),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {
      "proof": proofBytes,
      "instances": instances.map((e) => e.instances()).toList(),
    };
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.orchardVerifyProofInputs;

  @override
  List<CborObject?> get serializationItems => [
    CborBytesValue(proofBytes),
    CborTagSerializable.listFromDynamic(
      instances
          .map(
            (e) => CborTagSerializable.listFromDynamic(
              e.instances().map((e) => CborBytesValue(e)).toList(),
            ),
          )
          .toList(),
    ),
  ];
}

// abstract mixin class BaseOrchardVerifier {
//   FutureOr<bool> verifyOrchardProof(OrchardVerifyProofInputs args);
// }

class OrchardProofInputs with LayoutSerializable, CborTagSerializable {
  final OrchardTransfableCircuit circuit;
  final OrchardCircuitInstance instance;
  const OrchardProofInputs({required this.circuit, required this.instance});
  static Layout<Map<String, dynamic>> layout({String? property}) =>
      OrchardTransfableCircuit.layout(property: property);
  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return circuit.toSerializeJson(instances: instance.instances());
  }

  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.orchardProofInputs;

  @override
  List<CborObject?> get serializationItems => [
    CborBytesValue(circuit.fvk.toBytes()),
    CborBytesValue(circuit.note.recipient.toBytes()),
    CborSafeIntValue(circuit.note.value.value),
    CborBytesValue(circuit.note.rho.toBytes()),
    CborBytesValue(circuit.note.rseed.inner),
    circuit.merklePath.position.position.toCbor(),
    CborTagSerializable.listFromDynamic(
      circuit.merklePath.authPath
          .map((e) => CborBytesValue(e.toBytes()))
          .toList(),
    ),
    CborBytesValue(circuit.outputNote.recipient.toBytes()),
    CborSafeIntValue(circuit.outputNote.value.value),
    CborBytesValue(circuit.outputNote.rho.toBytes()),
    CborBytesValue(circuit.outputNote.rseed.inner),
    CborBytesValue(circuit.alpha),
    CborBytesValue(circuit.rcv.toBytes()),
    CborTagSerializable.listFromDynamic(
      instance.instances().map((e) => CborBytesValue(e)).toList(),
    ),
  ];
}

class OrchardProofParams with LayoutSerializable, CborTagSerializable {
  final List<OrchardProofInputs> args;
  const OrchardProofParams(this.args);
  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.vec(OrchardProofInputs.layout(), property: "args"),
    ], property: property);
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson() {
    return {"args": args.map((e) => e.toSerializeJson()).toList()};
  }

  @override
  @override
  SerializationIdentifier get serializationIdentifier =>
      ZcashSerializationIdentifier.orchardProofParams;

  @override
  List<CborObject?> get serializationItems => [
    CborTagSerializable.listFromDynamic(args.map((e) => e.toCbor()).toList()),
  ];
}

class OrchardCircuitInstance {
  final OrchardAnchor anchor;
  final OrchardValueCommitment valueCommitment;
  final OrchardNullifier nullifier;
  final RedPallasSpendPublicKey rk;
  final OrchardExtractedNoteCommitment cmx;
  final bool enableSpend;
  final bool enableOutput;
  final bool disableCrossAddress;
  final OrchardProtocolVersion version;
  const OrchardCircuitInstance({
    required this.anchor,
    required this.valueCommitment,
    required this.nullifier,
    required this.rk,
    required this.cmx,
    required this.enableSpend,
    required this.enableOutput,
    required this.disableCrossAddress,
    required this.version,
  });

  Map<String, dynamic> toJson() {
    return {
      "anchor": anchor.toBytes().toHex(),
      "valueCommitment": valueCommitment.toBytes().toHex(),
      "nullifier": nullifier.toBytes().toHex(),
      "rk": rk.toBytes().toHex(),
      "cmx": cmx.toBytes().toHex(),
      "enableSpend": enableSpend,
      "enableOutput": enableOutput,
      "disableCrossAddress": disableCrossAddress,
      "version": version.name,
    };
  }

  List<List<BuBytes>> toHalo2() {
    return [instances()];
  }

  /// Public-input limbs as raw 32-byte LE encodings (bytes in, bytes out;
  /// point decompression stays internal): anchor | cv.x | cv.y | nullifier |
  /// rk.x | rk.y | cmx | enableSpend | enableOutput | disableCrossAddress.
  /// Identity commitments encode as zero limbs.
  List<BuBytes> instances() {
    final cv = PallasAffinePoint.fromBytes(valueCommitment.toBytes());
    final rk = PallasAffinePoint.fromBytes(this.rk.toBytes());
    BuBytes flag(bool v) {
      final b = BuBytes.zero(32);
      if (v) b[0] = 1;
      return b;
    }

    final cvX = cv.isIdentity() ? BuBytes.zero(32) : cv.x.toBytes();
    final cvY = cv.isIdentity() ? BuBytes.zero(32) : cv.y.toBytes();
    return [
      anchor.inner.toBytes(),
      cvX,
      cvY,
      nullifier.toBytes(),
      rk.x.toBytes(),
      rk.y.toBytes(),
      cmx.inner.toBytes(),
      flag(enableSpend),
      flag(enableOutput),
      flag(disableCrossAddress),
    ];
  }
}

class OrchardTransfableCircuit with LayoutSerializable {
  final OrchardFullViewingKey fvk;
  final OrchardCommitIvkRandomness rivk;
  final OrchardNote note;

  final OrchardNoteCommitment noteCommitment;
  final OrchardMerklePath merklePath;
  final OrchardNote outputNote;
  final BuBytes alpha;
  final OrchardValueCommitTrapdoor rcv;

  OrchardTransfableCircuit({
    required this.fvk,
    required this.note,
    required this.noteCommitment,
    required this.merklePath,
    required this.outputNote,
    required this.alpha,
    required this.rcv,
    required this.rivk,
  });
  factory OrchardTransfableCircuit.fromActionContext({
    required OrchardSpendInfo spend,
    required OrchardNote outputNote,
    required List<int> alpha,
    required OrchardValueCommitTrapdoor rcv,
    required ZcashCryptoContext context,
  }) {
    if (!BytesUtils.bytesEqual(
      spend.note.nullifier(fvk: spend.fvk, context: context).inner,
      outputNote.rho.inner,
    )) {
      throw BuError(
        DefaultErrorType.badPrivateKey,
        "Invalid spend full view key.",
      );
    }
    final Bip44Changes scope = spend.getScope(context);
    return OrchardTransfableCircuit(
      fvk: spend.fvk,
      noteCommitment: spend.note.commitment(context),
      note: spend.note,
      merklePath: spend.merklePath,
      outputNote: outputNote,
      rivk: spend.fvk.rivkFromScope(scope),
      alpha: BuBytes.from(alpha),
      rcv: rcv,
    );
  }

  static Layout<Map<String, dynamic>> layout({String? property}) {
    return LayoutConst.struct([
      LayoutConst.fixedBlobN(96, property: "fvk"),
      LayoutConst.fixedBlobN(43, property: "recipient"),
      LayoutConst.u64(property: "value"),
      LayoutConst.fixedBlob32(property: "rho"),
      LayoutConst.fixedBlob32(property: "rseed"),
      LayoutConst.u32(property: "position"),
      LayoutConst.array(LayoutConst.fixedBlob32(), 32, property: "auth_path"),

      ///
      LayoutConst.fixedBlobN(43, property: "out_recipient"),
      LayoutConst.u64(property: "out_value"),
      LayoutConst.fixedBlob32(property: "out_rho"),
      LayoutConst.fixedBlob32(property: "out_rseed"),
      LayoutConst.fixedBlob32(property: "alpha"),
      LayoutConst.fixedBlob32(property: "rcv"),
      LayoutConst.array(LayoutConst.fixedBlob32(), 9, property: "instances"),
    ], property: property);
  }

  @override
  Map<String, dynamic> toSerializeJson({List<List<int>> instances = const []}) {
    if (instances.length != 9) {
      throw BuError(
        DefaultErrorType.invalidArgument,
        "Missing orchard transfable instances.",
      );
    }
    return {
      "fvk": fvk.toBytes(),
      "recipient": note.recipient.toBytes(),
      "value": note.value.value,
      "rho": note.rho.toBytes(),
      "rseed": note.rseed.inner,
      "position": merklePath.position.position,
      "auth_path": merklePath.authPath.map((e) => e.toBytes()).toList(),
      "out_recipient": outputNote.recipient.toBytes(),
      "out_value": outputNote.value.value,
      "out_rho": outputNote.rho.toBytes(),
      "out_rseed": outputNote.rseed.inner,
      "alpha": alpha,
      "rcv": rcv.toBytes(),
      "instances": instances.map((e) => e.toList()).toList(),
    };
  }

  @override
  Layout<Map<String, dynamic>> toLayout({String? property}) {
    return layout(property: property);
  }
}
