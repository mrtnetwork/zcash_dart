#[macro_use]
extern crate alloc;

use rand_core::OsRng;

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

pub mod error;
pub mod ffi;
pub mod io_parameters;
pub mod orchard;
pub mod sapling;
pub mod wasm;
#[derive(Clone)]
pub struct OutputData {
    pub bytes: Vec<u8>,
    pub code: u32,
}

/// Core processing
pub fn process_core(id: u32, payload: &[u8]) -> OutputData {
    let result: Result<Vec<u8>, Error> = (|| match id {
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
        Ok(bytes) => OutputData {
            bytes,
            code: Error::Ok as u32, // 0
        },
        Err(err) => OutputData {
            bytes: vec![0],
            code: err as u32, // non-zero error code
        },
    }
}
