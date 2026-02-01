use std::ptr;

use crate::{
    error::Error,
    sapling::{
        circuit::{Output, Spend, ValueCommitmentOpening},
        constants::GROTH_PROOF_SIZE,
    },
};
use bls12_381::Scalar;
use ff::PrimeField;
use group::GroupEncoding;
use jubjub::Fr;

use std::convert::TryInto;

/// Maximum size for auth path (you can adjust this)
pub const MAX_AUTH_PATH: usize = 32;

pub const MAX_SPEND_VERIFY_INPUTS: usize = 7;

pub const MAX_OUTPUT_VERIFY_INPUTS: usize = 5;

pub type WasmResult<T> = Result<T, Error>;

/// Fixed-size Spend struct for byte transfer
#[repr(C, packed)]
#[derive(Clone, Copy, Debug)]
pub struct SpendBytes {
    pub value: u64,
    pub randomness: [u8; 32],
    pub ak: [u8; 32],
    pub nsk: [u8; 32],
    pub payment_address_diversify_hash: [u8; 32],
    pub commitment_randomness: [u8; 32],
    pub ar: [u8; 32],
    pub auth_path: [[u8; 32]; MAX_AUTH_PATH], // each element is Scalar
    pub auth_path_pos: [u8; MAX_AUTH_PATH],   // bool flags 0/1
    pub anchor: [u8; 32],
}

pub struct SpendVerifyBytes {
    pub proof: [u8; GROTH_PROOF_SIZE],
    pub public_inputs: [[u8; 32]; MAX_SPEND_VERIFY_INPUTS],
}

pub struct SpendVerify {
    pub proof: [u8; GROTH_PROOF_SIZE],
    pub public_inputs: [Scalar; MAX_SPEND_VERIFY_INPUTS],
}
pub struct OutputVerifyBytes {
    pub proof: [u8; GROTH_PROOF_SIZE],
    pub public_inputs: [[u8; 32]; MAX_OUTPUT_VERIFY_INPUTS],
}

pub struct OutputVerify {
    pub proof: [u8; GROTH_PROOF_SIZE],
    pub public_inputs: [Scalar; MAX_OUTPUT_VERIFY_INPUTS],
}
/// Fixed-size Output struct for byte transfer
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct OutputBytes {
    pub value: u64,
    pub randomness: [u8; 32],
    pub recipient_address_diversify_hash: [u8; 32],
    pub recipient_address_pk_d: [u8; 32],
    pub commitment_randomness: [u8; 32],
    pub esk: [u8; 32],
}

/// =======================
/// Byte slice → fixed struct
/// =======================

fn spend_from_bytes(bytes: &[u8]) -> WasmResult<SpendBytes> {
    if bytes.len() != size_of::<SpendBytes>() {
        return Err(Error::InvalidLength);
    }
    Ok(unsafe { ptr::read_unaligned(bytes.as_ptr() as *const SpendBytes) })
}

pub fn output_from_bytes(bytes: &[u8]) -> WasmResult<OutputBytes> {
    if bytes.len() != size_of::<OutputBytes>() {
        return Err(Error::InvalidLength);
    }
    Ok(unsafe { ptr::read_unaligned(bytes.as_ptr() as *const OutputBytes) })
}

fn spend_verify_from_bytes(bytes: &[u8]) -> WasmResult<SpendVerifyBytes> {
    if bytes.len() != size_of::<SpendVerifyBytes>() {
        return Err(Error::InvalidLength);
    }
    Ok(unsafe { ptr::read_unaligned(bytes.as_ptr() as *const SpendVerifyBytes) })
}
fn output_verify_from_bytes(bytes: &[u8]) -> WasmResult<OutputVerifyBytes> {
    if bytes.len() != size_of::<OutputVerifyBytes>() {
        return Err(Error::InvalidLength);
    }
    Ok(unsafe { ptr::read_unaligned(bytes.as_ptr() as *const OutputVerifyBytes) })
}

/// =======================
/// Field / scalar parsing
/// =======================

fn fr_from_bytes(bytes: [u8; 32]) -> WasmResult<Fr> {
    Fr::from_repr(bytes)
        .into_option()
        .ok_or(Error::SaplingInvalidRandomness)
}

fn scalar_from_bytes(bytes: [u8; 32]) -> WasmResult<Scalar> {
    Scalar::from_repr(bytes)
        .into_option()
        .ok_or(Error::SaplingInvalidAuthPath)
}

fn extended_from_bytes(bytes: [u8; 32]) -> WasmResult<jubjub::ExtendedPoint> {
    jubjub::ExtendedPoint::from_bytes(&bytes)
        .into_option()
        .ok_or(Error::InvalidPointEncoding)
}

pub fn parse_sapling_output(bytes: &[u8]) -> WasmResult<Output> {
    let bytes = output_from_bytes(bytes)?;
    Ok(Output {
        value_commitment_opening: Some(ValueCommitmentOpening {
            value: bytes.value,
            randomness: fr_from_bytes(bytes.randomness)?,
        }),
        recipient_address_diversify_hash: Some(extended_from_bytes(
            bytes.recipient_address_diversify_hash,
        )?),
        recipient_address_pk_d: Some(extended_from_bytes(bytes.recipient_address_pk_d)?),
        esk: Some(fr_from_bytes(bytes.esk)?),
        commitment_randomness: Some(fr_from_bytes(bytes.commitment_randomness)?),
    })
}

pub fn parse_sapling_spend(bytes: &[u8]) -> WasmResult<Spend> {
    let bytes = spend_from_bytes(bytes)?;
    let mut auth_path = Vec::with_capacity(MAX_AUTH_PATH);

    for i in 0..MAX_AUTH_PATH {
        let scalar = scalar_from_bytes(bytes.auth_path[i])?;
        let flag = bytes.auth_path_pos[i] != 0;
        auth_path.push(Some((scalar, flag)));
    }

    Ok(Spend {
        value_commitment_opening: Some(ValueCommitmentOpening {
            value: bytes.value,
            randomness: fr_from_bytes(bytes.randomness)?,
        }),
        ak: Some(extended_from_bytes(bytes.ak)?),
        nsk: Some(fr_from_bytes(bytes.nsk)?),
        payment_address_diversify_hash: Some(extended_from_bytes(
            bytes.payment_address_diversify_hash,
        )?),
        anchor: Some(scalar_from_bytes(bytes.anchor)?),
        ar: Some(fr_from_bytes(bytes.ar)?),
        auth_path,
        commitment_randomness: Some(fr_from_bytes(bytes.commitment_randomness)?),
    })
}

pub fn parse_spend_verify(bytes: &[u8]) -> WasmResult<SpendVerify> {
    // Parse raw bytes into your intermediate struct
    let bytes = spend_verify_from_bytes(bytes)?;

    // Collect scalars into a Vec first
    let mut vec_inputs = Vec::with_capacity(MAX_SPEND_VERIFY_INPUTS);
    for i in 0..MAX_SPEND_VERIFY_INPUTS {
        let scalar = scalar_from_bytes(bytes.public_inputs[i])?;
        vec_inputs.push(scalar);
    }

    // Convert Vec<T> → [T; N] using TryInto
    let public_inputs: [Scalar; MAX_SPEND_VERIFY_INPUTS] =
        vec_inputs.try_into().map_err(|_| Error::InvalidLength)?;

    Ok(SpendVerify {
        proof: bytes.proof,
        public_inputs,
    })
}

pub fn parse_output_verify(bytes: &[u8]) -> WasmResult<OutputVerify> {
    // Parse raw bytes into your intermediate struct
    let bytes = output_verify_from_bytes(bytes)?;

    // Collect scalars into a Vec first
    let mut vec_inputs = Vec::with_capacity(MAX_OUTPUT_VERIFY_INPUTS);
    for i in 0..MAX_OUTPUT_VERIFY_INPUTS {
        let scalar = scalar_from_bytes(bytes.public_inputs[i])?;
        vec_inputs.push(scalar);
    }

    // Convert Vec<T> → [T; N] using TryInto
    let public_inputs: [Scalar; MAX_OUTPUT_VERIFY_INPUTS] =
        vec_inputs.try_into().map_err(|_| Error::InvalidLength)?;

    Ok(OutputVerify {
        proof: bytes.proof,
        public_inputs,
    })
}
