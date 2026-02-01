use crate::{process_core, OutputData};

/// Dart calls this
#[no_mangle]
pub extern "C" fn process_bytes_ffi(
    id: u32,
    payload_ptr: *const u8,
    payload_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if payload_ptr.is_null() || out_ptr.is_null() || out_len.is_null() {
        return u32::MAX; // error code
    }

    let payload = unsafe { std::slice::from_raw_parts(payload_ptr, payload_len) };

    let OutputData { mut bytes, code } = process_core(id, payload);

    let ptr = bytes.as_mut_ptr();
    let len = bytes.len();

    unsafe {
        *out_ptr = ptr;
        *out_len = len;
    }

    // Transfer ownership to caller
    std::mem::forget(bytes);

    code
}

/// Free memory allocated by Rust
#[no_mangle]
pub extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    unsafe { drop(Vec::from_raw_parts(ptr, len, len)) }
}
