use halo2_proofs::{
    plonk::{self, SingleVerifier},
    transcript::{Blake2bRead, Blake2bWrite},
};
use orchard::circuit::Circuit;
use pasta_curves::vesta;
use rand_core::OsRng;
// use redjubjub::VerificationKey;

use crate::{
    error::Error,
    orchard::params::{parse_orchard_proof, parse_orchard_spends},
    sapling::params::WasmResult,
};
pub mod params;
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

pub fn create_orchard_proof(pk: &'static ProvingKey, payload: &[u8]) -> WasmResult<Vec<u8>> {
    let (circuits, instances_arr) = parse_orchard_spends(payload)?;

    let mut transcript = Blake2bWrite::<_, vesta::Affine, _>::init(vec![]);

    // Pre-allocate storage for instance rows
    let mut instance_rows: Vec<[&[vesta::Scalar]; 1]> = Vec::with_capacity(instances_arr.len());

    for inst in &instances_arr {
        // inst: [[Scalar; 9]; 1]
        let row: &[vesta::Scalar] = &inst[0];

        // Store a 1-element array per circuit
        instance_rows.push([row]);
    }

    // Now build &[&[&[Scalar]]] from stable storage
    let instance_refs: Vec<&[&[vesta::Scalar]]> = instance_rows.iter().map(|r| &r[..]).collect();

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
    .map_err(|_| Error::OrchardProofCreationFailed)?;

    Ok(transcript.finalize())
}

pub fn verify_orchard_proof(pk: &'static ProvingKey, payload: &[u8]) -> WasmResult<bool> {
    let proof = parse_orchard_proof(payload)?;
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
