//! NAS synchronization API shared by both bridge surfaces.
//!
//! flutter_rust_bridge mirrors these functions and types for Android/iOS,
//! and the JSON C ABI (HarmonyOS) serializes the same types. All failure
//! reporting goes through [`NasError`], which carries a category only.

use crate::nas::{make_backend, relative_file_path, NasConfig, NasError, NasTestDetails};
use std::path::Path;

/// One upload job: where the file comes from and where it goes.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct NasUploadRequest {
    pub config: NasConfig,
    /// Sanitized project directory name below the configured root.
    pub project_key: String,
    /// Remote file name, typically `{照片编号}.jpg`.
    pub file_name: String,
    /// Local path of the rendered watermarked JPEG.
    pub local_path: String,
}

/// Probes the configured server: connectivity, authentication and root
/// writability. Returns protocol details (the SFTP host key fingerprint)
/// the caller should persist after the user accepts them.
pub fn nas_test_connection(config: NasConfig) -> Result<NasTestDetails, NasError> {
    make_backend(&config)?.test_connection()
}

/// Uploads the local file to `{root}/{project_key}/{file_name}`, creating
/// every missing directory on the way and overwriting previous content so
/// retries converge. Reads the whole file into memory first: watermarked
/// JPEGs are single-digit megabytes and every protocol here prefers a
/// known-size body over streaming bookkeeping.
pub fn nas_upload(request: NasUploadRequest) -> Result<(), NasError> {
    let backend = make_backend(&request.config)?;
    let relative = relative_file_path(&request.project_key, &request.file_name)?;
    if !Path::new(&request.local_path).is_file() {
        return Err(NasError::new(crate::nas::NasErrorCode::LocalIo));
    }
    let bytes = std::fs::read(&request.local_path)
        .map_err(|_| NasError::new(crate::nas::NasErrorCode::LocalIo))?;
    backend.ensure_dirs(&[request.project_key])?;
    backend.put_file(&relative, bytes)
}
