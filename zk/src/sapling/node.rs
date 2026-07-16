use bitvec::{order::Lsb0, view::AsBits};
use core::fmt;
use ff::PrimeField;
use group::Curve;
use incrementalmerkletree::{Hashable, Level};
use lazy_static::lazy_static;

use crate::{
    error::Error,
    sapling::pedersen_hash::{pedersen_hash, Personalization},
};
pub const NOTE_COMMITMENT_TREE_DEPTH: u8 = 32;
pub const SAPLING_SHARD_HEIGHT: u8 = 16;
pub type CommitmentTree =
    incrementalmerkletree::frontier::CommitmentTree<SaplingNode, NOTE_COMMITMENT_TREE_DEPTH>;
pub type IncrementalWitness =
    incrementalmerkletree::witness::IncrementalWitness<SaplingNode, NOTE_COMMITMENT_TREE_DEPTH>;
pub type MerklePath = incrementalmerkletree::MerklePath<SaplingNode, NOTE_COMMITMENT_TREE_DEPTH>;
lazy_static! {
    static ref UNCOMMITTED_SAPLING: bls12_381::Scalar = bls12_381::Scalar::one();
    static ref EMPTY_ROOTS: Vec<SaplingNode> = empty_roots();
}
fn empty_roots() -> Vec<SaplingNode> {
    let mut v = vec![SaplingNode::empty_leaf()];
    for d in 0..NOTE_COMMITMENT_TREE_DEPTH {
        let next = SaplingNode::combine(d.into(), &v[usize::from(d)], &v[usize::from(d)]);
        v.push(next);
    }
    v
}
/// A node within the Sapling commitment tree.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct SaplingNode(jubjub::Base);

impl fmt::Debug for SaplingNode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SaplingNode").finish()
    }
}

impl Hashable for SaplingNode {
    fn empty_leaf() -> Self {
        SaplingNode(*UNCOMMITTED_SAPLING)
    }

    fn combine(level: Level, lhs: &Self, rhs: &Self) -> Self {
        SaplingNode(merkle_hash_field(
            level.into(),
            &lhs.0.to_bytes(),
            &rhs.0.to_bytes(),
        ))
    }

    fn empty_root(level: Level) -> Self {
        EMPTY_ROOTS[<usize>::from(level)]
    }
}

impl SaplingNode {
    /// Constructs a new note commitment tree node from a [`bls12_381::Scalar`]
    pub fn from_scalar(cmu: bls12_381::Scalar) -> Self {
        Self(cmu)
    }

    /// Returns the canonical byte representation of this node.
    pub fn to_bytes(&self) -> [u8; 32] {
        self.0.to_repr()
    }

    /// Parses a tree leaf from the bytes of a Sapling note commitment.
    ///
    /// Returns `None` if the provided bytes represent a non-canonical encoding.
    pub fn from_bytes(bytes: [u8; 32]) -> Result<Self, Error> {
        jubjub::Base::from_repr(bytes)
            .into_option()
            .map(SaplingNode)
            .ok_or(Error::EncodingError)
    }
}

/// Compute a parent node in the Sapling commitment tree given its two children.
pub fn merkle_hash(depth: usize, lhs: &[u8; 32], rhs: &[u8; 32]) -> [u8; 32] {
    merkle_hash_field(depth, lhs, rhs).to_repr()
}

fn merkle_hash_field(depth: usize, lhs: &[u8; 32], rhs: &[u8; 32]) -> jubjub::Base {
    let lhs = {
        let mut tmp = [false; 256];
        for (a, b) in tmp.iter_mut().zip(lhs.as_bits::<Lsb0>()) {
            *a = *b;
        }
        tmp
    };

    let rhs = {
        let mut tmp = [false; 256];
        for (a, b) in tmp.iter_mut().zip(rhs.as_bits::<Lsb0>()) {
            *a = *b;
        }
        tmp
    };

    jubjub::ExtendedPoint::from(pedersen_hash(
        Personalization::MerkleTree(depth),
        lhs.iter()
            .copied()
            .take(bls12_381::Scalar::NUM_BITS as usize)
            .chain(
                rhs.iter()
                    .copied()
                    .take(bls12_381::Scalar::NUM_BITS as usize),
            ),
    ))
    .to_affine()
    .get_u()
}
