//! Minimal JSON C ABI used by the native HarmonyOS N-API wrapper.
//!
//! The existing Flutter Rust Bridge surface remains the default feature. The
//! HarmonyOS build disables that feature so it does not link the Dart runtime,
//! then calls this stable ownership-safe boundary from a tiny C++ N-API module.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::api::image_core::{
    export_diagnostic_bundle, export_project, export_project_bundle, export_selection,
    extract_archive_photo, extract_project_bundle_entry, read_project_archive, read_project_bundle,
    render_photo, sha256_file, ExportDiagnosticBundleRequest, ExportProjectBundleRequest,
    ExportProjectRequest, ExportSelectionRequest, ExtractArchivePhotoRequest,
    ExtractProjectBundleEntryRequest, RenderPhotoRequest,
};

#[derive(Debug, Deserialize)]
struct JsonCall {
    operation: String,
    payload: Value,
}

#[derive(Debug, Deserialize)]
struct PathRequest {
    path: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct JsonResponse {
    ok: bool,
    value: Option<Value>,
    error: Option<String>,
}

fn parse_payload<T: for<'de> Deserialize<'de>>(value: Value) -> Result<T, String> {
    serde_json::from_value(value).map_err(|error| format!("invalid_data:{error}"))
}

fn value_of<T: Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|error| format!("invalid_data:{error}"))
}

fn dispatch(call: JsonCall) -> Result<Value, String> {
    match call.operation.as_str() {
        "sha256" => {
            let request: PathRequest = parse_payload(call.payload)?;
            value_of(sha256_file(request.path)?)
        }
        "render" => {
            let request: RenderPhotoRequest = parse_payload(call.payload)?;
            value_of(render_photo(request)?)
        }
        "export" => {
            let request: ExportProjectRequest = parse_payload(call.payload)?;
            value_of(export_project(request)?)
        }
        "exportSelection" => {
            let request: ExportSelectionRequest = parse_payload(call.payload)?;
            value_of(export_selection(request)?)
        }
        "exportDiagnostic" => {
            let request: ExportDiagnosticBundleRequest = parse_payload(call.payload)?;
            value_of(export_diagnostic_bundle(request)?)
        }
        "exportBundle" => {
            let request: ExportProjectBundleRequest = parse_payload(call.payload)?;
            value_of(export_project_bundle(request)?)
        }
        "readProjectArchive" => {
            let request: PathRequest = parse_payload(call.payload)?;
            value_of(read_project_archive(request.path)?)
        }
        "extractArchivePhoto" => {
            let request: ExtractArchivePhotoRequest = parse_payload(call.payload)?;
            value_of(extract_archive_photo(request)?)
        }
        "readBundle" => {
            let request: PathRequest = parse_payload(call.payload)?;
            value_of(read_project_bundle(request.path)?)
        }
        "extractBundleEntry" => {
            let request: ExtractProjectBundleEntryRequest = parse_payload(call.payload)?;
            extract_project_bundle_entry(request)?;
            Ok(Value::Null)
        }
        _ => Err("invalid_data:unsupported operation".to_string()),
    }
}

fn response_json(input: *const c_char) -> String {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<Value, String> {
        if input.is_null() {
            return Err("invalid_data:null request".to_string());
        }
        let bytes = unsafe { CStr::from_ptr(input) };
        let json = bytes
            .to_str()
            .map_err(|_| "invalid_data:request must be UTF-8".to_string())?;
        let call: JsonCall =
            serde_json::from_str(json).map_err(|error| format!("invalid_data:{error}"))?;
        dispatch(call)
    }));

    let response = match result {
        Ok(Ok(value)) => JsonResponse {
            ok: true,
            value: Some(value),
            error: None,
        },
        Ok(Err(error)) => JsonResponse {
            ok: false,
            value: None,
            error: Some(error),
        },
        Err(panic) => {
            // A panic is an internal bug, not bad input; classify it as
            // internal and log the payload because the string boundary cannot
            // carry diagnostics back to the caller.
            let payload = panic
                .downcast_ref::<&str>()
                .map(|message| (*message).to_string())
                .or_else(|| panic.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "unknown panic payload".to_string());
            eprintln!("sitemark native panic: {payload}");
            JsonResponse {
                ok: false,
                value: None,
                error: Some("internal:native panic".to_string()),
            }
        }
    };
    serde_json::to_string(&response).unwrap_or_else(|_| {
        "{\"ok\":false,\"value\":null,\"error\":\"invalid_data:serialization\"}".to_string()
    })
}

/// Calls the image core. The returned UTF-8 string is owned by Rust and must
/// be released exactly once with [`sitemark_string_free`].
///
/// # Safety
///
/// `input` must be null or point to a valid NUL-terminated UTF-8 byte string
/// for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn sitemark_call_json(input: *const c_char) -> *mut c_char {
    let response = response_json(input).replace('\0', "");
    CString::new(response)
        .expect("NUL bytes were removed")
        .into_raw()
}

/// Releases a string returned by [`sitemark_call_json`].
///
/// # Safety
///
/// `value` must be null or a pointer returned by `sitemark_call_json` that has
/// not already been released.
#[no_mangle]
pub unsafe extern "C" fn sitemark_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            drop(CString::from_raw(value));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unknown_operations_without_panicking() {
        let response = response_json(
            CString::new(r#"{"operation":"unknown","payload":{}}"#)
                .unwrap()
                .as_ptr(),
        );
        let decoded: JsonResponse = serde_json::from_str(&response).unwrap();
        assert!(!decoded.ok);
        assert_eq!(
            decoded.error.as_deref(),
            Some("invalid_data:unsupported operation")
        );
    }
}
