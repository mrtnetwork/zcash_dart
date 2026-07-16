#[macro_use]
extern crate alloc;

use wasm_bindgen::prelude::wasm_bindgen;

use crate::{controller::ZKCONTROLLER, error::Error};

pub mod controller;
pub mod error;
pub mod ffi;
pub mod logging;
pub mod map;
pub mod merkle;
pub mod orchard;
pub mod request;
pub mod response;
pub mod sapling;
#[wasm_bindgen]
pub fn setup_sapling_spend_params_inner(payload: &[u8]) -> u32 {
    ZKCONTROLLER
        .setup_sapling_spend_params_inner(payload)
        .map(|_| 0)
        .unwrap_or_else(|e| e.code as u32)
}
#[wasm_bindgen]
pub fn setup_sapling_output_params_inner(payload: &[u8]) -> u32 {
    ZKCONTROLLER
        .setup_sapling_output_params_inner(payload)
        .map(|_| 0)
        .unwrap_or_else(|e| e.code as u32)
}

pub fn new_request_inner(payload: &[u8]) -> Result<Vec<u8>, Error> {
    ZKCONTROLLER.do_request(payload.into())
}

#[wasm_bindgen]
pub struct ZKResponseWasm {
    bytes: Vec<u8>,
    code: u32,
}
#[wasm_bindgen]
pub fn new_request(payload: &[u8]) -> ZKResponseWasm {
    ZKCONTROLLER
        .do_request(payload.into())
        .map(|e| ZKResponseWasm { bytes: e, code: 0 })
        .unwrap_or_else(|e| ZKResponseWasm {
            bytes: Vec::new(),
            code: e as u32,
        })
}
#[wasm_bindgen]
impl ZKResponseWasm {
    #[wasm_bindgen(getter)]
    pub fn bytes(&self) -> Vec<u8> {
        self.bytes.clone()
    }

    #[wasm_bindgen(getter)]
    pub fn code(&self) -> u32 {
        self.code
    }
}
