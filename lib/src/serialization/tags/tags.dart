import 'package:blockchain_utils/encoding/encoding.dart';

enum ZcashSerializationIdentifier implements SerializationIdentifier {
  zcashPluginError(id: 23001),
  zcashAddressError(id: 23002),
  blockScannerError(id: 23003),
  cryptoError(id: 23004),
  merkleError(id: 23005),
  noteError(id: 23006),
  orchardError(id: 23007),
  pcztError(id: 23008),
  walletdError(id: 23010),
  saplingError(id: 23011),
  transactionError(id: 23012),
  transactionSerializationError(id: 23013),
  transparentError(id: 23014),
  zklibError(id: 23017),
  orchardBuilderError(id: 23018),
  orchardPcztError(id: 23019),
  saplingBuilderError(id: 23020),
  saplingPcztError(id: 23021),
  merkleMergeError(id: 23022),
  merkleFrontierError(id: 23023),
  merkleWitnessError(id: 23024),
  merkleInsertionError(id: 23025),
  serializableTreeCheckpoint(id: 23026),
  retention(id: 23027),
  prunalbeTree(id: 23028),
  locatedPrunalbeTree(id: 23029),
  nodeAddress(id: 23030),
  blockCommitment(id: 23032),
  serialzableTreeShard(id: 23033),
  serialzableTree(id: 23034),
  chainMerkleState(id: 23035),
  serializableTreeInsertReport(id: 23036),
  serializableTreeCheckpointPosition(id: 23037),
  serializableMerkleInsertReport(id: 23038),
  nonEmptyFrontier(id: 23039),
  frontier(id: 23040),
  chainState(id: 23041),
  nullifier(id: 23042),
  scanedBlockNullifiers(id: 23043),
  scanedBlockNullifier(id: 23044),
  merkleBuilderError(id: 23045),
  scannedProtocolBundles(id: 23046),
  subtreeHashes(id: 23047),
  scannedBlockBundles(id: 23048),
  nativeMerkleState(id: 23064),

  ///
  zkRequest(id: 23035),
  saplingSpendParams(id: 23049),
  saplingOutputParams(id: 23050),
  saplingVerifyProofParams(id: 23051),
  orchardProofInputs(id: 23052),
  orchardProofParams(id: 23053),
  orchardVerifyProofInputs(id: 23054),
  scannedBlocksBundles(id: 23055),
  zkResponse(id: 23056),
  createWitnessParams(id: 23057),
  serializableMerklePath(id: 23058),
  serializableWitnesses(id: 23059),
  zkCommitmentShortDomain(id: 23060),
  zkCommitmentDomain(id: 23061),
  zkPseudoRando(id: 23062),
  zkPedersenHash(id: 23063);

  @override
  final int id;
  const ZcashSerializationIdentifier({required this.id});

  @override
  bool isValid(int? tag) {
    return tag == id;
  }
}
