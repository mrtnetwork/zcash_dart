#[repr(u32)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum Error {
    KeyError = 1,
    EncodingError = 2,
    InvalidInput = 3,
    ProofError = 4,
    WitnessError = 5,
    MerkleError = 6,
    Internal = 7,
    Missing = 8,
    HashError = 9,
}
pub struct RuntimeError {
    pub code: Error,
    pub msg: alloc::string::String,
}
impl RuntimeError {
    pub fn key(msg: impl Into<String>) -> Self {
        Self {
            code: Error::KeyError,
            msg: msg.into(),
        }
    }
    pub fn hash(msg: impl Into<String>) -> Self {
        Self {
            code: Error::HashError,
            msg: msg.into(),
        }
    }

    pub fn encoding(msg: impl Into<String>) -> Self {
        Self {
            code: Error::EncodingError,
            msg: msg.into(),
        }
    }

    pub fn input(msg: impl Into<String>) -> Self {
        Self {
            code: Error::InvalidInput,
            msg: msg.into(),
        }
    }

    pub fn proof(msg: impl Into<String>) -> Self {
        Self {
            code: Error::ProofError,
            msg: msg.into(),
        }
    }
    pub fn internal(msg: impl Into<String>) -> Self {
        Self {
            code: Error::Internal,
            msg: msg.into(),
        }
    }
}
pub type ZKError<T> = Result<T, RuntimeError>;

pub fn enc_err(field: &str, msg: &str) -> RuntimeError {
    RuntimeError::encoding(format!("{field}: {msg}"))
}

pub fn key_err(field: &str, msg: &str) -> RuntimeError {
    RuntimeError::key(format!("{field}: {msg}"))
}
pub fn hash_err(field: &str, msg: &str) -> RuntimeError {
    RuntimeError::hash(format!("{field}: {msg}"))
}

pub fn input_err(field: &str, msg: &str) -> RuntimeError {
    RuntimeError::input(format!("{field}: {msg}"))
}
pub fn internal_err(msg: &str) -> RuntimeError {
    RuntimeError::internal(msg.to_string())
}
