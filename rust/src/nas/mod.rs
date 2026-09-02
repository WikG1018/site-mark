//! NAS synchronization core: one implementation of the WebDAV, SFTP and SMB
//! clients shared by the Flutter (Android/iOS) and HarmonyOS product lines.
//!
//! The bridge layers (flutter_rust_bridge for Flutter, the JSON C ABI for
//! HarmonyOS) only pass structured parameters across the boundary; every
//! protocol detail, remote-path rule and error category lives here so both
//! lines behave identically. Error values carry categories only — server
//! strings, host names and paths must never reach user-facing surfaces.

pub mod runtime;
pub mod sftp;
pub mod smb;
pub mod webdav;

use std::fmt;

/// Remote surface selection. Wire values are serialized snake_case.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NasProtocol {
    Webdav,
    Sftp,
    Smb,
}

/// Connection parameters. The password is only ever held in memory here; it
/// is supplied per call from secure storage and never persisted in SQLite.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct NasConfig {
    pub protocol: NasProtocol,
    pub host: String,
    pub port: Option<u16>,
    pub username: String,
    pub password: String,
    /// WebDAV/SFTP: server path prefix such as `/SiteMark`. SMB: `/share`
    /// followed by optional sub-directories such as `/media/SiteMark`.
    pub root_path: String,
    /// WebDAV only: try HTTPS instead of HTTP. SFTP is always encrypted and
    /// SMB negotiates its own crypto, so both ignore this flag.
    pub secure_tls: bool,
    /// WebDAV only: accept self-signed or mismatched certificates.
    pub accept_invalid_tls: bool,
    /// SFTP only: host key fingerprint previously accepted by the user
    /// (OpenSSH `SHA256:…` form). `None` trusts on first use; a mismatch
    /// aborts every operation with `NasErrorCode::HostKeyChanged`.
    pub known_sftp_fingerprint: Option<String>,
}

/// Stable, translatable failure categories. UI text must map from these —
/// never from server messages.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NasErrorCode {
    ConfigInvalid,
    ConnectionFailed,
    AuthFailed,
    Timeout,
    TlsError,
    /// HTTPS was requested on a build whose WebDAV stack has no TLS support
    /// (the HarmonyOS line stays C-free and therefore TLS-free for WebDAV).
    TlsUnsupported,
    /// SFTP server key does not match the fingerprint the user accepted.
    HostKeyChanged,
    ProtocolError,
    QuotaInsufficient,
    PathInvalid,
    LocalIo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct NasError {
    pub code: NasErrorCode,
}

impl NasError {
    pub fn new(code: NasErrorCode) -> Self {
        Self { code }
    }

    /// The stable snake_case wire form, shared by serde serialization and
    /// the C ABI's error strings (`nas:{code_name}`) so both bridge layers
    /// speak the same contract.
    pub fn code_name(&self) -> &'static str {
        match self.code {
            NasErrorCode::ConfigInvalid => "config_invalid",
            NasErrorCode::ConnectionFailed => "connection_failed",
            NasErrorCode::AuthFailed => "auth_failed",
            NasErrorCode::Timeout => "timeout",
            NasErrorCode::TlsError => "tls_error",
            NasErrorCode::TlsUnsupported => "tls_unsupported",
            NasErrorCode::HostKeyChanged => "host_key_changed",
            NasErrorCode::ProtocolError => "protocol_error",
            NasErrorCode::QuotaInsufficient => "quota_insufficient",
            NasErrorCode::PathInvalid => "path_invalid",
            NasErrorCode::LocalIo => "local_io",
        }
    }
}

impl fmt::Display for NasError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "nas:{}", self.code_name())
    }
}

impl std::error::Error for NasError {}

/// One path segment that is safe to join on every protocol: WebDAV URL
/// segments, SFTP paths and SMB names all forbid separators, traversal and
/// control characters, so the contract is enforced once, here.
pub(crate) fn validate_segment(segment: &str, code: NasErrorCode) -> Result<(), NasError> {
    if segment.is_empty()
        || segment == "."
        || segment == ".."
        || segment.contains(['/', '\\', '\0'])
        || segment.chars().any(char::is_control)
    {
        return Err(NasError::new(code));
    }
    Ok(())
}

/// Splits a root path into normalized segments. `/SiteMark/` → `["SiteMark"]`,
/// `/` or `` → empty. Rejects traversal and backslashes everywhere so a
/// client-supplied root can never escape its subtree.
pub(crate) fn root_segments(root_path: &str) -> Result<Vec<String>, NasError> {
    let trimmed = root_path.trim();
    if trimmed.contains('\\') {
        return Err(NasError::new(NasErrorCode::PathInvalid));
    }
    let mut segments = Vec::new();
    for raw in trimmed.split('/') {
        if raw.is_empty() {
            continue;
        }
        validate_segment(raw, NasErrorCode::PathInvalid)?;
        segments.push(raw.to_string());
    }
    Ok(segments)
}

/// Percent-encodes one path segment for use inside a WebDAV URL. Everything
/// outside the RFC 3986 unreserved set is escaped, UTF-8 bytes included.
pub(crate) fn encode_url_segment(segment: &str) -> String {
    let mut encoded = String::with_capacity(segment.len());
    for byte in segment.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(byte as char);
            }
            other => {
                encoded.push_str(&format!("%{other:02X}"));
            }
        }
    }
    encoded
}

/// Everything a protocol backend must support for the v1 surface: probe the
/// server, create missing directories, upload a watermarked JPEG, verify and
/// clean up. All methods are blocking and own their timeouts.
pub(crate) trait NasBackend {
    /// Connects and verifies the configured root is usable: auth accepted,
    /// root creatable, and a probe file can be written, stat'ed and deleted.
    /// Reports protocol-specific details (the observed SFTP host key
    /// fingerprint) for the caller to persist.
    fn test_connection(&self) -> Result<NasTestDetails, NasError>;
    /// Creates every missing directory between the backend root and the
    /// file's parent directory. Idempotent: existing directories are fine.
    fn ensure_dirs(&self, segments: &[String]) -> Result<(), NasError>;
    /// Uploads `bytes` to `relative_path` (segments joined with `/`),
    /// overwriting any previous content.
    fn put_file(&self, relative_path: &str, bytes: Vec<u8>) -> Result<(), NasError>;
    /// Returns the stored file size, or `None` when the file does not exist.
    fn stat_file(&self, relative_path: &str) -> Result<Option<u64>, NasError>;
    /// Deletes the file; deleting an already-absent file succeeds.
    fn delete_file(&self, relative_path: &str) -> Result<(), NasError>;
}

/// Name of the small canary file written (and removed again) by
/// [`NasBackend::test_connection`] to prove the share is writable.
pub(crate) const PROBE_FILE_NAME: &str = "sitemark-connection-probe.txt";

/// Protocol-specific details reported by a successful connection test.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct NasTestDetails {
    /// SFTP: the host key fingerprint observed during the probe, so the
    /// caller can store it after the user accepts the first connection.
    pub sftp_fingerprint: Option<String>,
}

/// Maps transport-phase russh failures into stable categories.
pub(crate) fn map_russh_connect_error(error: russh::Error) -> NasError {
    match error {
        russh::Error::KeyChanged { .. }
        | russh::Error::UnknownKey
        | russh::Error::CouldNotReadKey
        | russh::Error::WrongServerSig => NasError::new(NasErrorCode::HostKeyChanged),
        russh::Error::ConnectionTimeout
        | russh::Error::KeepaliveTimeout
        | russh::Error::InactivityTimeout => NasError::new(NasErrorCode::Timeout),
        _ => NasError::new(NasErrorCode::ConnectionFailed),
    }
}

/// Maps smb2 failures into stable categories.
pub(crate) fn map_smb_error(error: smb2::Error) -> NasError {
    match error.kind() {
        smb2::ErrorKind::AuthRequired
        | smb2::ErrorKind::SigningRequired
        | smb2::ErrorKind::AccessDenied => NasError::new(NasErrorCode::AuthFailed),
        smb2::ErrorKind::DiskFull => NasError::new(NasErrorCode::QuotaInsufficient),
        smb2::ErrorKind::TimedOut => NasError::new(NasErrorCode::Timeout),
        smb2::ErrorKind::ConnectionLost | smb2::ErrorKind::Io => {
            NasError::new(NasErrorCode::ConnectionFailed)
        }
        _ => NasError::new(NasErrorCode::ProtocolError),
    }
}

pub(crate) fn make_backend(config: &NasConfig) -> Result<Box<dyn NasBackend>, NasError> {
    validate_config(config)?;
    match config.protocol {
        NasProtocol::Webdav => Ok(Box::new(webdav::WebdavBackend::new(config.clone()))),
        NasProtocol::Sftp => Ok(Box::new(sftp::SftpBackend::new(config.clone()))),
        NasProtocol::Smb => Ok(Box::new(smb::SmbBackend::new(config.clone()))),
    }
}

fn validate_config(config: &NasConfig) -> Result<(), NasError> {
    let invalid = NasError::new(NasErrorCode::ConfigInvalid);
    if config.host.trim().is_empty()
        || config.host.contains(['/', '\\', ' '])
        || config.host.starts_with("http")
    {
        return Err(invalid);
    }
    if let Some(port) = config.port {
        if port == 0 {
            return Err(invalid);
        }
    }
    match config.protocol {
        NasProtocol::Webdav | NasProtocol::Sftp => {
            root_segments(&config.root_path)?;
        }
        NasProtocol::Smb => {
            let segments = root_segments(&config.root_path)?;
            if segments.is_empty() {
                // The share name is mandatory: it is not part of the path.
                return Err(invalid);
            }
        }
    }
    Ok(())
}

/// Joins the project key and the file name into the canonical path below
/// the backend root: `{project_key}/{file_name}`. Creating the project
/// directory (and the root above it) is `ensure_dirs`' responsibility.
pub(crate) fn relative_file_path(project_key: &str, file_name: &str) -> Result<String, NasError> {
    validate_segment(project_key, NasErrorCode::PathInvalid)?;
    validate_segment(file_name, NasErrorCode::PathInvalid)?;
    Ok(format!("{project_key}/{file_name}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(protocol: NasProtocol, root: &str) -> NasConfig {
        NasConfig {
            protocol,
            host: "nas.local".to_string(),
            port: None,
            username: "user".to_string(),
            password: "pass".to_string(),
            root_path: root.to_string(),
            secure_tls: false,
            accept_invalid_tls: false,
            known_sftp_fingerprint: None,
        }
    }

    #[test]
    fn validates_segments_reject_traversal_and_separators() {
        for bad in ["..", ".", "a/b", "a\\b", "", "a\0b", "a\nb"] {
            assert!(
                validate_segment(bad, NasErrorCode::PathInvalid).is_err(),
                "segment {bad:?} must be rejected"
            );
        }
        for good in ["SiteMark", "项目", "003.jpg", "a-b_c"] {
            assert!(validate_segment(good, NasErrorCode::PathInvalid).is_ok());
        }
    }

    #[test]
    fn normalizes_root_segments() {
        assert!(root_segments("/").unwrap().is_empty());
        assert!(root_segments("").unwrap().is_empty());
        assert_eq!(
            root_segments("/SiteMark/").unwrap(),
            vec!["SiteMark".to_string()]
        );
        assert_eq!(
            root_segments("/media/SiteMark").unwrap(),
            vec!["media".to_string(), "SiteMark".to_string()]
        );
        assert!(root_segments("..").is_err());
        assert!(root_segments("a\\b").is_err());
    }

    #[test]
    fn smb_requires_share_in_root() {
        assert!(validate_config(&config(NasProtocol::Smb, "/")).is_err());
        assert!(validate_config(&config(NasProtocol::Smb, "/media/SiteMark")).is_ok());
    }

    #[test]
    fn rejects_host_shaped_like_url() {
        let mut cfg = config(NasProtocol::Webdav, "/dav");
        cfg.host = "https://nas.local".to_string();
        assert_eq!(
            validate_config(&cfg).unwrap_err().code,
            NasErrorCode::ConfigInvalid
        );
    }

    #[test]
    fn builds_relative_file_path() {
        let path = relative_file_path("云湖之城", "003.jpg").expect("valid path");
        assert_eq!(path, "云湖之城/003.jpg");
        assert!(relative_file_path("..", "x.jpg").is_err());
        assert!(relative_file_path("p", "a/b.jpg").is_err());
    }

    #[test]
    fn encodes_url_segments() {
        assert_eq!(encode_url_segment("a b/c"), "a%20b%2Fc");
        assert_eq!(
            encode_url_segment("云湖之城"),
            "%E4%BA%91%E6%B9%96%E4%B9%8B%E5%9F%8E"
        );
        assert_eq!(encode_url_segment("safe-name_1.jpg"), "safe-name_1.jpg");
    }
}
