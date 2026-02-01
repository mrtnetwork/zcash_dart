import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:blockchain_utils/crypto/crypto/crypto.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/orchard/constants/constants.dart';

sealed class OrchardFixedBases {
  PallasAffineNativePoint generator();
  List<List<BigInt>> u();
  List<int> z();
  int get numWindows => 85;
  List<List<PallasNativeFp>> lagrangeCoeffs() {
    return Halo2Utils.computeLagrangeCoeffs(generator(), numWindows);
  }
}

enum OrchardFixedBasesFull implements OrchardFixedBases {
  commitIvkR,
  noteCommitR,
  valueCommitR,
  spendAuthG;

  @override
  PallasAffineNativePoint generator() {
    switch (this) {
      case spendAuthG:
        return PallasAffineNativePoint(
            x: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardSpendAuthGConst.base.$1)),
            y: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardSpendAuthGConst.base.$2)));
      case noteCommitR:
        return PallasAffineNativePoint(
            x: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardNoteCommitConst.base.$1)),
            y: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardNoteCommitConst.base.$2)));
      case valueCommitR:
        return PallasAffineNativePoint(
            x: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardValueCommitRConst.base.$1)),
            y: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardValueCommitRConst.base.$2)));
      case commitIvkR:
        return PallasAffineNativePoint(
            x: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardCommitIVKConst.base.$1)),
            y: PallasNativeFp.nP(
                BigInt.parse(HaloOrchardCommitIVKConst.base.$2)));
    }
  }

  @override
  int get numWindows => 85;

  @override
  List<int> z() {
    switch (this) {
      case spendAuthG:
        return HaloOrchardSpendAuthGConst.Z;
      case noteCommitR:
        return HaloOrchardNoteCommitConst.Z;
      case valueCommitR:
        return HaloOrchardValueCommitRConst.Z;
      case commitIvkR:
        return HaloOrchardCommitIVKConst.Z;
    }
  }

  @override
  List<List<PallasNativeFp>> lagrangeCoeffs() {
    return Halo2Utils.computeLagrangeCoeffs(generator(), numWindows);
  }

  @override
  List<List<BigInt>> u() {
    final items = () {
      switch (this) {
        case spendAuthG:
          return HaloOrchardSpendAuthGConst.u;
        case noteCommitR:
          return HaloOrchardNoteCommitConst.u;
        case valueCommitR:
          return HaloOrchardValueCommitRConst.u;
        case commitIvkR:
          return HaloOrchardCommitIVKConst.u;
      }
    }();
    return items.map((e) => e.map((e) => BigInt.parse(e)).toList()).toList();
  }
}

class OrchardFixedBasesNullifierK extends OrchardFixedBases {
  @override
  PallasAffineNativePoint generator() {
    return PallasAffineNativePoint(
        x: PallasNativeFp.nP(BigInt.parse(HaloOrchardNullifierKConst.base.$1)),
        y: PallasNativeFp.nP(BigInt.parse(HaloOrchardNullifierKConst.base.$2)));
  }

  @override
  List<List<BigInt>> u() {
    return HaloOrchardNullifierKConst.u
        .map((e) => e.map((e) => BigInt.parse(e)).toList())
        .toList();
  }

  @override
  List<int> z() {
    return HaloOrchardNullifierKConst.Z;
  }
}

class OrchardFixedBasesValueCommitV extends OrchardFixedBases {
  @override
  int get numWindows => 22;

  @override
  PallasAffineNativePoint generator() {
    return PallasAffineNativePoint(
        x: PallasNativeFp.nP(
            BigInt.parse(HaloOrchardValueCommitVConst.base.$1)),
        y: PallasNativeFp.nP(
            BigInt.parse(HaloOrchardValueCommitVConst.base.$2)));
  }

  @override
  List<List<BigInt>> u() {
    return HaloOrchardValueCommitVConst.u
        .map((e) => e.map((e) => BigInt.parse(e)).toList())
        .toList();
  }

  @override
  List<int> z() {
    return HaloOrchardValueCommitVConst.Z;
  }
}
