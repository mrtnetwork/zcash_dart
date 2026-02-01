import 'dart:collection';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/poly/params.dart';

class MSM with Equality {
  final PolyParams params;
  List<PallasNativeFp>? _gScalars;
  PallasNativeFp? _wScalar;
  PallasNativeFp? _uScalar;
  SplayTreeMap<VestaNativeFq, _OtherTerm> _other;
  MSM(this.params) : _other = SplayTreeMap();

  MSM clone() => MSM(params)
    .._gScalars = _gScalars?.clone()
    .._wScalar = _wScalar
    .._uScalar = _uScalar
    .._other = SplayTreeMap.from(_other);

  void addMsm(MSM otherMsm) {
    otherMsm._other.forEach((x, term) {
      _other.update(x, (existing) {
        if (existing.y == term.y) {
          existing.scalar += term.scalar;
        } else {
          assert(existing.y == -term.y);
          existing.scalar -= term.scalar;
        }
        return existing;
      }, ifAbsent: () => _OtherTerm(term.scalar, term.y));
    });
    final g = otherMsm._gScalars;
    if (g != null) {
      addToGScalars(g);
    }
    final w = otherMsm._wScalar;
    if (w != null) {
      addToWScalar(w);
    }
    final u = otherMsm._uScalar;
    if (u != null) {
      addToUScalar(u);
    }
  }

  void appendTerm(PallasNativeFp scalar, VestaAffineNativePoint point) {
    if (point.isIdentity()) return;
    final x = point.x;
    final y = point.y;
    _other.update(x, (existing) {
      if (existing.y == y) {
        existing.scalar += scalar;
      } else {
        assert(existing.y == -y);
        existing.scalar -= scalar;
      }
      return existing;
    }, ifAbsent: () => _OtherTerm(scalar, y));
  }

  void addConstantTerm(PallasNativeFp constant) {
    final g = _gScalars;
    if (g != null) {
      g[0] += constant;
    } else {
      final scalars =
          List<PallasNativeFp>.filled(params.n, PallasNativeFp.zero());
      scalars[0] += constant;
      _gScalars = scalars;
    }
  }

  void addToGScalars(List<PallasNativeFp> scalars) {
    assert(scalars.length == params.n);
    final g = _gScalars;

    if (g != null) {
      for (int i = 0; i < scalars.length; i++) {
        g[i] += scalars[i];
      }
    } else {
      _gScalars = List<PallasNativeFp>.from(scalars);
    }
  }

  void addToWScalar(PallasNativeFp scalar) {
    final w = _wScalar;
    _wScalar = (w == null) ? scalar : w + scalar;
  }

  void addToUScalar(PallasNativeFp scalar) {
    final u = _uScalar;
    _uScalar = (u == null) ? scalar : u + scalar;
  }

  void scale(PallasNativeFp factor) {
    final g = _gScalars;
    if (g != null) {
      for (int i = 0; i < g.length; i++) {
        g[i] *= factor;
      }
    }

    for (final term in _other.values) {
      term.scalar *= factor;
    }
    final w = _wScalar;
    final u = _uScalar;
    if (w != null) _wScalar = w * factor;
    if (u != null) _uScalar = u * factor;
  }

  bool eval() {
    final g = _gScalars;
    final u = _uScalar;
    final w = _wScalar;
    final len = (g?.length ?? 0) +
        (w != null ? 1 : 0) +
        (u != null ? 1 : 0) +
        _other.length;

    final scalars = <PallasNativeFp>[];
    final bases = <VestaAffineNativePoint>[];

    _other.forEach((x, term) {
      scalars.add(term.scalar);
      bases.add(VestaAffineNativePoint(x: x, y: term.y));
    });

    if (w != null) {
      scalars.add(w);
      bases.add(params.w);
    }

    if (u != null) {
      scalars.add(u);
      bases.add(params.u);
    }

    if (g != null) {
      scalars.addAll(g);
      bases.addAll(params.g);
    }
    if (scalars.length == len && bases.length == len) {
      return Halo2Utils.bestMultiexp(scalars, bases).isIdentity();
    }
    return false;
  }

  @override
  List<dynamic> get variables =>
      [params, _gScalars, _uScalar, _wScalar, _other];
}

class _OtherTerm with Equality {
  PallasNativeFp scalar;
  VestaNativeFq y;

  _OtherTerm(this.scalar, this.y);

  @override
  List<dynamic> get variables => [scalar, y];
}
