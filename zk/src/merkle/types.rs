use crate::{
    error::{enc_err, input_err, internal_err, Error, RuntimeError, ZKError},
    sapling::node::SaplingNode,
};

use incrementalmerkletree::{
    frontier::Frontier, Address, Hashable, Level, Marking, MerklePath, Position, Retention,
};

use minicbor::{bytes::ByteArray, Decode, Encode};
use orchard::tree::MerkleHashOrchard;
use shardtree::{
    store::{memory::MemoryShardStore, Checkpoint, ShardStore},
    LocatedPrunableTree, LocatedTree, Node, PrunableTree, RetentionFlags, ShardTree, Tree,
};
use std::sync::Arc;

pub const NOTE_COMMITMENT_TREE_DEPTH: u8 = 32;
pub const SHARD_HEIGHT: u8 = NOTE_COMMITMENT_TREE_DEPTH / 2;
pub const SHARD_HEIGHT_LEVEL: Level = Level::new(SHARD_HEIGHT);
pub const MAX_CHECKPOINTS: usize = 100;
pub type OrchardShardStore = MemoryShardStore<orchard::tree::MerkleHashOrchard, u32>;
pub type SaplingShardStore = MemoryShardStore<SaplingNode, u32>;

fn decode_node<T: MerkleCodec>(bytes: [u8; 32], field: &'static str) -> ZKError<T> {
    T::from_bytes(bytes).map_err(|_| enc_err(field, "invalid 32-byte encoding"))
}

#[repr(u8)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum ShieldProtocol {
    Sapling = 0,
    Orchard = 1,
}
impl TryFrom<u8> for ShieldProtocol {
    type Error = RuntimeError;

    fn try_from(value: u8) -> ZKError<Self> {
        match value {
            1 => Ok(Self::Orchard),
            0 => Ok(Self::Sapling),
            _ => Err(input_err(
                "shield_protocol",
                "invalid value (expected 0 or 1)",
            )),
        }
    }
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23027))]
#[cbor(array)]
pub enum RetentionRepr {
    #[n(0)]
    Ephemeral,

    #[n(1)]
    Checkpoint {
        #[n(0)]
        id: u32,
        #[n(1)]
        marking: u8,
    },

    #[n(2)]
    Marked,

    #[n(3)]
    Reference,
}
impl RetentionRepr {
    pub fn to_retention(&self) -> ZKError<Retention<u32>> {
        Ok(match self {
            RetentionRepr::Ephemeral => Retention::Ephemeral,
            RetentionRepr::Checkpoint { id, marking } => Retention::Checkpoint {
                id: *id,
                marking: match marking {
                    0 => Marking::Marked,
                    1 => Marking::Reference,
                    2 => Marking::None,
                    _ => return Err(input_err("retention_marking", "invalid marking value")),
                },
            },
            RetentionRepr::Marked => Retention::Marked,
            RetentionRepr::Reference => Retention::Reference,
        })
    }
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23032))]
#[cbor(array)]
pub struct BlockCommitment {
    #[n(0)]
    pub node: ByteArray<32>,
    #[n(1)]
    pub retention: RetentionRepr,
}

impl BlockCommitment {
    pub fn to_retention(&self) -> ZKError<Retention<u32>> {
        self.retention.to_retention()
    }
}
impl<T> TryFrom<BlockCommitment> for (T, Retention<u32>)
where
    T: MerkleCodec,
{
    type Error = RuntimeError;

    fn try_from(value: BlockCommitment) -> ZKError<Self> {
        let node = decode_node::<T>(value.node.into(), "block_commitment_node")?;
        let retention = value.to_retention()?;
        Ok((node, retention))
    }
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23046))]
#[cbor(array)]
pub struct ScannedProtocolBundles {
    #[n(0)]
    pub final_tree_size: u32,
    #[n(1)]
    pub commitment: Vec<BlockCommitment>,
}
impl ScannedProtocolBundles {
    pub fn into_iter_all<T>(bundles: Vec<Self>) -> ZKError<std::vec::IntoIter<(T, Retention<u32>)>>
    where
        T: MerkleCodec,
    {
        let mut out = Vec::new();

        for b in bundles {
            let iter = b.into_iter::<T>()?;
            out.extend(iter);
        }

        Ok(out.into_iter())
    }
    pub fn into_iter<T>(self) -> ZKError<impl Iterator<Item = (T, Retention<u32>)>>
    where
        T: MerkleCodec,
    {
        let mut out = Vec::with_capacity(self.commitment.len());

        for c in self.commitment {
            out.push(c.try_into()?);
        }

        Ok(out.into_iter())
    }
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23028))]
#[cbor(array)]
pub enum SerializableNode {
    #[n(0)]
    Parent(
        #[n(0)] Option<ByteArray<32>>,
        #[n(1)] Box<SerializableNode>,
        #[n(2)] Box<SerializableNode>,
    ),
    #[n(1)]
    Leaf(#[n(0)] ByteArray<32>, #[n(1)] u8),
    #[n(2)]
    Nil,
}
impl<H> TryFrom<&Tree<Option<Arc<H>>, (H, RetentionFlags)>> for SerializableNode
where
    H: MerkleCodec + Clone,
{
    type Error = RuntimeError;

    fn try_from(tree: &Tree<Option<Arc<H>>, (H, RetentionFlags)>) -> ZKError<Self> {
        match &**tree {
            Node::Parent { ann, left, right } => {
                let ann_bytes = ann.as_ref().map(|h| ByteArray::from(h.to_bytes()));

                let left_ser = SerializableNode::try_from(left.as_ref()).map(Box::new)?;
                let right_ser = SerializableNode::try_from(right.as_ref()).map(Box::new)?;
                Ok(SerializableNode::Parent(ann_bytes, left_ser, right_ser))
            }
            Node::Leaf { value } => {
                let (h, flag) = value;

                let bytes = ByteArray::from(h.to_bytes());
                Ok(SerializableNode::Leaf(bytes, flag.bits()))
            }

            Node::Nil => Ok(SerializableNode::Nil),
        }
    }
}

impl<H> TryFrom<&SerializableNode> for Tree<Option<Arc<H>>, (H, RetentionFlags)>
where
    H: MerkleCodec + Clone,
{
    type Error = RuntimeError;

    fn try_from(node: &SerializableNode) -> ZKError<Self> {
        match node {
            SerializableNode::Nil => Ok(Tree::empty()),

            SerializableNode::Leaf(bytes, flag) => {
                let h: H = decode_node((*bytes).into(), "leaf_node")?;

                let rf = RetentionFlags::from_bits(*flag)
                    .ok_or_else(|| input_err("leaf_flag", "invalid retention flag"))?;

                Ok(Tree::leaf((h, rf)))
            }

            SerializableNode::Parent(ann, left, right) => {
                let ann = match ann {
                    Some(b) => Some(Arc::new(decode_node((*b).into(), "parent_annotation")?)),
                    None => None,
                };

                let left = Tree::try_from(left.as_ref())?;
                let right = Tree::try_from(right.as_ref())?;

                Ok(Tree::parent(ann, left, right))
            }
        }
    }
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23030))]
#[cbor(array)]
pub struct NodeAddress {
    #[n(0)]
    level: u8,
    #[n(1)]
    index: u64,
}
impl From<NodeAddress> for Address {
    fn from(addr: NodeAddress) -> Self {
        Address::from_parts(addr.level.into(), addr.index)
    }
}
impl From<Address> for NodeAddress {
    fn from(addr: Address) -> Self {
        Self {
            level: addr.level().into(),
            index: addr.index(),
        }
    }
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23033))]
#[cbor(array)]
pub struct SerializableTreeShard {
    #[n(0)]
    pub index: u64,
    #[n(1)]
    pub shard: SerializableNode,
}
impl<H> TryFrom<&SerializableTreeShard> for LocatedPrunableTree<H>
where
    H: MerkleCodec + Clone,
{
    type Error = RuntimeError;

    fn try_from(value: &SerializableTreeShard) -> ZKError<Self> {
        let root = Tree::try_from(&value.shard)?;

        LocatedPrunableTree::from_parts(Address::from_parts(SHARD_HEIGHT_LEVEL, value.index), root)
            .map_err(|_| input_err("prunable_tree", "Invalid tree."))
    }
}
impl<H> TryFrom<&LocatedPrunableTree<H>> for SerializableTreeShard
where
    H: MerkleCodec + Clone,
{
    type Error = RuntimeError;

    fn try_from(tree: &LocatedPrunableTree<H>) -> ZKError<Self> {
        let shard = SerializableNode::try_from(tree.root())?;

        let address = tree.root_addr();

        Ok(SerializableTreeShard {
            index: address.index(),
            shard,
        })
    }
}
fn map_internal<E: ToString>(e: E) -> RuntimeError {
    internal_err(&e.to_string())
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23026))]
#[cbor(array)]
pub struct SerializableTreeCheckpoint {
    #[n(0)]
    pub position: Option<u64>,
    #[n(1)]
    pub checkpoint_id: u32,
}
impl SerializableTreeCheckpoint {
    pub fn get_checkpoint(&self) -> Checkpoint {
        match self.position {
            Some(position) => Checkpoint::at_position(position.into()),
            None => Checkpoint::tree_empty(),
        }
    }
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(array)]
#[cbor(tag(23034))]
pub struct SerializableShardTree {
    #[n(0)]
    pub cap: SerializableNode,
    #[n(1)]
    pub shards: Vec<SerializableTreeShard>,
    #[n(2)]
    pub checkpoints: Vec<SerializableTreeCheckpoint>,
}
impl<T> TryFrom<&SerializableShardTree>
    for ShardTree<MemoryShardStore<T, u32>, { NOTE_COMMITMENT_TREE_DEPTH }, SHARD_HEIGHT>
where
    T: MerkleCodec + Clone + Hashable + PartialEq,
{
    type Error = RuntimeError;

    fn try_from(value: &SerializableShardTree) -> ZKError<Self> {
        let mut tree = ShardTree::new(MemoryShardStore::empty(), MAX_CHECKPOINTS);

        let cap: PrunableTree<T> = Tree::try_from(&value.cap)?;
        tree.store_mut().put_cap(cap).map_err(map_internal)?;

        for shard in &value.shards {
            let shard: LocatedPrunableTree<T> = shard.try_into()?;
            tree.store_mut().put_shard(shard).map_err(map_internal)?;
        }

        for checkpoint in &value.checkpoints {
            tree.store_mut()
                .add_checkpoint(checkpoint.checkpoint_id, checkpoint.get_checkpoint())
                .map_err(map_internal)?;
        }

        Ok(tree)
    }
}

impl<T> TryFrom<&ShardTree<MemoryShardStore<T, u32>, NOTE_COMMITMENT_TREE_DEPTH, SHARD_HEIGHT>>
    for SerializableShardTree
where
    T: MerkleCodec + Clone + Hashable + PartialEq,
{
    type Error = RuntimeError;

    fn try_from(
        tree: &ShardTree<MemoryShardStore<T, u32>, NOTE_COMMITMENT_TREE_DEPTH, SHARD_HEIGHT>,
    ) -> ZKError<Self> {
        let store = tree.store();
        let cap = store.get_cap().map_err(map_internal)?;
        let cap = SerializableNode::try_from(&cap)?;
        let shards = store
            .get_shard_roots()
            .map_err(map_internal)?
            .iter()
            .map(|shard_root| {
                let shard = store.get_shard(*shard_root).map_err(map_internal)?.unwrap();
                let shard = SerializableTreeShard::try_from(&shard)?;
                Ok(shard)
            })
            .collect::<ZKError<Vec<_>>>()?;
        let mut checkpoints = Vec::<SerializableTreeCheckpoint>::new();
        store
            .for_each_checkpoint(usize::MAX, |id, checkpoint| {
                checkpoints.push(SerializableTreeCheckpoint {
                    checkpoint_id: (*id).into(),
                    position: match checkpoint.tree_state() {
                        shardtree::store::TreeState::Empty => None,
                        shardtree::store::TreeState::AtPosition(position) => Some(position.into()),
                    },
                });
                Ok(())
            })
            .ok();
        Ok(SerializableShardTree {
            cap,
            shards,
            checkpoints,
        })
    }
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23029))]
#[cbor(array)]
pub struct SerializableLocatedPrunableTree {
    #[n(0)]
    pub root: SerializableNode,
    #[n(1)]
    pub address: NodeAddress,
}

impl<H> TryFrom<&SerializableLocatedPrunableTree> for LocatedPrunableTree<H>
where
    H: MerkleCodec + Clone,
{
    type Error = RuntimeError;

    fn try_from(value: &SerializableLocatedPrunableTree) -> ZKError<Self> {
        let root_tree: Tree<Option<Arc<H>>, (H, RetentionFlags)> = Tree::try_from(&value.root)?;
        let root_addr: Address = value.address.clone().into();
        Ok(LocatedTree::from_parts(root_addr, root_tree)
            .map_err(|_| input_err("located_prunable_tree", "invalid tree."))?)
    }
}
impl<H> TryFrom<&LocatedPrunableTree<H>> for SerializableLocatedPrunableTree
where
    H: MerkleCodec + Clone,
{
    type Error = RuntimeError;
    fn try_from(tree: &LocatedPrunableTree<H>) -> Result<Self, Self::Error> {
        let root = SerializableNode::try_from(tree.root())?;

        let address = NodeAddress::from(tree.root_addr());

        Ok(SerializableLocatedPrunableTree { root, address })
    }
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23037))]
#[cbor(array)]
pub struct SerializableTreeCheckpointPosition {
    #[n(0)]
    pub checkpoint: u32,
    #[n(1)]
    pub position: u64,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23036))]
#[cbor(array)]
pub struct SerializableTreeInsertReport {
    #[n(0)]
    pub subtree: SerializableLocatedPrunableTree,
    #[n(1)]
    pub checkpoints: Vec<SerializableTreeCheckpointPosition>,
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23047))]
#[cbor(array)]
pub struct SubtreeRoots {
    #[n(0)]
    pub start: u32,
    #[n(1)]
    pub hashes: Vec<ByteArray<32>>,
}
impl<T> TryFrom<&SubtreeRoots> for Vec<T>
where
    T: MerkleCodec,
{
    type Error = RuntimeError;

    fn try_from(value: &SubtreeRoots) -> ZKError<Self> {
        value
            .hashes
            .iter()
            .map(|bytes| T::from_bytes(*bytes.as_ref()))
            .collect::<ZKError<Vec<_>>>()
    }
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23039))]
#[cbor(array)]
pub struct SerializableNonEmptyFrontier {
    #[n(0)]
    pub position: u64,
    #[n(1)]
    pub leaf: ByteArray<32>,
    #[n(2)]
    pub ommers: Vec<ByteArray<32>>,
}

impl<T> TryFrom<SerializableNonEmptyFrontier> for Frontier<T, NOTE_COMMITMENT_TREE_DEPTH>
where
    T: MerkleCodec,
{
    type Error = RuntimeError;

    fn try_from(value: SerializableNonEmptyFrontier) -> ZKError<Self> {
        let ommers = value
            .ommers
            .into_iter()
            .map(|b| decode_node::<T>(b.into(), "frontier_ommers"))
            .collect::<ZKError<Vec<_>>>()?;

        let leaf = decode_node::<T>(value.leaf.into(), "frontier_leaf")?;
        let position: Position = value.position.into();

        Frontier::from_parts(position, leaf, ommers)
            .map_err(|_| input_err("frontier", "failed to construct frontier"))
    }
}
impl<T> TryFrom<&SerializableNonEmptyFrontier> for Frontier<T, NOTE_COMMITMENT_TREE_DEPTH>
where
    T: MerkleCodec,
{
    type Error = RuntimeError;

    fn try_from(value: &SerializableNonEmptyFrontier) -> ZKError<Self> {
        value.clone().try_into()
    }
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23041))]
#[cbor(array)]
pub struct ChainState {
    #[n(0)]
    pub final_orchard_tree: Option<SerializableNonEmptyFrontier>,
    #[n(1)]
    pub final_sapling_tree: Option<SerializableNonEmptyFrontier>,
    #[n(2)]
    pub block_height: u32,
    #[n(3)]
    pub block_hash: ByteArray<32>,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23038))]
#[cbor(array)]
pub struct SerializableMerkleInsertReport {
    #[n(0)]
    pub orchard: Option<SerializableTreeInsertReport>,
    #[n(1)]
    pub sapling: Option<SerializableTreeInsertReport>,
    #[n(2)]
    pub height: u32,
    #[n(3)]
    pub final_orchard_tree: u32,
    #[n(4)]
    pub final_sapling_tree: u32,
    #[n(5)]
    pub chain_state: ChainState,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23048))]
#[cbor(array)]
pub struct BlockBundles {
    #[n(0)]
    pub sapling: ScannedProtocolBundles,
    #[n(1)]
    pub orchard: ScannedProtocolBundles,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23055))]
#[cbor(array)]
pub struct BlocksBundles {
    #[n(0)]
    pub bundles: Vec<BlockBundles>,
    #[n(1)]
    pub start_height: u32,
}
pub trait MerkleCodec: Sized {
    fn to_bytes(&self) -> [u8; 32];
    fn from_bytes(bytes: [u8; 32]) -> ZKError<Self>;
    fn encode(&self) -> ByteArray<32> {
        ByteArray::from(self.to_bytes())
    }
}

impl MerkleCodec for SaplingNode {
    fn to_bytes(&self) -> [u8; 32] {
        SaplingNode::to_bytes(self)
    }

    fn from_bytes(bytes: [u8; 32]) -> ZKError<Self> {
        SaplingNode::from_bytes(bytes)
            .map_err(|_| enc_err("sapling_node", "invalid 32-byte encoding"))
    }
}
impl MerkleCodec for MerkleHashOrchard {
    fn to_bytes(&self) -> [u8; 32] {
        MerkleHashOrchard::to_bytes(self)
    }

    fn from_bytes(bytes: [u8; 32]) -> ZKError<Self> {
        MerkleHashOrchard::from_bytes(&bytes)
            .into_option()
            .ok_or(enc_err("orchard_merkle_hash", "invalid 32-byte encoding"))
    }
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23035))]
#[cbor(array)]
pub struct ChainMerkleState {
    #[n(0)]
    pub sapling: SerializableShardTree,
    #[n(1)]
    pub orchard: SerializableShardTree,
    #[n(2)]
    pub sapling_subtree_index: u32,
    #[n(3)]
    pub orchard_subtree_index: u32,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23057))]
#[cbor(array)]
pub struct CreateWitnessParams {
    #[n(0)]
    pub protocol: u8,
    #[n(1)]
    pub height: u32,
    #[n(2)]
    pub positions: Vec<u64>,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23058))]
#[cbor(array)]
pub struct SerializableMerklePath {
    #[n(0)]
    pub pahts: Vec<ByteArray<32>>,
    #[n(1)]
    pub position: u64,
}
impl<H, const DEPTH: u8> TryFrom<&MerklePath<H, DEPTH>> for SerializableMerklePath
where
    H: MerkleCodec,
{
    type Error = RuntimeError;

    fn try_from(value: &MerklePath<H, DEPTH>) -> ZKError<Self> {
        let elems = value.path_elems();
        if elems.len() != 32 {
            return Err(internal_err(
                "merkle path has invalid length (expected 32 elements)",
            ));
        }
        let mut pahts: Vec<ByteArray<32>> = Vec::with_capacity(32);

        for elem in elems {
            pahts.push(ByteArray::from(elem.to_bytes()));
        }

        Ok(SerializableMerklePath {
            pahts,
            position: value.position().into(),
        })
    }
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23059))]
#[cbor(array)]
pub struct SerializableWitnesses {
    #[n(0)]
    pub anchor: Option<ByteArray<32>>,
    #[n(1)]
    pub merkles: Vec<SerializableMerklePath>,
}

pub trait WitnessTree {
    type Node;

    fn root_at_checkpoint_id(&self, height: &u32) -> Result<Option<Self::Node>, RuntimeError>;

    fn witness_at_checkpoint_id_caching(
        &mut self,
        position: Position,
        height: &u32,
    ) -> Result<Option<MerklePath<Self::Node, NOTE_COMMITMENT_TREE_DEPTH>>, RuntimeError>;

    fn create_witness_for_tree<T>(
        tree: &mut T,
        params: CreateWitnessParams,
    ) -> ZKError<SerializableWitnesses>
    where
        T: WitnessTree,
        T::Node: MerkleCodec,
    {
        let anchor = tree.root_at_checkpoint_id(&params.height)?;

        let anchor = anchor.map(|a| ByteArray::from(a.to_bytes()));

        let merkles = params
            .positions
            .into_iter()
            .map(|pos| -> ZKError<SerializableMerklePath> {
                let p: Position = pos.into();

                let merkle = tree
                    .witness_at_checkpoint_id_caching(p, &params.height)?
                    .ok_or_else(|| RuntimeError {
                        code: Error::WitnessError,
                        msg: "Missing checkpoint".to_string(),
                    })?;

                (&merkle).try_into()
            })
            .collect::<ZKError<Vec<_>>>()?;

        Ok(SerializableWitnesses { anchor, merkles })
    }
}
impl WitnessTree for ShardTree<SaplingShardStore, NOTE_COMMITMENT_TREE_DEPTH, SHARD_HEIGHT> {
    type Node = SaplingNode;

    fn root_at_checkpoint_id(&self, height: &u32) -> Result<Option<Self::Node>, RuntimeError> {
        self.root_at_checkpoint_id(height)
            .map_err(|e| RuntimeError {
                code: Error::WitnessError,
                msg: e.to_string(),
            })
    }

    fn witness_at_checkpoint_id_caching(
        &mut self,
        position: Position,
        height: &u32,
    ) -> Result<Option<MerklePath<Self::Node, NOTE_COMMITMENT_TREE_DEPTH>>, RuntimeError> {
        self.witness_at_checkpoint_id_caching(position, height)
            .map_err(|e| RuntimeError {
                code: Error::WitnessError,
                msg: e.to_string(),
            })
    }
}
impl WitnessTree for ShardTree<OrchardShardStore, NOTE_COMMITMENT_TREE_DEPTH, SHARD_HEIGHT> {
    type Node = MerkleHashOrchard;

    fn root_at_checkpoint_id(&self, height: &u32) -> Result<Option<Self::Node>, RuntimeError> {
        self.root_at_checkpoint_id(height)
            .map_err(|e| RuntimeError {
                code: Error::WitnessError,
                msg: e.to_string(),
            })
    }

    fn witness_at_checkpoint_id_caching(
        &mut self,
        position: Position,
        height: &u32,
    ) -> Result<Option<MerklePath<Self::Node, NOTE_COMMITMENT_TREE_DEPTH>>, RuntimeError> {
        self.witness_at_checkpoint_id_caching(position, height)
            .map_err(
                |e: shardtree::error::ShardTreeError<std::convert::Infallible>| RuntimeError {
                    code: Error::WitnessError,
                    msg: e.to_string(),
                },
            )
    }
}
