//! Gadget for Zcash's Pedersen hash.

use super::ecc::{EdwardsPoint, MontgomeryPoint};
pub use crate::sapling::pedersen_hash::Personalization;

use alloc::vec::Vec;
use bellman::gadgets::boolean::Boolean;
use bellman::gadgets::lookup::*;
use bellman::{ConstraintSystem, SynthesisError};

use super::constants::PEDERSEN_CIRCUIT_GENERATORS;

fn get_constant_bools(person: &Personalization) -> Vec<Boolean> {
    person
        .get_bits()
        .into_iter()
        .map(Boolean::constant)
        .collect()
}

pub fn pedersen_hash<CS>(
    mut cs: CS,
    personalization: Personalization,
    bits: &[Boolean],
) -> Result<EdwardsPoint, SynthesisError>
where
    CS: ConstraintSystem<bls12_381::Scalar>,
{
    let personalization = get_constant_bools(&personalization);
    assert_eq!(personalization.len(), 6);

    let mut edwards_result = None;
    let mut bits = personalization.iter().chain(bits.iter()).peekable();
    let mut segment_generators = PEDERSEN_CIRCUIT_GENERATORS.iter();
    let boolean_false = Boolean::constant(false);

    let mut segment_i = 0;
    while bits.peek().is_some() {
        let mut segment_result = None;
        let mut segment_windows = &segment_generators.next().expect("enough segments")[..];

        let mut window_i = 0;
        while let Some(a) = bits.next() {
            let b = bits.next().unwrap_or(&boolean_false);
            let c = bits.next().unwrap_or(&boolean_false);

            let tmp = lookup3_xy_with_conditional_negation(
                cs.namespace(|| format!("segment {}, window {}", segment_i, window_i)),
                &[a.clone(), b.clone(), c.clone()],
                &segment_windows[0],
            )?;

            let tmp = MontgomeryPoint::interpret_unchecked(tmp.0, tmp.1);

            match segment_result {
                None => {
                    segment_result = Some(tmp);
                }
                Some(ref mut segment_result) => {
                    *segment_result = tmp.add(
                        cs.namespace(|| {
                            format!("addition of segment {}, window {}", segment_i, window_i)
                        }),
                        segment_result,
                    )?;
                }
            }

            segment_windows = &segment_windows[1..];

            if segment_windows.is_empty() {
                break;
            }

            window_i += 1;
        }

        let segment_result = segment_result.expect(
            "bits is not exhausted due to while condition;
                    thus there must be a segment window;
                    thus there must be a segment result",
        );

        // Convert this segment into twisted Edwards form.
        let segment_result = segment_result.into_edwards(
            cs.namespace(|| format!("conversion of segment {} into edwards", segment_i)),
        )?;

        match edwards_result {
            Some(ref mut edwards_result) => {
                *edwards_result = segment_result.add(
                    cs.namespace(|| format!("addition of segment {} to accumulator", segment_i)),
                    edwards_result,
                )?;
            }
            None => {
                edwards_result = Some(segment_result);
            }
        }

        segment_i += 1;
    }

    Ok(edwards_result.unwrap())
}
