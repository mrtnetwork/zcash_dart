use std::vec::Vec;

use crate::{
    error::Error, new_request_inner, setup_sapling_output_params_inner,
    setup_sapling_spend_params_inner,
};

/// Free memory allocated by Rust
#[no_mangle]
pub extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    unsafe { drop(Vec::from_raw_parts(ptr, len, len)) }
}

#[no_mangle]
pub extern "C" fn setup_sapling_spend_params(payload_ptr: *const u8, payload_len: usize) -> u32 {
    if payload_ptr.is_null() {
        return Error::Internal as u32;
    }

    let payload = unsafe { std::slice::from_raw_parts(payload_ptr, payload_len) };

    setup_sapling_spend_params_inner(payload)
}
#[no_mangle]
pub extern "C" fn setup_sapling_output_params(payload_ptr: *const u8, payload_len: usize) -> u32 {
    if payload_ptr.is_null() {
        return Error::Internal as u32;
    }

    let payload = unsafe { std::slice::from_raw_parts(payload_ptr, payload_len) };

    setup_sapling_output_params_inner(payload)
}

/// Dart calls this
#[no_mangle]
pub extern "C" fn new_request_c(
    payload_ptr: *const u8,
    payload_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if payload_ptr.is_null() || out_ptr.is_null() || out_len.is_null() {
        return Error::Internal as u32;
    }

    let payload = unsafe { std::slice::from_raw_parts(payload_ptr, payload_len) };

    let response = new_request_inner(payload);
    response
        .map(|mut response| {
            let ptr = response.as_mut_ptr();
            let len = response.len();

            unsafe {
                *out_ptr = ptr;
                *out_len = len;
            }
            // Transfer ownership to caller
            std::mem::forget(response);
            0
        })
        .unwrap_or_else(|e| {
            unsafe { *out_len = 0 };
            e as u32
        })
}
