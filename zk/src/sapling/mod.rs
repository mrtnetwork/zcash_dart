use bellman::groth16::Proof;
use bls12_381::Bls12;
pub mod circuit;
pub mod constants;
pub mod params;
pub mod pedersen_hash;
pub mod prover;

use crate::sapling::{
    circuit::{OutputParameters, SpendParameters},
    constants::GROTH_PROOF_SIZE,
    prover::{OutputProver, SpendProver},
};

pub struct SaplingSpendProver {
    pub(crate) spend_params: &'static SpendParameters,
}

impl SpendProver for SaplingSpendProver {
    type Proof = Proof<Bls12>;

    fn create_proof<R: rand_core::RngCore>(
        &self,
        circuit: circuit::Spend,
        rng: &mut R,
    ) -> Self::Proof {
        self.spend_params.create_proof(circuit, rng)
    }

    fn encode_proof(proof: Self::Proof) -> [u8; GROTH_PROOF_SIZE] {
        let mut zkproof = [0u8; 192];
        proof
            .write(&mut zkproof[..])
            .expect("should be able to serialize a proof");
        zkproof
    }

    fn verify(&self, proof: &Self::Proof, inputs: &[jubjub::Fq]) -> bool {
        self.spend_params.verify(proof, inputs)
    }
    fn parse_proof(
        &self,
        proof_bytes: [u8; GROTH_PROOF_SIZE],
    ) -> Result<Self::Proof, crate::error::Error> {
        self.spend_params.parse_proof(proof_bytes)
    }
}

pub struct SaplingOutputProver {
    pub(crate) output_params: &'static OutputParameters,
}

impl OutputProver for SaplingOutputProver {
    type Proof = Proof<Bls12>;

    fn create_proof<R: rand_core::RngCore>(
        &self,
        circuit: circuit::Output,
        rng: &mut R,
    ) -> Self::Proof {
        self.output_params.create_proof(circuit, rng)
    }

    fn encode_proof(proof: Self::Proof) -> [u8; GROTH_PROOF_SIZE] {
        let mut zkproof = [0u8; 192];
        proof
            .write(&mut zkproof[..])
            .expect("should be able to serialize a proof");
        zkproof
    }

    fn verify(&self, proof: &Self::Proof, inputs: &[jubjub::Fq]) -> bool {
        self.output_params.verify(proof, inputs)
    }

    fn parse_proof(
        &self,
        proof_bytes: [u8; GROTH_PROOF_SIZE],
    ) -> Result<Self::Proof, crate::error::Error> {
        self.output_params.parse_proof(proof_bytes)
    }
}
