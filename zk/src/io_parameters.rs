use crate::{
    error::Error,
    orchard::ProvingKey,
    sapling::circuit::{OutputParameters, SpendParameters},
};
use once_cell::sync::OnceCell;
use std::io::Cursor;

pub const LIB_VERSION: u8 = 1;

// Global statics for parameters
static SPEND_PARAMS: OnceCell<SpendParameters> = OnceCell::new();
static OUTPUT_PARAMS: OnceCell<OutputParameters> = OnceCell::new();
static ORCHARD_PK: OnceCell<ProvingKey> = OnceCell::new();

/// Get or initialize SpendParameters from payload
pub fn get_or_init_spend_params(payload: &[u8]) -> Result<&'static SpendParameters, Error> {
    SPEND_PARAMS.get_or_try_init(|| {
        let reader = Cursor::new(payload);
        SpendParameters::read(reader, false).map_err(|_| Error::SaplingInvalidParameters)
    })
}

/// Get or initialize OutputParameters from payload
pub fn get_or_init_output_params(payload: &[u8]) -> Result<&'static OutputParameters, Error> {
    OUTPUT_PARAMS.get_or_try_init(|| {
        let reader = Cursor::new(payload);
        OutputParameters::read(reader, false).map_err(|_| Error::SaplingInvalidParameters)
    })
}

/// Get already initialized SpendParameters
pub fn get_spend_params() -> Result<&'static SpendParameters, Error> {
    SPEND_PARAMS.get().ok_or(Error::SaplingSpendNotInitialized)
}

/// Get already initialized OutputParameters
pub fn get_output_params() -> Result<&'static OutputParameters, Error> {
    OUTPUT_PARAMS
        .get()
        .ok_or(Error::SaplingOutputNotInitialized)
}

/// Get or initialize Orchard ProvingKey
pub fn get_or_init_orchard_pk() -> Result<&'static ProvingKey, Error> {
    ORCHARD_PK.get_or_try_init(|| Ok(ProvingKey::build()))
}
