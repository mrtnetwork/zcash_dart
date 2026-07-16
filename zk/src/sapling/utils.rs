use crate::{
    error::{enc_err, key_err, ZKError},
    sapling::{
        circuit::{Output, Spend, ValueCommitmentOpening},
        pedersen_hash::{pedersen_hash, Personalization},
        types::{
            SaplingOutputBytes, SaplingOutputVerification, SaplingOutputVerificationBytes,
            SaplingSpendBytes, SaplingSpendVerification, SaplingSpendVerificationBytes,
            MAX_AUTH_PATH, MAX_OUTPUT_VERIFY_INPUTS, MAX_SPEND_VERIFY_INPUTS,
        },
    },
};
use bls12_381::Scalar;
use ff::PrimeField;
use group::GroupEncoding;
use jubjub::Fr;
use minicbor::bytes::ByteArray;

pub struct ZKSaplingUtils;
impl ZKSaplingUtils {
    pub fn fr_from_bytes(bytes: [u8; 32]) -> ZKError<Fr> {
        Fr::from_repr(bytes)
            .into_option()
            .ok_or_else(|| enc_err("fr", "invalid encoding"))
    }

    pub fn scalar_from_bytes(bytes: [u8; 32]) -> ZKError<Scalar> {
        Scalar::from_repr(bytes)
            .into_option()
            .ok_or_else(|| enc_err("scalar", "invalid encoding"))
    }

    pub fn extended_from_bytes(bytes: [u8; 32]) -> ZKError<jubjub::ExtendedPoint> {
        jubjub::ExtendedPoint::from_bytes(&bytes)
            .into_option()
            .ok_or_else(|| key_err("jubjub_point", "invalid encoding"))
    }
    pub fn parse_sapling_output_proof(bytes: SaplingOutputBytes) -> ZKError<Output> {
        Ok(Output {
            value_commitment_opening: Some(ValueCommitmentOpening {
                value: bytes.value,
                randomness: ZKSaplingUtils::fr_from_bytes(bytes.randomness.into())?,
            }),
            recipient_address_diversify_hash: Some(ZKSaplingUtils::extended_from_bytes(
                bytes.recipient_address_diversify_hash.into(),
            )?),
            recipient_address_pk_d: Some(ZKSaplingUtils::extended_from_bytes(
                bytes.recipient_address_pk_d.into(),
            )?),
            esk: Some(ZKSaplingUtils::fr_from_bytes(bytes.esk.into())?),
            commitment_randomness: Some(ZKSaplingUtils::fr_from_bytes(
                bytes.commitment_randomness.into(),
            )?),
        })
    }

    pub fn parse_sapling_spend_proof(bytes: SaplingSpendBytes) -> ZKError<Spend> {
        let mut auth_path = Vec::with_capacity(MAX_AUTH_PATH);

        for i in 0..MAX_AUTH_PATH {
            let scalar = ZKSaplingUtils::scalar_from_bytes(bytes.auth_path[i].into())?;
            let flag = bytes.auth_path_pos[i];
            auth_path.push(Some((scalar, flag)));
        }

        Ok(Spend {
            value_commitment_opening: Some(ValueCommitmentOpening {
                value: bytes.value as u64,
                randomness: ZKSaplingUtils::fr_from_bytes(bytes.randomness.into())?,
            }),
            ak: Some(ZKSaplingUtils::extended_from_bytes(bytes.ak.into())?),
            nsk: Some(ZKSaplingUtils::fr_from_bytes(bytes.nsk.into())?),
            payment_address_diversify_hash: Some(ZKSaplingUtils::extended_from_bytes(
                bytes.payment_address_diversify_hash.into(),
            )?),
            anchor: Some(ZKSaplingUtils::scalar_from_bytes(bytes.anchor.into())?),
            ar: Some(ZKSaplingUtils::fr_from_bytes(bytes.ar.into())?),
            auth_path,
            commitment_randomness: Some(ZKSaplingUtils::fr_from_bytes(
                bytes.commitment_randomness.into(),
            )?),
        })
    }
    fn parse_public_inputs<const N: usize>(inputs: [ByteArray<32>; N]) -> ZKError<[Scalar; N]> {
        let mut out = [Scalar::default(); N];

        for i in 0..N {
            out[i] = ZKSaplingUtils::scalar_from_bytes(inputs[i].into())?;
        }

        Ok(out)
    }
    pub fn parse_sapling_spend_verification(
        bytes: SaplingSpendVerificationBytes,
    ) -> ZKError<SaplingSpendVerification> {
        let public_inputs =
            Self::parse_public_inputs::<MAX_SPEND_VERIFY_INPUTS>(bytes.public_inputs)?;

        Ok(SaplingSpendVerification {
            proof: bytes.proof.into(),
            public_inputs,
        })
    }

    pub fn parse_sapling_output_verification(
        bytes: SaplingOutputVerificationBytes,
    ) -> ZKError<SaplingOutputVerification> {
        let public_inputs =
            Self::parse_public_inputs::<MAX_OUTPUT_VERIFY_INPUTS>(bytes.public_inputs)?;

        Ok(SaplingOutputVerification {
            proof: bytes.proof.into(),
            public_inputs,
        })
    }

    pub fn pedersen_hash(bits: Vec<bool>, merkle_tree_size: Option<u32>) -> ZKError<[u8; 32]> {
        let hash = pedersen_hash(
            match merkle_tree_size {
                Some(size) => Personalization::MerkleTree(size as usize),
                None => Personalization::NoteCommitment,
            },
            bits,
        );
        Ok(hash.to_bytes())
    }
}
