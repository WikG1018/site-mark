//! SFTP backend on top of russh + russh-sftp.
//!
//! Transport security is inherent to SSH, so there is no TLS switch here.
//! Host key handling is trust-on-first-use enforced in Rust: the caller
//! passes the fingerprint it previously accepted (if any), the backend
//! compares it against the key the server presents, reports what it saw,
//! and refuses to continue on a mismatch (NasErrorCode::HostKeyChanged).

use russh::client;
use russh_sftp::client::fs::File;
use russh_sftp::client::SftpSession;
use russh_sftp::protocol::StatusCode;
use std::sync::Mutex;
use tokio::io::AsyncWriteExt;

use super::runtime::{block_on, block_on_timed, OP_TIMEOUT};
use super::{
    root_segments, NasBackend, NasConfig, NasError, NasErrorCode, NasTestDetails, PROBE_FILE_NAME,
};

type SeenFingerprint = Mutex<Option<String>>;

struct TofuHandler {
    known_fingerprint: Option<String>,
    seen_fingerprint: std::sync::Arc<SeenFingerprint>,
}

#[async_trait::async_trait]
impl client::Handler for TofuHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &russh::keys::key::PublicKey,
    ) -> Result<bool, Self::Error> {
        let fingerprint = format!("SHA256:{}", server_public_key.fingerprint());
        *self.seen_fingerprint.lock().expect("fingerprint mutex") = Some(fingerprint);
        let seen = self
            .seen_fingerprint
            .lock()
            .expect("fingerprint mutex")
            .clone();
        Ok(match &self.known_fingerprint {
            // First contact: accept, and the caller stores the fingerprint.
            None => true,
            Some(known) => Some(known.clone()) == seen,
        })
    }
}

pub(crate) struct SftpBackend {
    config: NasConfig,
}

impl SftpBackend {
    pub(crate) fn new(config: NasConfig) -> Self {
        Self { config }
    }

    /// Connects, authenticates and opens the SFTP subsystem. Reports the
    /// server host key fingerprint it observed via `seen_fingerprint`.
    fn connect_sftp(
        &self,
        seen_fingerprint: &std::sync::Arc<SeenFingerprint>,
    ) -> Result<SftpSession, NasError> {
        let config = russh::client::Config {
            inactivity_timeout: Some(OP_TIMEOUT),
            ..Default::default()
        };
        let addr = (self.config.host.clone(), self.config.port.unwrap_or(22));
        let handler = TofuHandler {
            known_fingerprint: self.config.known_sftp_fingerprint.clone(),
            seen_fingerprint: std::sync::Arc::clone(seen_fingerprint),
        };
        let mut session =
            block_on_timed(client::connect(std::sync::Arc::new(config), addr, handler))
                .map_err(|_| NasError::new(NasErrorCode::Timeout))?
                .map_err(super::map_russh_connect_error)?;
        let authenticated = block_on_timed(
            session.authenticate_password(&self.config.username, &self.config.password),
        )
        .map_err(|_| NasError::new(NasErrorCode::Timeout))?
        .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        if !authenticated {
            return Err(NasError::new(NasErrorCode::AuthFailed));
        }
        let channel = block_on(session.channel_open_session())
            .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        block_on(channel.request_subsystem(true, "sftp"))
            .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        let stream = channel.into_stream();
        block_on(SftpSession::new(stream)).map_err(|_| NasError::new(NasErrorCode::ProtocolError))
    }

    fn root_prefix(&self) -> String {
        let root = root_segments(&self.config.root_path).unwrap_or_default();
        if root.is_empty() {
            String::new()
        } else {
            format!("/{}", root.join("/"))
        }
    }

    fn sftp_path(&self, segments: &[String]) -> String {
        let prefix = self.root_prefix();
        let mut path = prefix;
        for segment in segments {
            if !path.ends_with('/') && !path.is_empty() {
                path.push('/');
            }
            path.push_str(segment);
        }
        path
    }
}

impl NasBackend for SftpBackend {
    fn test_connection(&self) -> Result<NasTestDetails, NasError> {
        let seen_fingerprint = std::sync::Arc::new(SeenFingerprint::new(None));
        let sftp = self.connect_sftp(&seen_fingerprint)?;
        // Create the root when missing so the very first probe succeeds,
        // then write/read/delete the canary file at the root.
        let root = self.sftp_path(&[]);
        if !root.is_empty() {
            block_on(sftp.create_dir(&root))
                .or_else(|_| block_on(sftp.metadata(&root)).map(|_| ()))
                .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        }
        let probe_path = self.sftp_path(&[PROBE_FILE_NAME.to_string()]);
        write_probe(&sftp, &probe_path)?;
        block_on(sftp.remove_file(&probe_path))
            .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        let fingerprint = seen_fingerprint.lock().expect("fingerprint mutex").clone();
        Ok(NasTestDetails {
            sftp_fingerprint: fingerprint,
        })
    }

    fn ensure_dirs(&self, segments: &[String]) -> Result<(), NasError> {
        let seen_fingerprint = std::sync::Arc::new(SeenFingerprint::new(None));
        let sftp = self.connect_sftp(&seen_fingerprint)?;
        // `segments` are relative to the root; the root itself is part of
        // the tree that has to exist, so it is walked first.
        let mut full = root_segments(&self.config.root_path)?;
        full.extend(segments.iter().cloned());
        for depth in 1..=full.len() {
            let path = self.sftp_path(&full[..depth]);
            block_on(sftp.create_dir(&path))
                .or_else(|_| block_on(sftp.metadata(&path)).map(|_| ()))
                .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        }
        Ok(())
    }

    fn put_file(&self, relative_path: &str, bytes: Vec<u8>) -> Result<(), NasError> {
        let seen_fingerprint = std::sync::Arc::new(SeenFingerprint::new(None));
        let sftp = self.connect_sftp(&seen_fingerprint)?;
        let path = self.sftp_path(&[relative_path.to_string()]);
        let mut file: File =
            block_on(sftp.create(&path)).map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        block_on(file.write_all(&bytes)).map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        block_on(file.flush()).map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
        block_on(file.shutdown()).map_err(|_| NasError::new(NasErrorCode::ProtocolError))
    }

    fn stat_file(&self, relative_path: &str) -> Result<Option<u64>, NasError> {
        let seen_fingerprint = std::sync::Arc::new(SeenFingerprint::new(None));
        let sftp = self.connect_sftp(&seen_fingerprint)?;
        let path = self.sftp_path(&[relative_path.to_string()]);
        match block_on(sftp.metadata(&path)) {
            Ok(attributes) => Ok(attributes.size),
            Err(error) => {
                if is_not_found(&error) {
                    Ok(None)
                } else {
                    Err(NasError::new(NasErrorCode::ProtocolError))
                }
            }
        }
    }

    fn delete_file(&self, relative_path: &str) -> Result<(), NasError> {
        let seen_fingerprint = std::sync::Arc::new(SeenFingerprint::new(None));
        let sftp = self.connect_sftp(&seen_fingerprint)?;
        let path = self.sftp_path(&[relative_path.to_string()]);
        match block_on(sftp.remove_file(&path)) {
            Ok(()) => Ok(()),
            Err(error) => {
                if is_not_found(&error) {
                    Ok(())
                } else {
                    Err(NasError::new(NasErrorCode::ProtocolError))
                }
            }
        }
    }
}

fn write_probe(sftp: &SftpSession, probe_path: &str) -> Result<(), NasError> {
    let mut file: File = block_on(sftp.create(probe_path))
        .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
    block_on(file.write_all(b"sitemark connection probe"))
        .map_err(|_| NasError::new(NasErrorCode::ProtocolError))?;
    block_on(file.shutdown()).map_err(|_| NasError::new(NasErrorCode::ProtocolError))
}

fn is_not_found(error: &russh_sftp::client::error::Error) -> bool {
    match error {
        russh_sftp::client::error::Error::Status(status) => {
            status.status_code == StatusCode::NoSuchFile
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::super::NasProtocol;
    use super::*;

    #[test]
    fn builds_absolute_paths_from_root() {
        let backend = SftpBackend::new(NasConfig {
            protocol: NasProtocol::Sftp,
            host: "nas.local".to_string(),
            port: None,
            username: "u".to_string(),
            password: "p".to_string(),
            root_path: "/volume1/SiteMark".to_string(),
            secure_tls: false,
            accept_invalid_tls: false,
            known_sftp_fingerprint: None,
        });
        assert_eq!(backend.sftp_path(&[]), "/volume1/SiteMark");
        assert_eq!(
            backend.sftp_path(&["项目".to_string(), "003.jpg".to_string()]),
            "/volume1/SiteMark/项目/003.jpg"
        );
    }

    #[test]
    fn empty_root_starts_relative_to_home() {
        let backend = SftpBackend::new(NasConfig {
            protocol: NasProtocol::Sftp,
            host: "nas.local".to_string(),
            port: None,
            username: "u".to_string(),
            password: "p".to_string(),
            root_path: "/".to_string(),
            secure_tls: false,
            accept_invalid_tls: false,
            known_sftp_fingerprint: None,
        });
        assert_eq!(backend.sftp_path(&[]), "");
        assert_eq!(backend.sftp_path(&["a".to_string()]), "a");
    }

    #[test]
    fn not_found_detection_covers_no_such_file() {
        let status = |code: StatusCode| russh_sftp::protocol::Status {
            id: 0,
            status_code: code,
            error_message: String::new(),
            language_tag: String::new(),
        };
        assert!(is_not_found(&russh_sftp::client::error::Error::Status(
            status(StatusCode::NoSuchFile)
        )));
        assert!(!is_not_found(&russh_sftp::client::error::Error::Status(
            status(StatusCode::PermissionDenied)
        )));
    }
}
