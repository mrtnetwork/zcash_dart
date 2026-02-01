use crate::{
    error::Error,
    io_parameters::{
        get_or_init_orchard_pk, get_or_init_output_params, get_or_init_spend_params,
        get_output_params, get_spend_params, LIB_VERSION,
    },
    orchard::{create_orchard_proof, verify_orchard_proof},
    sapling::{
        params::{
            parse_output_verify, parse_sapling_output, parse_sapling_spend, parse_spend_verify,
        },
        prover::{OutputProver, SpendProver},
        SaplingOutputProver, SaplingSpendProver,
    },
};
use rand_core::OsRng;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct JsOutputData {
    bytes: Vec<u8>,
    code: u32,
}

#[wasm_bindgen]
impl JsOutputData {
    #[wasm_bindgen(getter)]
    pub fn bytes(&self) -> Vec<u8> {
        self.bytes.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn code(&self) -> u32 {
        self.code
    }
}

#[wasm_bindgen]
pub fn process_wasm(input: u32, payload: &[u8]) -> JsOutputData {
    let result: Result<Vec<u8>, Error> = (|| match input {
        u32::MAX => Ok(vec![LIB_VERSION]),
        1 => {
            get_or_init_spend_params(payload)?;
            Ok(vec![0])
        }
        2 => {
            get_or_init_output_params(payload)?;
            Ok(vec![0])
        }
        3 => {
            let circuit = parse_sapling_spend(payload)?;
            let spend_params = get_spend_params()?;
            let mut rng = OsRng;
            let prover = SaplingSpendProver { spend_params };
            let proof = prover.create_proof(circuit, &mut rng);
            let encoded = SaplingSpendProver::encode_proof(proof);
            Ok(encoded.to_vec())
        }
        4 => {
            let circuit = parse_sapling_output(payload)?;
            let output_params = get_output_params()?;
            let prover = SaplingOutputProver { output_params };
            let mut rng = OsRng;
            let proof = prover.create_proof(circuit, &mut rng);
            let encoded = SaplingOutputProver::encode_proof(proof);
            Ok(encoded.to_vec())
        }

        5 => {
            let circuit = parse_output_verify(payload)?;
            let output_params = get_output_params()?;
            let prover = SaplingOutputProver { output_params };
            let proof = prover.parse_proof(circuit.proof)?;
            let verify = prover.verify(&proof, &circuit.public_inputs[..]);
            Ok(vec![verify.into()])
        }
        6 => {
            let circuit = parse_spend_verify(payload)?;
            let spend_params = get_spend_params()?;
            let prover = SaplingSpendProver { spend_params };
            let proof = prover.parse_proof(circuit.proof)?;
            let verify = prover.verify(&proof, &circuit.public_inputs[..]);
            Ok(vec![verify.into()])
        }
        8 => {
            let pk = get_or_init_orchard_pk()?;
            let verify = verify_orchard_proof(pk, payload)?;
            Ok(vec![verify.into()])
        }
        9 => {
            let pk = get_or_init_orchard_pk()?;
            create_orchard_proof(pk, payload)
        }
        10 => {
            let spend_params = get_spend_params();
            Ok(vec![spend_params.is_ok().into()])
        }
        11 => {
            let output_params = get_output_params();
            Ok(vec![output_params.is_ok().into()])
        }
        _ => Err(Error::UnknowRequestId),
    })();
    match result {
        Ok(bytes) => JsOutputData {
            bytes,
            code: Error::Ok as u32,
        },
        Err(err) => JsOutputData {
            bytes: vec![],
            code: err as u32,
        },
    }
}
