use crate::sapling::constants::GROTH_PROOF_SIZE;
use bls12_381::Scalar;
use minicbor::{bytes::ByteArray, Decode, Encode};

/// Maximum size for auth path (you can adjust this)
pub const MAX_AUTH_PATH: usize = 32;

pub const MAX_SPEND_VERIFY_INPUTS: usize = 7;

pub const MAX_OUTPUT_VERIFY_INPUTS: usize = 5;
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23049))]
#[cbor(array)]
pub struct SaplingSpendBytes {
    #[n(0)]
    pub value: u64,
    #[n(1)]
    pub randomness: ByteArray<32>,
    #[n(2)]
    pub ak: ByteArray<32>,

    #[n(3)]
    pub nsk: ByteArray<32>,
    #[n(4)]
    pub payment_address_diversify_hash: ByteArray<32>,
    #[n(5)]
    pub commitment_randomness: ByteArray<32>,

    #[n(6)]
    pub ar: ByteArray<32>,
    #[n(7)]
    pub auth_path: [ByteArray<32>; MAX_AUTH_PATH],
    #[n(8)]
    pub auth_path_pos: [bool; MAX_AUTH_PATH],
    #[n(9)]
    pub anchor: ByteArray<32>,
}

impl SaplingSpendBytes {
    pub fn dummy() -> Self {
        Self {
            value: 42,

            randomness: ByteArray::from([1u8; 32]),
            ak: ByteArray::from([2u8; 32]),
            nsk: ByteArray::from([3u8; 32]),
            payment_address_diversify_hash: ByteArray::from([4u8; 32]),
            commitment_randomness: ByteArray::from([5u8; 32]),
            ar: ByteArray::from([6u8; 32]),

            auth_path: [ByteArray::from([7u8; 32]); MAX_AUTH_PATH],
            auth_path_pos: [true; MAX_AUTH_PATH],

            anchor: ByteArray::from([11u8; 32]),
        }
    }
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23050))]
#[cbor(array)]
pub struct SaplingOutputBytes {
    #[n(0)]
    pub value: u64,
    #[n(1)]
    pub randomness: ByteArray<32>,
    #[n(2)]
    pub recipient_address_diversify_hash: ByteArray<32>,
    #[n(3)]
    pub recipient_address_pk_d: ByteArray<32>,
    #[n(4)]
    pub commitment_randomness: ByteArray<32>,
    #[n(5)]
    pub esk: ByteArray<32>,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23051))]
#[cbor(array)]
pub struct SaplingSpendVerificationBytes {
    #[n(0)]
    pub proof: ByteArray<GROTH_PROOF_SIZE>,
    #[n(1)]
    pub public_inputs: [ByteArray<32>; MAX_SPEND_VERIFY_INPUTS],
}

pub struct SaplingSpendVerification {
    pub proof: [u8; GROTH_PROOF_SIZE],
    pub public_inputs: [Scalar; MAX_SPEND_VERIFY_INPUTS],
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23051))]
#[cbor(array)]
pub struct SaplingOutputVerificationBytes {
    #[n(0)]
    pub proof: ByteArray<GROTH_PROOF_SIZE>,
    #[n(1)]
    pub public_inputs: [ByteArray<32>; MAX_OUTPUT_VERIFY_INPUTS],
}
pub struct SaplingOutputVerification {
    pub proof: [u8; GROTH_PROOF_SIZE],
    pub public_inputs: [Scalar; MAX_OUTPUT_VERIFY_INPUTS],
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23063))]
#[cbor(array)]
pub struct PedersenHash {
    #[n(0)]
    pub merkle_tree_size: Option<u32>,
    #[n(1)]
    pub bits: Vec<bool>,
}
