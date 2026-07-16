use crate::error::{Error, RuntimeError, ZKError};
use crate::logging::{disable_logging, enable_logging};
use crate::merkle::types::{ChainMerkleState, ShieldProtocol};
use crate::orchard::types::{
    CommitmentDomain, CommitmentShortDomain, OrchardProofParams, OrchardVerifyProofParams,
    PseudoRando,
};
use crate::orchard::utils::{ProvingKey, ZKOrchardUtils};
use crate::request::ZKRequest;
use crate::response::ZKResponse;
use crate::sapling::circuit::{OutputParameters, SpendParameters};
use crate::sapling::prover::{OutputProver, SpendProver};
use crate::sapling::types::{
    PedersenHash, SaplingOutputBytes, SaplingOutputVerificationBytes, SaplingSpendBytes,
    SaplingSpendVerificationBytes,
};
use crate::sapling::utils::ZKSaplingUtils;
use crate::sapling::{SaplingOutputProver, SaplingSpendProver};
use crate::{map::PlatformMap, merkle::context::MerkleContext};
use log::debug;
use once_cell::sync::Lazy;
use rand_core::OsRng;
use std::io::Cursor;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::sync::{atomic::AtomicU32, RwLock};
pub static ZKCONTROLLER: Lazy<ZKController> = Lazy::new(|| ZKController::new());
pub struct ZKController {
    context: PlatformMap<u32, Arc<RwLock<MerkleContext>>>,
    next_id: AtomicU32,

    spend_params: RwLock<Option<Arc<SpendParameters>>>,
    output_params: RwLock<Option<Arc<OutputParameters>>>,
    orchard_pk: RwLock<Option<Arc<ProvingKey>>>,
}
impl ZKController {
    pub fn new() -> Self {
        ZKController {
            context: PlatformMap::new(),
            next_id: AtomicU32::new(1),
            spend_params: RwLock::new(None),
            output_params: RwLock::new(None),
            orchard_pk: RwLock::new(None),
        }
    }
    pub fn get_spend_params_inner(&self) -> ZKError<Arc<SpendParameters>> {
        let guard = self.spend_params.read().unwrap_or_else(|e| e.into_inner());
        match &*guard {
            Some(p) => Ok(Arc::clone(p)),
            None => Err(RuntimeError {
                code: Error::Missing,
                msg: "Missing sapling spend parameters.".to_string(),
            }),
        }
    }
    pub fn get_output_params_inner(&self) -> ZKError<Arc<OutputParameters>> {
        let guard = self.output_params.read().unwrap_or_else(|e| e.into_inner());
        match &*guard {
            Some(p) => Ok(Arc::clone(p)),
            None => Err(RuntimeError {
                code: Error::Missing,
                msg: "Missing sapling output parameters.".to_string(),
            }),
        }
    }

    pub fn has_output_params_inner(&self) -> ZKError<bool> {
        let has_params = self
            .output_params
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .is_some();
        Ok(has_params)
    }
    pub fn has_spend_params_inner(&self) -> ZKError<bool> {
        let has_params = self
            .spend_params
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .is_some();
        Ok(has_params)
    }

    pub fn has_spend_params(&self) -> ZKError<ZKResponse> {
        self.has_spend_params_inner()
            .map(|has_params| ZKResponse::SaplingHasParams(has_params))
    }
    pub fn has_output_params(&self) -> ZKError<ZKResponse> {
        self.has_output_params_inner()
            .map(|has_params| ZKResponse::SaplingHasParams(has_params))
    }

    pub fn get_or_create_proving_key(&self) -> ZKError<Arc<ProvingKey>> {
        let mut guard = self.orchard_pk.write().unwrap_or_else(|e| e.into_inner());

        if let Some(pk) = &*guard {
            return Ok(pk.clone());
        }

        let pk = Arc::new(ProvingKey::build());

        *guard = Some(pk.clone());

        Ok(pk)
    }
    pub fn setup_sapling_spend_params_inner(&self, payload: &[u8]) -> ZKError<ZKResponse> {
        self.has_spend_params_inner().and_then(|has_params| {
            if has_params {
                return Ok(ZKResponse::Ok());
            }
            let reader = Cursor::new(payload);
            let params = SpendParameters::read(reader, false).map_err(|e| RuntimeError {
                code: Error::InvalidInput,
                msg: e.to_string(),
            })?;
            *self.spend_params.write().unwrap_or_else(|e| e.into_inner()) = Some(Arc::new(params));

            Ok(ZKResponse::Ok())
        })
    }
    pub fn setup_sapling_output_params_inner(&self, payload: &[u8]) -> ZKError<ZKResponse> {
        self.has_output_params_inner().and_then(|has_params| {
            if has_params {
                return Ok(ZKResponse::Ok());
            }
            let reader = Cursor::new(payload);
            let params = OutputParameters::read(reader, false).map_err(|e| RuntimeError {
                code: Error::InvalidInput,
                msg: e.to_string(),
            })?;
            *self
                .output_params
                .write()
                .unwrap_or_else(|e| e.into_inner()) = Some(Arc::new(params));

            Ok(ZKResponse::Ok())
        })
    }

    pub fn create_sapling_spend_proof(&self, params: SaplingSpendBytes) -> ZKError<ZKResponse> {
        let circuit = ZKSaplingUtils::parse_sapling_spend_proof(params)?;

        let spend_params = self.get_spend_params_inner()?; // Arc clone (cheap)
        let mut rng = OsRng;
        let prover = SaplingSpendProver { spend_params };

        let proof = prover.create_proof(circuit, &mut rng);

        let encoded = SaplingSpendProver::encode_proof(proof);

        Ok(ZKResponse::SaplingProof(encoded))
    }
    pub fn verify_sapling_spend_proof(
        &self,
        params: SaplingSpendVerificationBytes,
    ) -> ZKError<ZKResponse> {
        let circuit = ZKSaplingUtils::parse_sapling_spend_verification(params)?;

        let spend_params = self.get_spend_params_inner()?; // Arc clone (cheap)
        let prover = SaplingSpendProver { spend_params };
        let proof = prover
            .parse_proof(circuit.proof)
            .map_err(|e| RuntimeError {
                code: e,
                msg: "Invalid sapling proof bytes.".to_string(),
            })?;
        let verify = prover.verify(&proof, &circuit.public_inputs[..]);

        Ok(ZKResponse::VerifyProof(verify))
    }

    pub fn create_sapling_output_proof(&self, params: SaplingOutputBytes) -> ZKError<ZKResponse> {
        let circuit = ZKSaplingUtils::parse_sapling_output_proof(params)?;

        let output_params = self.get_output_params_inner()?; // Arc clone (cheap)
        let mut rng = OsRng;
        let prover = SaplingOutputProver { output_params };

        let proof = prover.create_proof(circuit, &mut rng);

        let encoded = SaplingSpendProver::encode_proof(proof);

        Ok(ZKResponse::SaplingProof(encoded))
    }
    pub fn verify_sapling_output_proof(
        &self,
        params: SaplingOutputVerificationBytes,
    ) -> ZKError<ZKResponse> {
        let circuit = ZKSaplingUtils::parse_sapling_output_verification(params)?;
        let output_params = self.get_output_params_inner()?; // Arc clone (cheap)
        let prover = SaplingOutputProver { output_params };
        let proof = prover
            .parse_proof(circuit.proof)
            .map_err(|e| RuntimeError {
                code: e,
                msg: "Invalid sapling proof bytes.".to_string(),
            })?;
        let verify = prover.verify(&proof, &circuit.public_inputs[..]);
        Ok(ZKResponse::VerifyProof(verify))
    }

    pub fn create_orchard_action_proof(&self, params: OrchardProofParams) -> ZKError<ZKResponse> {
        let key = self.get_or_create_proving_key()?;
        let proof = ZKOrchardUtils::create_orchard_proof(key, params)?;
        Ok(ZKResponse::OrchardActionProof(proof))
    }

    pub fn verify_orchard_action_proof(
        &self,
        params: OrchardVerifyProofParams,
    ) -> ZKError<ZKResponse> {
        let key = self.get_or_create_proving_key()?;
        let verify = ZKOrchardUtils::verify_orchard_proof(key, params)?;
        Ok(ZKResponse::VerifyProof(verify))
    }
    pub fn commitment_short_domain(&self, params: CommitmentShortDomain) -> ZKError<ZKResponse> {
        let data = ZKOrchardUtils::sinsemilla_short_commit(params.domain, params.bits, params.r)?;
        Ok(ZKResponse::Bytes(data.into()))
    }
    pub fn commitment_domain(&self, params: CommitmentDomain) -> ZKError<ZKResponse> {
        let data = ZKOrchardUtils::sinsemilla_commit(params.domain, params.bits, params.r)?;
        Ok(ZKResponse::Bytes(data.into()))
    }
    pub fn prf_nf(&self, params: PseudoRando) -> ZKError<ZKResponse> {
        let data = ZKOrchardUtils::prf_nf(params.nk, params.rho)?;
        Ok(ZKResponse::Bytes(data.into()))
    }
    pub fn pedersen_hash(&self, params: PedersenHash) -> ZKError<ZKResponse> {
        let data = ZKSaplingUtils::pedersen_hash(params.bits, params.merkle_tree_size)?;
        Ok(ZKResponse::Bytes(data.into()))
    }
    pub fn clear_sapling_spend_params(&self) -> ZKError<ZKResponse> {
        let mut guard = self.spend_params.write().unwrap_or_else(|e| e.into_inner());

        *guard = None;

        Ok(ZKResponse::Ok())
    }

    pub fn clear_sapling_output_params(&self) -> ZKError<ZKResponse> {
        let mut guard = self
            .output_params
            .write()
            .unwrap_or_else(|e| e.into_inner());

        *guard = None;

        Ok(ZKResponse::Ok())
    }
    pub fn clear_orchard_proving_key(&self) -> ZKError<ZKResponse> {
        let mut guard = self.orchard_pk.write().unwrap_or_else(|e| e.into_inner());

        *guard = None;

        Ok(ZKResponse::Ok())
    }
    pub fn parse_request(&self, payload: Vec<u8>) -> ZKError<ZKRequest> {
        minicbor::decode::<ZKRequest>(&payload).map_err(|e| RuntimeError {
            code: Error::InvalidInput,
            msg: e.to_string(),
        })
    }

    pub fn do_request_inner(&self, payload: Vec<u8>) -> ZKError<ZKResponse> {
        let request = self.parse_request(payload)?;
        debug!("New request {:#?}", request);
        match request {
            ZKRequest::MerkleCreateContext(params) => self.create_merkle_context(params),
            ZKRequest::MerkleUpdateSubtree(id, protocol, subtree) => {
                let context = self.get_context(id)?;
                let protocol: ShieldProtocol = protocol.try_into()?;
                let mut guard = context.write().unwrap_or_else(|e| e.into_inner());
                let index = match protocol {
                    ShieldProtocol::Sapling => guard.update_sapling_subtree(subtree)?,
                    ShieldProtocol::Orchard => guard.update_orchard_subtree(subtree)?,
                };

                Ok(ZKResponse::MerkleUpdateSubtreeResult(index))
            }
            ZKRequest::MerkleCreateWitness(id, params) => {
                let context = self.get_context(id)?;
                let mut guard = context.write().unwrap_or_else(|e| e.into_inner());
                Ok(ZKResponse::MerkleCreateWitnessResult(
                    guard.create_witness(params)?,
                ))
            }
            ZKRequest::MerkleGetContext(id) => {
                let context = self.get_context(id)?;
                let guard = context.read().unwrap_or_else(|e| e.into_inner());
                let state = guard.get_context()?;
                Ok(ZKResponse::MerkleGetContextResult(state))
            }
            ZKRequest::MerkleInsertChainState(id, chain_state) => {
                let context = self.get_context(id)?;
                let mut guard = context.write().unwrap_or_else(|e| e.into_inner());
                guard.insert_chain_state(&chain_state)?;
                Ok(ZKResponse::Ok())
            }
            ZKRequest::MerkleUpdateState(id, blocks_bundles) => {
                let context = self.get_context(id)?;
                let mut guard = context.write().unwrap_or_else(|e| e.into_inner());
                Ok(ZKResponse::MerkleUpdateResult(
                    guard.update_state(blocks_bundles)?,
                ))
            }
            ZKRequest::MerkleMergeState(id, state) => {
                let context = self.get_context(id)?;
                let mut guard = context.write().unwrap_or_else(|e| e.into_inner());
                guard.merge_state(state)?;
                Ok(ZKResponse::Ok())
            }
            ZKRequest::MerkleCloseContext(id) => self.close_context(id),
            ZKRequest::SaplingHasSpendParams() => self.has_spend_params(),
            ZKRequest::SaplingHasOutputParams() => self.has_output_params(),
            ZKRequest::SaplingSetupSpendParams(params) => {
                self.setup_sapling_spend_params_inner(&params)
            }
            ZKRequest::SaplingSetupOutputParams(params) => {
                self.setup_sapling_output_params_inner(&params)
            }
            ZKRequest::SaplingCreateSpendProof(params) => self.create_sapling_spend_proof(params),
            ZKRequest::SaplingCreateOutputProof(params) => self.create_sapling_output_proof(params),
            ZKRequest::SaplingVerifySpendProof(params) => self.verify_sapling_spend_proof(params),
            ZKRequest::SaplingVerifyOutputProof(params) => self.verify_sapling_output_proof(params),
            ZKRequest::OrchardCreateActionProof(params) => self.create_orchard_action_proof(params),
            ZKRequest::OrchardVerifyActionProof(params) => self.verify_orchard_action_proof(params),
            ZKRequest::SaplingClearSpendParams() => self.clear_sapling_spend_params(),
            ZKRequest::SaplingClearOutputParams() => self.clear_sapling_output_params(),
            ZKRequest::SaplingClearOrchardProvingKey() => self.clear_orchard_proving_key(),
            ZKRequest::Version() => Ok(ZKResponse::Version(1)),
            ZKRequest::EnableLogging(enable, mode) => {
                match enable {
                    true => enable_logging(mode),
                    false => disable_logging(),
                }
                Ok(ZKResponse::Ok())
            }
            ZKRequest::CommitmentShortDomain(params) => self.commitment_short_domain(params),
            ZKRequest::CommitmentDomain(params) => self.commitment_domain(params),
            ZKRequest::PseudoRando(params) => self.prf_nf(params),
            ZKRequest::PedersenHash(params) => self.pedersen_hash(params),
        }
    }

    pub fn do_request(&self, payload: Vec<u8>) -> Result<Vec<u8>, Error> {
        // Error::InternalError
        let result = self
            .do_request_inner(payload)
            .unwrap_or_else(|e| ZKResponse::Error(e.code as u32, e.msg));
        debug!("Response {:#?}", result);
        minicbor::to_vec(&result).map_err(|_| Error::Internal)
    }

    pub fn create_merkle_context(&self, params: ChainMerkleState) -> ZKError<ZKResponse> {
        let context = MerkleContext::deserialize(params)?;
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);

        self.context.insert(id, Arc::new(RwLock::new(context)));

        Ok(ZKResponse::MerkleCreateContext(id))
    }
    pub fn get_context(&self, id: u32) -> ZKError<Arc<RwLock<MerkleContext>>> {
        self.context.get(&id).ok_or(RuntimeError {
            code: Error::Missing,
            msg: format!("Context with id {} not found", id),
        })
    }
    pub fn close_context(&self, id: u32) -> ZKError<ZKResponse> {
        self.context.remove(&id);
        Ok(ZKResponse::Ok())
    }
}
