import 'package:blockchain_utils/blockchain_utils.dart';

class PcztConstants {
  static const List<int> magicBytes = [80, 67, 90, 84];
  static const int pcztVersion = 1;
  static const int flagTransparentInputsModifiable = 1;
  static const int notFlagTransparentInputsModifiable = 1 ^ BinaryOps.mask8;
  static const int flagTransparentOutputsModifiable = 2;
  static const int notFlagTransparentOutputsModifiable = 2 ^ BinaryOps.mask8;
  static const int flagShieldedModifiable = 128;
  static const int initialTxModifiable = 131;
  static const int orchardSpendsAndOutputsEnabled = 3;
  static const int flagHasSighashSingle = 4;
}
