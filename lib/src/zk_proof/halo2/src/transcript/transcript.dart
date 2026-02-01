import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/exception/exception.dart';

abstract class Halo2Transcript {
  Halo2Transcript();
  BLAKE2b _state = BLAKE2b(
      config: Blake2bConfig(personalization: "Halo2-Transcript".codeUnits));

  PallasNativeFp squeezeChallenge() {
    _state.update([0]);
    final hasher = _state.clone();
    return PallasNativeFp.fromBytes64(hasher.digest());
  }

  void commonPoint(VestaAffineNativePoint point) {
    _state.update([1]);
    if (point.isIdentity()) {
      throw Halo2Exception.operationFailed("commonPoint",
          reason: "Identity point not allowed.");
    }
    _state.update(point.x.toBytes());
    _state.update(point.y.toBytes());
  }

  void commonScalar(PallasNativeFp scalar) {
    _state.update([2]);
    _state.update(scalar.toBytes());
  }

  void cleanState() {
    _state = BLAKE2b(
        config: Blake2bConfig(personalization: "Halo2-Transcript".codeUnits));
  }
}

class Halo2TranscriptRead extends Halo2Transcript {
  final List<int> bytes;
  int _offset = 0;

  Halo2TranscriptRead(this.bytes);

  List<int> _read32() {
    final end = _offset + 32;
    assert(end <= bytes.length);
    final data = bytes.sublist(_offset, end);
    _offset += 32;
    return data;
  }

  VestaAffineNativePoint readPoint() {
    final point = VestaAffineNativePoint.fromBytes(_read32());
    commonPoint(point);
    return point;
  }

  PallasNativeFp readScalar() {
    final scalar = PallasNativeFp.fromBytes(_read32());
    commonScalar(scalar);
    return scalar;
  }

  List<PallasNativeFp> readNScalars(int n) =>
      List.generate(n, (i) => readScalar());
  List<VestaAffineNativePoint> readNPoint(int n) =>
      List.generate(n, (i) => readPoint());
}

class Halo2TranscriptWriter extends Halo2Transcript {
  final List<int> _buffer = List.empty(growable: true);
  Halo2TranscriptWriter();
  void writePoint(VestaAffineNativePoint point) {
    commonPoint(point);
    _buffer.addAll(point.toBytes());
  }

  void writeScalar(PallasNativeFp scalar) {
    commonScalar(scalar);
    _buffer.addAll(scalar.toBytes());
  }

  List<int> buffer() => _buffer;
  List<int> toBytes() => _buffer.clone();
}
