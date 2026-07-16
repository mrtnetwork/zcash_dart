use minicbor::{Decode, Encode};

use crate::{
    merkle::types::{
        BlocksBundles, ChainMerkleState, ChainState, CreateWitnessParams,
        SerializableMerkleInsertReport, SubtreeRoots,
    },
    orchard::types::{
        CommitmentDomain, CommitmentShortDomain, OrchardProofParams, OrchardVerifyProofParams,
        PseudoRando,
    },
    sapling::types::{
        PedersenHash, SaplingOutputBytes, SaplingOutputVerificationBytes, SaplingSpendBytes,
        SaplingSpendVerificationBytes,
    },
};

#[derive(Encode, Decode)]
#[cbor(tag(23035))]
#[cbor(array)]
pub enum ZKRequest {
    #[n(0)]
    MerkleCreateContext(#[n(0)] ChainMerkleState),
    #[n(1)]
    /// (Sapling,Orchard)
    MerkleUpdateSubtree(#[n(0)] u32, #[n(1)] u8, #[n(2)] SubtreeRoots),
    #[n(2)]
    MerkleInsertChainState(#[n(0)] u32, #[n(1)] ChainState),
    #[n(3)]
    MerkleUpdateState(#[n(0)] u32, #[n(1)] BlocksBundles),
    #[n(4)]
    MerkleMergeState(#[n(0)] u32, #[n(1)] SerializableMerkleInsertReport),
    #[n(5)]
    MerkleCloseContext(#[n(0)] u32),
    #[n(6)]
    SaplingHasSpendParams(),
    #[n(7)]
    SaplingHasOutputParams(),

    #[n(8)]
    SaplingSetupSpendParams(
        #[n(0)]
        #[cbor(with = "minicbor::bytes")]
        Vec<u8>,
    ),
    #[n(9)]
    SaplingSetupOutputParams(
        #[n(0)]
        #[cbor(with = "minicbor::bytes")]
        Vec<u8>,
    ),
    #[n(10)]
    SaplingCreateSpendProof(#[n(0)] SaplingSpendBytes),

    #[n(11)]
    SaplingCreateOutputProof(#[n(0)] SaplingOutputBytes),
    #[n(12)]
    SaplingVerifySpendProof(#[n(0)] SaplingSpendVerificationBytes),
    #[n(13)]
    SaplingVerifyOutputProof(#[n(0)] SaplingOutputVerificationBytes),

    #[n(14)]
    OrchardCreateActionProof(#[n(0)] OrchardProofParams),

    #[n(15)]
    OrchardVerifyActionProof(#[n(0)] OrchardVerifyProofParams),

    #[n(16)]
    SaplingClearSpendParams(),
    #[n(17)]
    SaplingClearOutputParams(),
    #[n(18)]
    SaplingClearOrchardProvingKey(),
    #[n(19)]
    Version(),

    #[n(20)]
    MerkleGetContext(#[n(0)] u32),

    #[n(21)]
    MerkleCreateWitness(#[n(0)] u32, #[n(1)] CreateWitnessParams),

    #[n(22)]
    EnableLogging(#[n(0)] bool, #[n(1)] u8),
    #[n(23)]
    CommitmentShortDomain(#[n(0)] CommitmentShortDomain),
    #[n(24)]
    CommitmentDomain(#[n(0)] CommitmentDomain),
    #[n(25)]
    PseudoRando(#[n(0)] PseudoRando),
    #[n(26)]
    PedersenHash(#[n(0)] PedersenHash),
}
impl std::fmt::Debug for ZKRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let name = match self {
            ZKRequest::MerkleCreateContext(id) => format!(
                "MerkleCreateContext(orchard_subtree_index:{:#?}, sapling_subtree_index:{:#?})",
                id.orchard_subtree_index, id.sapling_subtree_index
            ),
            ZKRequest::MerkleUpdateSubtree(id, _, _) => format!("MerkleUpdateSubtree(id:{:#?}", id),
            ZKRequest::MerkleInsertChainState(id, _) => {
                format!("MerkleInsertChainState(id:{:#?}", id)
            }
            ZKRequest::MerkleUpdateState(id, _) => format!("MerkleUpdateState(id:{:#?}", id),
            ZKRequest::MerkleMergeState(id, _) => format!("MerkleMergeState(id:{:#?}", id),
            ZKRequest::MerkleCloseContext(_) => "MerkleCloseContext".to_string(),
            ZKRequest::SaplingHasSpendParams() => "SaplingHasSpendParams".to_string(),
            ZKRequest::SaplingHasOutputParams() => "SaplingHasOutputParams".to_string(),
            ZKRequest::SaplingSetupSpendParams(_) => "SaplingSetupSpendParams".to_string(),
            ZKRequest::SaplingSetupOutputParams(_) => "SaplingSetupOutputParams".to_string(),
            ZKRequest::SaplingCreateSpendProof(_) => "SaplingCreateSpendProof".to_string(),
            ZKRequest::SaplingCreateOutputProof(_) => "SaplingCreateOutputProof".to_string(),
            ZKRequest::SaplingVerifySpendProof(_) => "SaplingVerifySpendProof".to_string(),
            ZKRequest::SaplingVerifyOutputProof(_) => "SaplingVerifyOutputProof".to_string(),
            ZKRequest::OrchardCreateActionProof(_) => "OrchardCreateActionProof".to_string(),
            ZKRequest::OrchardVerifyActionProof(_) => "OrchardVerifyActionProof".to_string(),
            ZKRequest::SaplingClearSpendParams() => "SaplingClearSpendParams".to_string(),
            ZKRequest::SaplingClearOutputParams() => "SaplingClearOutputParams".to_string(),
            ZKRequest::SaplingClearOrchardProvingKey() => {
                "SaplingClearOrchardProvingKey".to_string()
            }
            ZKRequest::Version() => "Version".to_string(),
            ZKRequest::MerkleGetContext(id) => format!("MerkleGetContext(id:{:#?}", id),
            ZKRequest::MerkleCreateWitness(id, _) => format!("MerkleCreateWitness(id:{:#?}", id),
            ZKRequest::EnableLogging(enable, mode) => {
                format!("EnableLogging(enable:{:#?}, {:#?}", enable, mode)
            }
            ZKRequest::CommitmentShortDomain(_) => "CommitmentShortDomain".to_string(),
            ZKRequest::CommitmentDomain(_) => "CommitmentDomain".to_string(),
            ZKRequest::PseudoRando(_) => "PseudoRando".to_string(),
            ZKRequest::PedersenHash(_) => "PedersenHash".to_string(),
        };

        write!(f, "ZKRequest::{name}")
    }
}
