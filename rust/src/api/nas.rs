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

/// One download job used by two-way sync to restore a missing local copy.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct NasDownloadRequest {
    pub config: NasConfig,
    pub project_key: String,
    pub file_name: String,
    /// Destination path for the restored JPEG.
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
/// retries converge. SFTP/SMB stream from disk on a single connection;
/// WebDAV still needs a known-size body.
pub fn nas_upload(request: NasUploadRequest) -> Result<(), NasError> {
    let backend = make_backend(&request.config)?;
    let relative = relative_file_path(&request.project_key, &request.file_name)?;
    if !Path::new(&request.local_path).is_file() {
        return Err(NasError::new(crate::nas::NasErrorCode::LocalIo));
    }
    backend.upload_from_path(
        &[request.project_key],
        &relative,
        Path::new(&request.local_path),
    )
}

/// Downloads `{root}/{project_key}/{file_name}` to [NasDownloadRequest::local_path].
pub fn nas_download(request: NasDownloadRequest) -> Result<(), NasError> {
    let backend = make_backend(&request.config)?;
    let relative = relative_file_path(&request.project_key, &request.file_name)?;
    if let Some(parent) = Path::new(&request.local_path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|_| NasError::new(crate::nas::NasErrorCode::LocalIo))?;
        }
    }
    backend.get_file_to_path(&relative, Path::new(&request.local_path))
}

/// One remote JPEG discovered under the configured root.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct NasRemoteFile {
    pub project_key: String,
    pub file_name: String,
}

/// Lists remote project folders and their `.jpg` files (one level deep).
pub fn nas_list(config: NasConfig) -> Result<Vec<NasRemoteFile>, NasError> {
    let backend = make_backend(&config)?;
    Ok(backend
        .list_project_files()?
        .into_iter()
        .map(|(project_key, file_name)| NasRemoteFile {
            project_key,
            file_name,
        })
        .collect())
}

/// Deletes `{root}/{project_key}/{file_name}`; missing files succeed.
pub fn nas_delete(request: NasDownloadRequest) -> Result<(), NasError> {
    let backend = make_backend(&request.config)?;
    let relative = relative_file_path(&request.project_key, &request.file_name)?;
    backend.delete_file(&relative)
}
