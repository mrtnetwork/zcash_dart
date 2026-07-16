use std::{collections::BTreeMap, ops::Range, vec::IntoIter};

use crate::{
    error::{Error, RuntimeError, ZKError},
    merkle::types::{
        BlocksBundles, ChainMerkleState, ChainState, CreateWitnessParams, OrchardShardStore,
        SaplingShardStore, ScannedProtocolBundles, SerializableLocatedPrunableTree,
        SerializableMerkleInsertReport, SerializableShardTree, SerializableTreeCheckpointPosition,
        SerializableTreeInsertReport, SerializableWitnesses, ShieldProtocol, SubtreeRoots,
        WitnessTree, NOTE_COMMITMENT_TREE_DEPTH, SHARD_HEIGHT, SHARD_HEIGHT_LEVEL,
    },
    sapling::node::SaplingNode,
};
use incrementalmerkletree::{frontier::Frontier, Address, Marking, Position, Retention};
use orchard::tree::MerkleHashOrchard;
use shardtree::{
    store::{Checkpoint, ShardStore},
    BatchInsertionResult, LocatedPrunableTree, ShardTree,
};

pub struct MerkleContext {
    pub sapling: ShardTree<SaplingShardStore, { NOTE_COMMITMENT_TREE_DEPTH }, SHARD_HEIGHT>,
    pub orchard: ShardTree<OrchardShardStore, { NOTE_COMMITMENT_TREE_DEPTH }, SHARD_HEIGHT>,
    pub chain_state: Option<ChainState>,
}

impl MerkleContext {
    pub fn deserialize(state: ChainMerkleState) -> ZKError<Self> {
        let sapling: ShardTree<SaplingShardStore, NOTE_COMMITMENT_TREE_DEPTH, SHARD_HEIGHT> =
            (&state.sapling).try_into()?;
        let orchard: ShardTree<OrchardShardStore, NOTE_COMMITMENT_TREE_DEPTH, SHARD_HEIGHT> =
            (&state.orchard).try_into()?;
        Ok(MerkleContext {
            sapling,
            orchard,
            chain_state: None,
        })
    }

    pub fn create_witness(
        &mut self,
        params: CreateWitnessParams,
    ) -> ZKError<SerializableWitnesses> {
        let protocol: ShieldProtocol = params.protocol.try_into()?;
        match protocol {
            ShieldProtocol::Sapling => ShardTree::<
                SaplingShardStore,
                NOTE_COMMITMENT_TREE_DEPTH,
                SHARD_HEIGHT,
            >::create_witness_for_tree(
                &mut self.sapling, params
            ),
            ShieldProtocol::Orchard => ShardTree::<
                OrchardShardStore,
                NOTE_COMMITMENT_TREE_DEPTH,
                SHARD_HEIGHT,
            >::create_witness_for_tree(
                &mut self.orchard, params
            ),
        }
    }
    pub fn get_context(&self) -> ZKError<ChainMerkleState> {
        Ok(ChainMerkleState {
            sapling: SerializableShardTree::try_from(&self.sapling)?,
            orchard: SerializableShardTree::try_from(&self.orchard)?,
            orchard_subtree_index: 0,
            sapling_subtree_index: 0,
        })
    }

    pub fn merge_state(&mut self, state: SerializableMerkleInsertReport) -> ZKError<()> {
        self.insert_chain_state(&state.chain_state)?;

        let sapling_checkpoints = match state.sapling.as_ref() {
            Some(sapling) => {
                let s = LocatedPrunableTree::<SaplingNode>::try_from(&sapling.subtree)?;
                let checkpoints: BTreeMap<u32, Position> = sapling
                    .checkpoints
                    .clone()
                    .into_iter()
                    .map(|cp| (cp.checkpoint, cp.position.into()))
                    .collect();
                self.sapling
                    .insert_tree(s, checkpoints.clone())
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })?;
                Some(checkpoints)
            }
            None => None,
        };
        let orchard_checkpoints = match state.orchard.as_ref() {
            Some(orchard) => {
                let s = LocatedPrunableTree::<MerkleHashOrchard>::try_from(&orchard.subtree)?;
                let checkpoints: BTreeMap<u32, Position> = orchard
                    .checkpoints
                    .clone()
                    .into_iter()
                    .map(|cp| (cp.checkpoint, cp.position.into()))
                    .collect();
                self.orchard
                    .insert_tree(s, checkpoints.clone())
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })?;
                Some(checkpoints)
            }
            None => None,
        };
        let empty = BTreeMap::new();

        let sapling_existing = sapling_checkpoints.as_ref().unwrap_or(&empty);
        let orchard_existing = orchard_checkpoints.as_ref().unwrap_or(&empty);
        let chain_state = state.chain_state;
        let sapling_frontier: Frontier<SaplingNode, 32> = chain_state
            .final_sapling_tree
            .map(|e| e.try_into())
            .transpose()?
            .unwrap_or_else(Frontier::empty);
        let orchard_frontier: Frontier<MerkleHashOrchard, NOTE_COMMITMENT_TREE_DEPTH> = chain_state
            .final_orchard_tree
            .map(|e| e.try_into())
            .transpose()?
            .unwrap_or_else(Frontier::empty);

        let sapling_missing = MerkleContext::ensure_checkpoints(
            orchard_existing.keys(),
            sapling_existing,
            &sapling_frontier,
        );

        let orchard_missing = MerkleContext::ensure_checkpoints(
            sapling_existing.keys(),
            orchard_existing,
            &orchard_frontier,
        );
        let min_sapling_height = self
            .sapling
            .store()
            .max_checkpoint_id()
            .map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?
            .unwrap_or(0);

        for (height, checkpoint) in sapling_missing {
            if height > min_sapling_height {
                self.sapling
                    .store_mut()
                    .add_checkpoint(height, checkpoint)
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })?;
            }
        }
        let min_orchard_height = self
            .orchard
            .store()
            .max_checkpoint_id()
            .map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?
            .unwrap_or(0);
        for (height, checkpoint) in orchard_missing {
            if height > min_orchard_height {
                self.orchard
                    .store_mut()
                    .add_checkpoint(height, checkpoint)
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })?;
            }
        }
        Ok(())
    }

    pub fn update_state(
        &mut self,
        blocks: BlocksBundles,
    ) -> ZKError<SerializableMerkleInsertReport> {
        let orchard_final_tree_size: u32 = blocks.bundles.last().unwrap().orchard.final_tree_size;
        let sapling_final_tree_size: u32 = blocks.bundles.last().unwrap().sapling.final_tree_size;
        let (sapling_bundles, orchard_bundles): (
            Vec<ScannedProtocolBundles>,
            Vec<ScannedProtocolBundles>,
        ) = blocks
            .bundles
            .into_iter()
            .map(|e| (e.sapling, e.orchard))
            .unzip();
        let update_sapling = self.update_sapling_state(sapling_bundles)?;
        let update_orchard = self.update_orchard_state(orchard_bundles)?;
        let chain_state = self.chain_state.as_ref().ok_or(RuntimeError {
            code: Error::MerkleError,
            msg: "Missing chain state".to_string(),
        })?;
        let sapling_checkpoints = match update_sapling {
            Some(sapling) => {
                let g = SerializableLocatedPrunableTree::try_from(&sapling.subtree)?;
                let i = SerializableTreeInsertReport {
                    subtree: g,
                    checkpoints: sapling
                        .checkpoints
                        .iter()
                        .map(
                            |(checkpoint, position)| SerializableTreeCheckpointPosition {
                                checkpoint: (*checkpoint).into(),
                                position: (*position).into(),
                            },
                        )
                        .collect::<Vec<SerializableTreeCheckpointPosition>>(),
                };
                let checkpoints = sapling.checkpoints.clone();
                let result = self
                    .sapling
                    .insert_tree(sapling.subtree, sapling.checkpoints);
                result
                    .map(|_| Some((i, checkpoints)))
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })
            }
            None => Ok(None),
        }?;

        let orchard_checkpoints = match update_orchard {
            Some(orchard) => {
                let g = SerializableLocatedPrunableTree::try_from(&orchard.subtree)?;
                let i = SerializableTreeInsertReport {
                    subtree: g,
                    checkpoints: orchard
                        .checkpoints
                        .iter()
                        .map(
                            |(checkpoint, position)| SerializableTreeCheckpointPosition {
                                checkpoint: (*checkpoint).into(),
                                position: (*position).into(),
                            },
                        )
                        .collect::<Vec<SerializableTreeCheckpointPosition>>(),
                };
                let checkpoints = orchard.checkpoints.clone();
                let result = self
                    .orchard
                    .insert_tree(orchard.subtree, orchard.checkpoints);
                result
                    .map(|_| Some((i, checkpoints)))
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })
            }
            None => Ok(None),
        }?;
        let empty = BTreeMap::new();

        // let sapling_existing = sapling_checkpoints.as_ref().unwrap_or(&empty);
        let sapling_existing = sapling_checkpoints
            .as_ref()
            .map(|(_, checkpoints)| checkpoints)
            .unwrap_or(&empty);
        let orchard_existing = orchard_checkpoints
            .as_ref()
            .map(|(_, checkpoints)| checkpoints)
            .unwrap_or(&empty);
        let sapling_frontier: Frontier<SaplingNode, NOTE_COMMITMENT_TREE_DEPTH> = chain_state
            .final_sapling_tree
            .as_ref()
            .map(|t| t.try_into())
            .transpose()?
            .unwrap_or_else(Frontier::empty);
        let orchard_frontier: Frontier<MerkleHashOrchard, NOTE_COMMITMENT_TREE_DEPTH> = chain_state
            .final_orchard_tree
            .as_ref()
            .map(|t| t.try_into())
            .transpose()?
            .unwrap_or_else(Frontier::empty);

        let sapling_missing = MerkleContext::ensure_checkpoints(
            orchard_existing.keys(),
            sapling_existing,
            &sapling_frontier,
        );

        let orchard_missing = MerkleContext::ensure_checkpoints(
            sapling_existing.keys(),
            orchard_existing,
            &orchard_frontier,
        );
        let min_sapling_height = self
            .sapling
            .store()
            .max_checkpoint_id()
            .map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?
            .unwrap_or(0);

        for (height, checkpoint) in sapling_missing {
            if height > min_sapling_height {
                self.sapling
                    .store_mut()
                    .add_checkpoint(height, checkpoint)
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })?;
            }
        }
        let min_orchard_height = self
            .orchard
            .store()
            .max_checkpoint_id()
            .map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?
            .unwrap_or(0);
        for (height, checkpoint) in orchard_missing {
            if height > min_orchard_height {
                self.orchard
                    .store_mut()
                    .add_checkpoint(height, checkpoint)
                    .map_err(|e| RuntimeError {
                        code: Error::MerkleError,
                        msg: e.to_string(),
                    })?;
            }
        }

        Ok(SerializableMerkleInsertReport {
            height: blocks.start_height,
            chain_state: chain_state.clone(),
            final_orchard_tree: orchard_final_tree_size,
            final_sapling_tree: sapling_final_tree_size,

            orchard: orchard_checkpoints.map(|(orchard, _)| orchard),
            sapling: sapling_checkpoints.map(|(sapling, _)| sapling),
        })
    }
    pub fn insert_chain_state(&mut self, chain_state: &ChainState) -> ZKError<()> {
        // SAPLING
        let sapling_frontier: Frontier<SaplingNode, NOTE_COMMITMENT_TREE_DEPTH> = chain_state
            .final_sapling_tree
            .as_ref()
            .map(|f| f.try_into())
            .transpose()?
            .unwrap_or_else(Frontier::empty);

        self.sapling
            .insert_frontier(
                sapling_frontier,
                Retention::Checkpoint {
                    id: chain_state.block_height,
                    marking: Marking::Reference,
                },
            )
            .map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?;

        // ORCHARD
        let orchard_frontier: Frontier<MerkleHashOrchard, NOTE_COMMITMENT_TREE_DEPTH> = chain_state
            .final_orchard_tree
            .as_ref()
            .map(|f| f.try_into())
            .transpose()?
            .unwrap_or_else(Frontier::empty);

        self.orchard
            .insert_frontier(
                orchard_frontier,
                Retention::Checkpoint {
                    id: chain_state.block_height,
                    marking: Marking::Reference,
                },
            )
            .map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?;
        self.chain_state = Some(chain_state.clone());

        Ok(())
    }
    pub fn update_sapling_subtree(&mut self, hashes: SubtreeRoots) -> ZKError<u32> {
        let subtrees: Vec<SaplingNode> = (&hashes).try_into()?;
        let mut index = hashes.start;

        for hash in subtrees {
            let addr = Address::from_parts(SHARD_HEIGHT_LEVEL, index.into());
            self.sapling.insert(addr, hash).map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?;

            index += 1;
        }
        Ok(index)
    }

    pub fn update_orchard_subtree(&mut self, hashes: SubtreeRoots) -> ZKError<u32> {
        let subtrees: Vec<MerkleHashOrchard> = (&hashes).try_into()?;
        let mut index = hashes.start;

        for hash in subtrees {
            let addr = Address::from_parts(SHARD_HEIGHT_LEVEL, index.into());
            self.orchard.insert(addr, hash).map_err(|e| RuntimeError {
                code: Error::MerkleError,
                msg: e.to_string(),
            })?;

            index += 1;
        }
        Ok(index)
    }

    pub fn update_sapling_state(
        &mut self,
        bundles: Vec<ScannedProtocolBundles>,
    ) -> ZKError<
        Option<BatchInsertionResult<SaplingNode, u32, IntoIter<(SaplingNode, Retention<u32>)>>>,
    > {
        let first = match bundles.first() {
            Some(v) => v,
            None => return Ok(None),
        };

        let start: u64 = first
            .final_tree_size
            .checked_sub(
                first
                    .commitment
                    .len()
                    .try_into()
                    .map_err(|_| RuntimeError {
                        code: Error::MerkleError,
                        msg: "Invalid tree size.".to_string(),
                    })?,
            )
            .ok_or(RuntimeError {
                code: Error::MerkleError,
                msg: "Invalid tree size.".to_string(),
            })?
            .into();
        let end: u64 = bundles.last().unwrap().final_tree_size.into();

        let range = Range {
            start: start.into(),
            end: end.into(),
        };

        let values = ScannedProtocolBundles::into_iter_all::<SaplingNode>(bundles)?;

        let result = LocatedPrunableTree::from_iter(range, SHARD_HEIGHT_LEVEL, values);

        Ok(result)
    }

    pub fn update_orchard_state(
        &mut self,
        bundles: Vec<ScannedProtocolBundles>,
    ) -> ZKError<
        Option<
            BatchInsertionResult<
                MerkleHashOrchard,
                u32,
                IntoIter<(MerkleHashOrchard, Retention<u32>)>,
            >,
        >,
    > {
        let first = match bundles.first() {
            Some(v) => v,
            None => return Ok(None),
        };

        let start: u64 = first
            .final_tree_size
            .checked_sub(
                first
                    .commitment
                    .len()
                    .try_into()
                    .map_err(|_| RuntimeError {
                        code: Error::MerkleError,
                        msg: "Invalid tree size.".to_string(),
                    })?,
            )
            .ok_or(RuntimeError {
                code: Error::MerkleError,
                msg: "Invalid tree size.".to_string(),
            })?
            .into();
        let end: u64 = bundles.last().unwrap().final_tree_size.into();

        let range = Range {
            start: start.into(),
            end: end.into(),
        };

        let values = ScannedProtocolBundles::into_iter_all::<MerkleHashOrchard>(bundles)?;

        let result = LocatedPrunableTree::from_iter(range, SHARD_HEIGHT_LEVEL, values);

        Ok(result)
    }

    fn ensure_checkpoints<'a, H, I: Iterator<Item = &'a u32>>(
        // An iterator of checkpoints heights for which we wish to ensure that
        // checkpoints exists.
        ensure_heights: I,
        // The map of checkpoint positions from which we will draw note commitment tree
        // position information for the newly created checkpoints.
        existing_checkpoint_positions: &BTreeMap<u32, Position>,
        // The frontier whose position will be used for an inserted checkpoint when
        // there is no preceding checkpoint in existing_checkpoint_positions.
        state_final_tree: &Frontier<H, NOTE_COMMITMENT_TREE_DEPTH>,
    ) -> Vec<(u32, Checkpoint)> {
        ensure_heights
            .flat_map(|ensure_height| {
                existing_checkpoint_positions
                    .range::<u32, _>(..=*ensure_height)
                    .last()
                    .map_or_else(
                        || {
                            Some((
                                *ensure_height,
                                state_final_tree
                                    .value()
                                    .map_or_else(Checkpoint::tree_empty, |t| {
                                        Checkpoint::at_position(t.position())
                                    }),
                            ))
                        },
                        |(existing_checkpoint_height, position)| {
                            if *existing_checkpoint_height < *ensure_height {
                                Some((*ensure_height, Checkpoint::at_position(*position)))
                            } else {
                                // The checkpoint already exists, so we don't need to
                                // do anything.
                                None
                            }
                        },
                    )
                    .into_iter()
            })
            .collect::<Vec<_>>()
    }
}
