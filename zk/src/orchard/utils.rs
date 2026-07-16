use std::sync::Arc;

use ff::PrimeField;
use group::GroupEncoding;
use halo2_gadgets::{poseidon::primitives as poseidon, sinsemilla::primitives as sinsemilla};
use halo2_proofs::{
    plonk::{self, SingleVerifier},
    transcript::{Blake2bRead, Blake2bWrite},
};

use incrementalmerkletree::Hashable;
use minicbor::bytes::ByteArray;
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
use rand_core::OsRng;

use crate::{
    error::{enc_err, hash_err, input_err, key_err, RuntimeError, ZKError},
    orchard::types::{
        OrchardProof, OrchardProofInputs, OrchardProofParams, OrchardVerifyProofParams,
    },
};
pub const COMMIT_IVK_PERSONALIZATION: &str = "z.cash:Orchard-CommitIvk";

pub struct ProvingKey {
    params: halo2_proofs::poly::commitment::Params<vesta::Affine>,
    pk: plonk::ProvingKey<vesta::Affine>,
}

impl ProvingKey {
    /// Builds the proving key.
    pub fn build() -> Self {
        let params = halo2_proofs::poly::commitment::Params::new(11);
        let circuit: Circuit = Default::default();

        let vk = plonk::keygen_vk(&params, &circuit).unwrap();
        let pk = plonk::keygen_pk(&params, vk, &circuit).unwrap();

        ProvingKey { params, pk }
    }
}

pub struct ZKOrchardUtils;

impl ZKOrchardUtils {
    pub fn fvk_from_bytes(bytes: [u8; 96]) -> ZKError<FullViewingKey> {
        FullViewingKey::from_bytes(&bytes)
            .ok_or_else(|| key_err("fvk", "invalid encoding (expected 96 bytes)"))
    }

    pub fn recipient_from_bytes(bytes: [u8; 43]) -> ZKError<Address> {
        Address::from_raw_address_bytes(&bytes)
            .into_option()
            .ok_or_else(|| key_err("recipient", "invalid address encoding"))
    }

    pub fn rho_from_bytes(bytes: [u8; 32]) -> ZKError<Rho> {
        Rho::from_bytes(&bytes)
            .into_option()
            .ok_or_else(|| key_err("rho", "invalid encoding"))
    }

    pub fn value_from_raw(value: u64) -> NoteValue {
        NoteValue::from_raw(value)
    }

    pub fn rseed_from_bytes(bytes: [u8; 32], rho: &Rho) -> ZKError<RandomSeed> {
        RandomSeed::from_bytes(bytes, rho)
            .into_option()
            .ok_or_else(|| key_err("rseed", "invalid seed"))
    }

    pub fn auth_path_from_bytes(bytes: [ByteArray<32>; 32]) -> ZKError<[MerkleHashOrchard; 32]> {
        let mut out = [MerkleHashOrchard::empty_leaf(); 32];

        for (i, b) in bytes.into_iter().enumerate() {
            out[i] = MerkleHashOrchard::from_bytes(&b)
                .into_option()
                .ok_or_else(|| key_err("auth_path", "invalid merkle hash"))?;
        }

        Ok(out)
    }

    pub fn merkle_path_from_bytes(
        bytes: [ByteArray<32>; 32],
        position: u32,
    ) -> ZKError<MerklePath> {
        let auth_path = ZKOrchardUtils::auth_path_from_bytes(bytes)?;
        Ok(MerklePath::from_parts(position, auth_path))
    }

    pub fn vesta_scalar_from_bytes(bytes: ByteArray<32>) -> ZKError<vesta::Scalar> {
        vesta::Scalar::from_repr(bytes.into())
            .into_option()
            .ok_or_else(|| enc_err("vesta_scalar", "invalid scalar encoding"))
    }

    pub fn pallas_scalar_from_bytes(bytes: [u8; 32]) -> ZKError<pallas::Scalar> {
        pallas::Scalar::from_repr(bytes)
            .into_option()
            .ok_or_else(|| enc_err("pallas_scalar", "invalid scalar encoding"))
    }
    pub fn instances_from_bytes(bytes: [ByteArray<32>; 9]) -> ZKError<[vesta::Scalar; 9]> {
        let mut out = [vesta::Scalar::default(); 9];

        for (i, b) in bytes.into_iter().enumerate() {
            out[i] = Self::vesta_scalar_from_bytes(b)?;
        }

        Ok(out)
    }
    pub fn build_circuit(
        params: &OrchardProofInputs,
    ) -> ZKError<(Circuit, [[vesta::Scalar; 9]; 1])> {
        let fvk = ZKOrchardUtils::fvk_from_bytes(params.fvk.into())?;
        let recipient = ZKOrchardUtils::recipient_from_bytes(params.recipient.into())?;
        let value = ZKOrchardUtils::value_from_raw(params.value);
        let rho = ZKOrchardUtils::rho_from_bytes(params.rho.into())?;
        let rseed = ZKOrchardUtils::rseed_from_bytes(params.rseed.into(), &rho)?;
        let note = Note::from_parts(recipient, value, rho, rseed)
            .into_option()
            .ok_or_else(|| input_err("note", "failed to construct note"))?;

        let merkle_path =
            ZKOrchardUtils::merkle_path_from_bytes(params.auth_path.into(), params.position)?;

        let out_recipient = ZKOrchardUtils::recipient_from_bytes(params.out_recipient.into())?;
        let out_value = ZKOrchardUtils::value_from_raw(params.out_value);
        let out_rho = ZKOrchardUtils::rho_from_bytes(params.out_rho.into())?;
        let out_rseed = ZKOrchardUtils::rseed_from_bytes(params.out_rseed.into(), &out_rho)?;
        let output_note = Note::from_parts(out_recipient, out_value, out_rho, out_rseed)
            .into_option()
            .ok_or(input_err("output_note", "failed to construct note"))?;

        let alpha = ZKOrchardUtils::pallas_scalar_from_bytes(params.alpha.into())?;
        let rcv = ValueCommitTrapdoor::from_bytes(params.rcv.into())
            .into_option()
            .ok_or(input_err("rcv", "failed to construct ValueCommitTrapdoor"))?;

        let spend_info = SpendInfo::new(fvk, note, merkle_path)
            .ok_or_else(|| input_err("spend_info", "invalid spend construction"))?;

        let instances = ZKOrchardUtils::instances_from_bytes(params.instances.into())?;

        let circuit = Circuit::from_action_context(spend_info, output_note, alpha, rcv)
            .ok_or_else(|| input_err("circuit", "failed to build circuit"))?;

        Ok((circuit, [instances]))
    }
    pub fn create_orchard_proof(
        pk: Arc<ProvingKey>,
        circuit_bytes: OrchardProofParams,
    ) -> ZKError<Vec<u8>> {
        // let (circuits, instances_arr) = parse_orchard_spends(payload)?;

        let mut circuits = Vec::with_capacity(circuit_bytes.circuits.len());
        let mut instances = Vec::with_capacity(circuit_bytes.circuits.len());

        for spend in &circuit_bytes.circuits {
            let (circuit, instance) = ZKOrchardUtils::build_circuit(spend)?;
            circuits.push(circuit);
            instances.push(instance);
        }

        let mut transcript = Blake2bWrite::<_, vesta::Affine, _>::init(vec![]);

        // Pre-allocate storage for instance rows
        let mut instance_rows: Vec<[&[vesta::Scalar]; 1]> = Vec::with_capacity(instances.len());

        for inst in &instances {
            // inst: [[Scalar; 9]; 1]
            let row: &[vesta::Scalar] = &inst[0];

            // Store a 1-element array per circuit
            instance_rows.push([row]);
        }

        // Now build &[&[&[Scalar]]] from stable storage
        let instance_refs: Vec<&[&[vesta::Scalar]]> =
            instance_rows.iter().map(|r| &r[..]).collect();

        let instances: &[&[&[vesta::Scalar]]] = &instance_refs;

        let rng = OsRng;

        plonk::create_proof(
            &pk.params,
            &pk.pk,
            &circuits,
            instances,
            rng,
            &mut transcript,
        )
        .map_err(|e| RuntimeError::proof(e.to_string()))?;

        Ok(transcript.finalize())
    }
    pub fn parse_proof_bytes(p: OrchardVerifyProofParams) -> ZKError<OrchardProof> {
        let proof = p.proof;

        let instances: Vec<[[vesta::Scalar; 9]; 1]> = p
            .instances
            .into_iter()
            .map(|row| -> Result<[[vesta::Scalar; 9]; 1], RuntimeError> {
                let mut out = [vesta::Scalar::default(); 9];

                for (i, b) in row.into_iter().enumerate() {
                    out[i] = ZKOrchardUtils::vesta_scalar_from_bytes(b.into())?;
                }

                Ok([out]) // <-- THIS is the missing layer
            })
            .collect::<Result<Vec<_>, _>>()?;

        Ok(OrchardProof { proof, instances })
    }
    pub fn verify_orchard_proof(
        pk: Arc<ProvingKey>,
        payload: OrchardVerifyProofParams,
    ) -> ZKError<bool> {
        let proof = ZKOrchardUtils::parse_proof_bytes(payload)?;
        let vk = pk.pk.get_vk();
        let params = &pk.params;
        let strategy = SingleVerifier::new(&params);

        let mut transcript = Blake2bRead::init(&proof.proof[..]);

        // 2. Convert owned instances → borrowed refs
        let instances_refs: Vec<&[&[vesta::Scalar]]> = proof
            .instances
            .iter()
            .map(|outer| {
                let inner: Vec<&[vesta::Scalar]> = outer.iter().map(|v| v.as_slice()).collect();
                let leaked: &mut [&[vesta::Scalar]] = inner.leak();
                let immut: &[&[vesta::Scalar]] = leaked;
                immut
            })
            .collect();

        // 3. Final shape required by PLONK
        let instances: &[&[&[vesta::Scalar]]] = &instances_refs;
        let result = plonk::verify_proof(params, vk, strategy, instances, &mut transcript);
        Ok(result.is_ok())
    }
    pub fn prf_nf(nk: ByteArray<32>, rho: ByteArray<32>) -> ZKError<[u8; 32]> {
        let nk_p = ZKOrchardUtils::vesta_scalar_from_bytes(nk)?;
        let rho_p = ZKOrchardUtils::vesta_scalar_from_bytes(rho)?;
        let hash =
            poseidon::Hash::<_, poseidon::P128Pow5T3, poseidon::ConstantLength<2>, 3, 2>::init()
                .hash([nk_p, rho_p]);
        Ok(hash.to_repr())
    }

    pub fn sinsemilla_short_commit(
        domain: String,
        bits: Vec<bool>,
        r: ByteArray<32>,
    ) -> ZKError<[u8; 32]> {
        let iter = bits.into_iter();
        let rivk_p = ZKOrchardUtils::pallas_scalar_from_bytes(r.into())?;
        let domain = sinsemilla::CommitDomain::new(domain.as_str());
        domain
            .short_commit(iter, &rivk_p)
            .into_option()
            .ok_or_else(|| hash_err("commit_domain", "commit failed."))
            .map(|e| e.to_repr())
    }
    pub fn sinsemilla_commit(
        domain: String,
        bits: Vec<bool>,
        r: ByteArray<32>,
    ) -> ZKError<[u8; 32]> {
        let iter = bits.into_iter();
        let rivk_p = ZKOrchardUtils::pallas_scalar_from_bytes(r.into())?;
        let domain = sinsemilla::CommitDomain::new(domain.as_str());
        domain
            .commit(iter, &rivk_p)
            .into_option()
            .ok_or_else(|| hash_err("commit_domain", "commit failed."))
            .map(|e| e.to_bytes())
    }
}
