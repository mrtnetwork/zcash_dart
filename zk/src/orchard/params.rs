use ff::PrimeField;
use orchard::{
    builder::SpendInfo,
    circuit::Circuit,
    keys::FullViewingKey,
    note::{RandomSeed, Rho},
    tree::{MerkleHashOrchard, MerklePath},
    value::{NoteValue, ValueCommitTrapdoor},
    Address, Note,
};
use pasta_curves::{pallas, vesta};

use crate::{error::Error, sapling::params::WasmResult};

/// Fixed-size Spend struct for byte transfer
#[repr(C, packed)]
#[derive(Clone, Copy, Debug)]
pub struct SpendBytes {
    pub fvk: [u8; 96],
    pub recipient: [u8; 43],
    pub value: u64,
    pub rho: [u8; 32],
    pub rseed: [u8; 32],
    pub position: u32,
    pub auth_path: [[u8; 32]; 32],

    pub out_recipient: [u8; 43],
    pub out_value: u64,
    pub out_rho: [u8; 32],
    pub out_rseed: [u8; 32],
    pub alpha: [u8; 32],
    pub rcv: [u8; 32],

    pub instances: [[u8; 32]; 9],
}

fn fvk_from_bytes(bytes: [u8; 96]) -> WasmResult<FullViewingKey> {
    FullViewingKey::from_bytes(&bytes).ok_or(Error::OrchardInvalidFvk)
}

fn recipient_from_bytes(bytes: [u8; 43]) -> WasmResult<Address> {
    Address::from_raw_address_bytes(&bytes)
        .into_option()
        .ok_or(Error::OrchardInvalidAddress)
}

fn rho_from_bytes(bytes: [u8; 32]) -> WasmResult<Rho> {
    Rho::from_bytes(&bytes)
        .into_option()
        .ok_or(Error::OrchardInvalidRho)
}

fn value_from_raw(value: u64) -> NoteValue {
    NoteValue::from_raw(value)
}

fn rseed_from_bytes(bytes: [u8; 32], rho: &Rho) -> WasmResult<RandomSeed> {
    RandomSeed::from_bytes(bytes, rho)
        .into_option()
        .ok_or(Error::OrchardInvalidRseed)
}

fn auth_path_from_bytes(bytes: [[u8; 32]; 32]) -> WasmResult<[MerkleHashOrchard; 32]> {
    bytes
        .map(|b| {
            MerkleHashOrchard::from_bytes(&b)
                .into_option()
                .ok_or(Error::OrchardInvalidAuthPath)
        })
        .into_iter()
        .collect::<Result<Vec<_>, _>>()?
        .try_into()
        .map_err(|_| Error::OrchardInvalidAuthPath)
}

fn merkle_path_from_bytes(bytes: [[u8; 32]; 32], position: u32) -> WasmResult<MerklePath> {
    let auth_path = auth_path_from_bytes(bytes)?;
    Ok(MerklePath::from_parts(position, auth_path))
}

fn vesta_scalar_from_bytes(bytes: [u8; 32]) -> WasmResult<vesta::Scalar> {
    vesta::Scalar::from_repr(bytes)
        .into_option()
        .ok_or(Error::OrchardInvalidScalar)
}

fn pallas_scalar_from_bytes(bytes: [u8; 32]) -> WasmResult<pallas::Scalar> {
    pallas::Scalar::from_repr(bytes)
        .into_option()
        .ok_or(Error::OrchardInvalidScalar)
}

fn instances_from_bytes(bytes: [[u8; 32]; 9]) -> WasmResult<[vesta::Scalar; 9]> {
    bytes
        .map(vesta_scalar_from_bytes)
        .into_iter()
        .collect::<Result<Vec<_>, _>>()?
        .try_into()
        .map_err(|_| Error::OrchardInvalidScalar)
}

fn build_orchard_circuit(spend: &SpendBytes) -> WasmResult<(Circuit, [[vesta::Scalar; 9]; 1])> {
    let fvk = fvk_from_bytes(spend.fvk)?;
    let recipient = recipient_from_bytes(spend.recipient)?;
    let value = value_from_raw(spend.value);
    let rho = rho_from_bytes(spend.rho)?;
    let rseed = rseed_from_bytes(spend.rseed, &rho)?;
    let note = Note::from_parts(recipient, value, rho, rseed)
        .into_option()
        .ok_or(Error::OrchardInvalidNote)?;

    let merkle_path = merkle_path_from_bytes(spend.auth_path, spend.position)?;

    let out_recipient = recipient_from_bytes(spend.out_recipient)?;
    let out_value = value_from_raw(spend.out_value);
    let out_rho = rho_from_bytes(spend.out_rho)?;
    let out_rseed = rseed_from_bytes(spend.out_rseed, &out_rho)?;
    let output_note = Note::from_parts(out_recipient, out_value, out_rho, out_rseed)
        .into_option()
        .ok_or(Error::OrchardInvalidNote)?;

    let alpha = pallas_scalar_from_bytes(spend.alpha)?;
    let rcv = ValueCommitTrapdoor::from_bytes(spend.rcv)
        .into_option()
        .ok_or(Error::OrchardInvalidCommitment)?;

    let spend_info = SpendInfo::new(fvk, note, merkle_path).ok_or(Error::OrchardInvalidSpend)?;

    let instances = instances_from_bytes(spend.instances)?;

    let circuit = Circuit::from_action_context(spend_info, output_note, alpha, rcv)
        .ok_or(Error::OrchardInvalidCircuit)?;

    Ok((circuit, [instances]))
}

pub fn parse_orchard_spends(
    bytes: &[u8],
) -> WasmResult<(Vec<Circuit>, Vec<[[vesta::Scalar; 9]; 1]>)> {
    let circuit_bytes = parse_circuit_bytes(bytes)?;

    let mut circuits = Vec::with_capacity(circuit_bytes.circuits.len());
    let mut instances = Vec::with_capacity(circuit_bytes.circuits.len());

    for spend in &circuit_bytes.circuits {
        let (circuit, instance) = build_orchard_circuit(spend)?;
        circuits.push(circuit);
        instances.push(instance);
    }

    Ok((circuits, instances))
}

pub struct OrchardProof {
    pub proof: Vec<u8>,
    pub instances: Vec<[[vesta::Scalar; 9]; 1]>,
}

pub fn parse_orchard_proof(bytes: &[u8]) -> Result<OrchardProof, Error> {
    use core::convert::TryInto;

    let mut offset = 0;

    // ---- proof length ----
    if bytes.len() < offset + 4 {
        return Err(Error::InvalidLength);
    }

    let proof_len = u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize;
    offset += 4;

    // ---- proof bytes ----
    if bytes.len() < offset + proof_len {
        return Err(Error::InvalidLength);
    }

    let proof = bytes[offset..offset + proof_len].to_vec();
    offset += proof_len;

    // ---- instance count ----
    if bytes.len() < offset + 4 {
        return Err(Error::InvalidLength);
    }

    let instance_count = u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize;
    offset += 4;

    // ---- instances ----
    let mut instances = Vec::with_capacity(instance_count);

    for _ in 0..instance_count {
        let mut scalars = [vesta::Scalar::zero(); 9];

        for i in 0..9 {
            if bytes.len() < offset + 32 {
                return Err(Error::InvalidLength);
            }
            let scalar_bytes: [u8; 32] = bytes[offset..offset + 32].try_into().unwrap();
            scalars[i] = vesta_scalar_from_bytes(scalar_bytes)?;
            offset += 32;
        }

        instances.push([scalars]);
    }

    // ---- extra bytes check (optional but recommended) ----
    if offset != bytes.len() {
        return Err(Error::InvalidLength);
    }

    Ok(OrchardProof { proof, instances })
}

// #[repr(C)]
// #[derive(Clone, Copy, Debug)]
// pub struct OrchardProofHeader {
//     pub proof_len: u32,

//     pub instances_outer_len: u32,
//     pub instances_middle_len: u32,
//     pub instances_inner_len: u32,
// }

// pub fn parse_orchard_proof_payload(
//     bytes: &[u8],
// ) -> WasmResult<(Vec<u8>, Vec<Vec<Vec<vesta::Scalar>>>)> {
//     use core::{mem::size_of, ptr};

//     if bytes.len() < size_of::<OrchardProofHeader>() {
//         return Err(Error::InvalidLength);
//     }

//     // Read header
//     let header = unsafe { ptr::read_unaligned(bytes.as_ptr() as *const OrchardProofHeader) };

//     let mut offset = size_of::<OrchardProofHeader>();

//     let proof_len = header.proof_len as usize;
//     let o = header.instances_outer_len as usize;
//     let m = header.instances_middle_len as usize;
//     let i = header.instances_inner_len as usize;

//     // ---- proof bytes ----
//     if bytes.len() < offset + proof_len {
//         return Err(Error::InvalidLength);
//     }

//     let proof_bytes = bytes[offset..offset + proof_len].to_vec();
//     offset += proof_len;

//     // ---- instances ----
//     let total_scalars = o
//         .checked_mul(m)
//         .and_then(|v| v.checked_mul(i))
//         .ok_or(Error::InvalidLength)?;

//     let total_bytes = total_scalars.checked_mul(32).ok_or(Error::InvalidLength)?;

//     if bytes.len() < offset + total_bytes {
//         return Err(Error::InvalidLength);
//     }

//     let mut instances = Vec::with_capacity(o);

//     for _ in 0..o {
//         let mut mid = Vec::with_capacity(m);
//         for _ in 0..m {
//             let mut inner = Vec::with_capacity(i);
//             for _ in 0..i {
//                 let chunk: [u8; 32] = bytes[offset..offset + 32].try_into().unwrap();
//                 offset += 32;
//                 inner.push(vesta_scalar_from_bytes(chunk)?);
//             }
//             mid.push(inner);
//         }
//         instances.push(mid);
//     }

//     Ok((proof_bytes, instances))
// }

pub struct CircuitBytes {
    pub circuits: Vec<SpendBytes>,
}

pub fn parse_circuit_bytes(bytes: &[u8]) -> WasmResult<CircuitBytes> {
    use core::mem::size_of;

    if bytes.len() < 4 {
        return Err(Error::InvalidLength);
    }

    // ---- read count ----
    let count = u32::from_le_bytes(bytes[0..4].try_into().unwrap()) as usize;

    let spend_size = size_of::<SpendBytes>();
    let expected_len = 4 + count.checked_mul(spend_size).ok_or(Error::InvalidLength)?;

    if bytes.len() != expected_len {
        return Err(Error::InvalidLength);
    }

    let mut offset = 4;
    let mut circuits = Vec::with_capacity(count);

    for _ in 0..count {
        let chunk = &bytes[offset..offset + spend_size];

        let spend = unsafe { core::ptr::read_unaligned(chunk.as_ptr() as *const SpendBytes) };

        circuits.push(spend);
        offset += spend_size;
    }

    Ok(CircuitBytes { circuits })
}
