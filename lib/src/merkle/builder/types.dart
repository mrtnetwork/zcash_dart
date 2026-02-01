import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:zcash_dart/src/block_processor/src/types.dart';
import 'package:zcash_dart/src/merkle/types/types.dart';
import 'package:zcash_dart/src/orchard/orchard.dart';
import 'package:zcash_dart/src/sapling/merkle/merkle.dart';

class ScannedOutputWithMerkle<OUTPUT extends ScannedOutput,
    MERKLE extends MerklePath> {
  final OUTPUT output;
  final MERKLE merklePath;
  const ScannedOutputWithMerkle(
      {required this.output, required this.merklePath});
}

class BuildMerleOutput {
  final List<ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
      orchardNotes;
  final List<ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
      saplingNotes;
  final OrchardAnchor orchardAnchor;
  final SaplingAnchor saplingAnchor;
  BuildMerleOutput({
    required List<
            ScannedOutputWithMerkle<OrchardScannedOutput, OrchardMerklePath>>
        orchardNotes,
    required List<
            ScannedOutputWithMerkle<SaplingScannedOutput, SaplingMerklePath>>
        saplingNotes,
    required this.orchardAnchor,
    required this.saplingAnchor,
  })  : orchardNotes = orchardNotes.immutable,
        saplingNotes = saplingNotes.immutable;
}
