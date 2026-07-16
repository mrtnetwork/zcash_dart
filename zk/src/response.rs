use std::string;

use crate::merkle::types::{
    ChainMerkleState, SerializableMerkleInsertReport, SerializableWitnesses,
};

#[derive(minicbor::Encode, minicbor::Decode)]
#[cbor(tag(23056))]
#[cbor(array)]
pub enum ZKResponse {
    #[n(0)]
    Error(#[n(0)] u32, #[n(1)] string::String),
    #[n(1)]
    Ok(),
    #[n(2)]
    SaplingHasParams(#[n(0)] bool),
    #[n(3)]
    SaplingProof(
        #[n(0)]
        #[cbor(with = "minicbor::bytes")]
        [u8; 192],
    ),
    #[n(4)]
    VerifyProof(#[n(0)] bool),
    #[n(5)]
    OrchardActionProof(
        #[n(0)]
        #[cbor(with = "minicbor::bytes")]
        Vec<u8>,
    ),
    #[n(6)]
    Version(#[n(0)] u8),

    #[n(7)]
    MerkleCreateContext(#[n(0)] u32),

    #[n(8)]
    MerkleUpdateResult(#[n(0)] SerializableMerkleInsertReport),
    #[n(9)]
    MerkleUpdateSubtreeResult(#[n(0)] u32),
    #[n(10)]
    MerkleGetContextResult(#[n(0)] ChainMerkleState),
    #[n(11)]
    MerkleCreateWitnessResult(#[n(0)] SerializableWitnesses),
    #[n(12)]
    Bytes(
        #[n(0)]
        #[cbor(with = "minicbor::bytes")]
        Vec<u8>,
    ),
}
impl std::fmt::Debug for ZKResponse {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let name = match self {
            ZKResponse::Error(_, _) => "Error".to_string(),
            ZKResponse::Ok() => "Ok".to_string(),
            ZKResponse::SaplingHasParams(_) => "SaplingHasParams".to_string(),
            ZKResponse::SaplingProof(_) => "SaplingProof".to_string(),
            ZKResponse::VerifyProof(_) => "VerifyProof".to_string(),
            ZKResponse::OrchardActionProof(_) => "OrchardActionProof".to_string(),
            ZKResponse::Version(_) => "Version".to_string(),
            ZKResponse::MerkleCreateContext(id) => format!("MerkleCreateContext(id:{:#?}", id),
            ZKResponse::MerkleUpdateResult(_) => "MerkleUpdateResult".to_string(),
            ZKResponse::MerkleUpdateSubtreeResult(_) => "MerkleUpdateSubtreeResult".to_string(),
            ZKResponse::MerkleGetContextResult(_) => "MerkleGetContextResult".to_string(),
            ZKResponse::MerkleCreateWitnessResult(e) => {
                format!(
                    "MerkleCreateWitnessResult(has_anchor={}, paths={})",
                    e.anchor.is_some(),
                    e.merkles.len()
                )
            }
            ZKResponse::Bytes(_) => "Bytes".to_string(),
        };

        write!(f, "ZKResponse::{name}")
    }
}
