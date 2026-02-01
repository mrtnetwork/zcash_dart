#[repr(u32)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum Error {
    Ok = 0,

    // General
    InvalidLength = 1,
    InvalidPointEncoding = 2,

    SaplingInvalidParameters = 3,
    UnexpectedError = 4,
    SaplingSpendNotInitialized = 5,
    SaplingOutputNotInitialized = 6,
    UnknowRequestId = 7,
    // Sapling-specific
    SaplingInvalidValue = 10,
    SaplingInvalidRandomness = 11,
    SaplingInvalidAuthPath = 12,
    SaplingInvalidAnchor = 13,
    SaplingInvalidProof = 14,

    /// orchard
    OrchardInvalidFvk = 20,
    OrchardInvalidAddress = 21,
    OrchardInvalidRho = 22,
    OrchardInvalidRseed = 23,
    OrchardInvalidAuthPath = 24,
    OrchardInvalidScalar = 25,
    OrchardInvalidNote = 26,
    OrchardInvalidCommitment = 27,
    OrchardInvalidSpend = 28,
    OrchardInvalidCircuit = 29,
    OrchardProofCreationFailed = 30,
}
