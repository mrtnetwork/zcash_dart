//! Abstractions over the proving system and parameters.

use std::io::Cursor;

use bellman::groth16::{create_random_proof, verify_proof, Proof};
use bls12_381::Bls12;
use rand_core::RngCore;

use crate::{
    error::Error,
    sapling::{
        circuit::{self},
        constants::GROTH_PROOF_SIZE,
    },
};

use super::{
    circuit::{Output, OutputParameters, Spend, SpendParameters},
    // Diversifier, Note, PaymentAddress, ProofGenerationKey, Rseed,
};

/// Interface for creating Sapling Spend proofs.
pub trait SpendProver {
    /// The proof type created by this prover.
    type Proof;

    /// Create the proof for a Sapling [`SpendDescription`].
    ///
    /// [`SpendDescription`]: crate::bundle::SpendDescription
    fn create_proof<R: RngCore>(&self, circuit: circuit::Spend, rng: &mut R) -> Self::Proof;

    /// Encodes the given Sapling [`SpendDescription`] proof, erasing its type.
    ///
    /// [`SpendDescription`]: crate::bundle::SpendDescription
    fn encode_proof(proof: Self::Proof) -> [u8; GROTH_PROOF_SIZE];

    fn verify(&self, proof: &Self::Proof, inputs: &[jubjub::Fq]) -> bool;

    fn parse_proof(&self, proof_bytes: [u8; GROTH_PROOF_SIZE]) -> Result<Self::Proof, Error>;
}

/// Interface for creating Sapling Output proofs.
pub trait OutputProver {
    /// The proof type created by this prover.
    type Proof;

    /// Create the proof for a Sapling [`OutputDescription`].
    ///
    /// [`OutputDescription`]: crate::bundle::OutputDescription
    fn create_proof<R: RngCore>(&self, circuit: circuit::Output, rng: &mut R) -> Self::Proof;

    /// Encodes the given Sapling [`OutputDescription`] proof, erasing its type.
    ///
    /// [`OutputDescription`]: crate::bundle::OutputDescription
    fn encode_proof(proof: Self::Proof) -> [u8; GROTH_PROOF_SIZE];

    /// proof
    fn verify(&self, proof: &Self::Proof, inputs: &[jubjub::Fq]) -> bool;

    fn parse_proof(&self, proof_bytes: [u8; GROTH_PROOF_SIZE]) -> Result<Self::Proof, Error>;
}

impl SpendProver for SpendParameters {
    type Proof = Proof<Bls12>;

    fn create_proof<R: RngCore>(&self, circuit: Spend, rng: &mut R) -> Self::Proof {
        create_random_proof(circuit, &self.0, rng).expect("proving should not fail")
    }

    fn encode_proof(proof: Self::Proof) -> [u8; GROTH_PROOF_SIZE] {
        let mut zkproof = [0u8; GROTH_PROOF_SIZE];
        proof
            .write(&mut zkproof[..])
            .expect("should be able to serialize a proof");
        zkproof
    }

    fn verify(&self, proof: &Self::Proof, inputs: &[jubjub::Fq]) -> bool {
        let pvk = self.prepared_verifying_key();
        verify_proof(&pvk.0, proof, inputs).is_ok()
    }

    fn parse_proof(&self, proof_bytes: [u8; GROTH_PROOF_SIZE]) -> Result<Self::Proof, Error> {
        let mut cursor = Cursor::new(&proof_bytes[..]);
        Proof::read(&mut cursor).map_err(|_| Error::SaplingInvalidProof)
    }
}

impl OutputProver for OutputParameters {
    type Proof = Proof<Bls12>;

    fn create_proof<R: RngCore>(&self, circuit: Output, rng: &mut R) -> Self::Proof {
        create_random_proof(circuit, &self.0, rng).expect("proving should not fail")
    }

    fn encode_proof(proof: Self::Proof) -> [u8; GROTH_PROOF_SIZE] {
        let mut zkproof = [0u8; GROTH_PROOF_SIZE];
        proof
            .write(&mut zkproof[..])
            .expect("should be able to serialize a proof");
        zkproof
    }

    fn verify(&self, proof: &Self::Proof, inputs: &[jubjub::Fq]) -> bool {
        let pvk = self.prepared_verifying_key();
        verify_proof(&pvk.0, proof, inputs).is_ok()
    }

    fn parse_proof(&self, proof_bytes: [u8; GROTH_PROOF_SIZE]) -> Result<Self::Proof, Error> {
        let mut cursor = Cursor::new(&proof_bytes[..]);
        Proof::read(&mut cursor).map_err(|_| Error::SaplingInvalidProof)
    }
}
