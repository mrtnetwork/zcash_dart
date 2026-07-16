use minicbor::{bytes::ByteArray, Decode, Encode};
use pasta_curves::vesta;

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23052))]
#[cbor(array)]
pub struct OrchardProofInputs {
    #[n(0)]
    pub fvk: ByteArray<96>,
    #[n(1)]
    pub recipient: ByteArray<43>,
    #[n(2)]
    pub value: u64,
    #[n(3)]
    pub rho: ByteArray<32>,
    #[n(4)]
    pub rseed: ByteArray<32>,
    #[n(5)]
    pub position: u32,
    #[n(6)]
    pub auth_path: [ByteArray<32>; 32],
    #[n(7)]
    pub out_recipient: ByteArray<43>,
    #[n(8)]
    pub out_value: u64,
    #[n(9)]
    pub out_rho: ByteArray<32>,
    #[n(10)]
    pub out_rseed: ByteArray<32>,
    #[n(11)]
    pub alpha: ByteArray<32>,
    #[n(12)]
    pub rcv: ByteArray<32>,
    #[n(13)]
    pub instances: [ByteArray<32>; 9],
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23053))]
#[cbor(array)]
pub struct OrchardProofParams {
    #[n(0)]
    pub circuits: Vec<OrchardProofInputs>,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23054))]
#[cbor(array)]
pub struct OrchardVerifyProofParams {
    #[n(0)]
    #[cbor(with = "minicbor::bytes")]
    pub proof: Vec<u8>,
    #[n(1)]
    pub instances: Vec<[ByteArray<32>; 9]>,
}

pub struct OrchardProof {
    pub proof: Vec<u8>,
    pub instances: Vec<[[vesta::Scalar; 9]; 1]>,
}

#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23060))]
#[cbor(array)]
pub struct CommitmentShortDomain {
    #[n(0)]
    pub domain: String,
    #[n(1)]
    pub bits: Vec<bool>,
    #[n(2)]
    pub r: ByteArray<32>,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23061))]
#[cbor(array)]
pub struct CommitmentDomain {
    #[n(0)]
    pub domain: String,
    #[n(1)]
    pub bits: Vec<bool>,

    #[n(2)]
    pub r: ByteArray<32>,
}
#[derive(Clone, Debug, Encode, Decode)]
#[cbor(tag(23062))]
#[cbor(array)]
pub struct PseudoRando {
    #[n(0)]
    pub nk: ByteArray<32>,
    #[n(1)]
    pub rho: ByteArray<32>,
}
