import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/exception/exception.dart';

class MerkleTreeException extends DartZCashPluginException {
  const MerkleTreeException(super.message, {super.details});

  static MerkleTreeException failed(String name,
      {String? reason, Map<String, dynamic>? details}) {
    return MerkleTreeException("Merkle operation failed during $name",
        details: {"reason": reason, ...details ?? {}}.notNullValue);
  }
}
