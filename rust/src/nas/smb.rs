//! SMB2/3 backend on top of the pure-Rust `smb2` crate.
//!
//! SMB3 negotiates its own encryption and authentication (NTLM), so there
//! is no separate TLS switch. The configured root path must start with the
//! share name: `/media/SiteMark` mounts share `media` and addresses the
//! `SiteMark` directory inside it.

use super::runtime::{block_on_timed, OP_TIMEOUT};
use super::{
    root_segments, NasBackend, NasConfig, NasError, NasErrorCode, NasTestDetails, PROBE_FILE_NAME,
};

pub(crate) struct SmbBackend {
    config: NasConfig,
}

/// `share` plus the sub-directory segments below it.
fn split_root(config: &NasConfig) -> Result<(String, Vec<String>), NasError> {
    let invalid = NasError::new(NasErrorCode::ConfigInvalid);
    let mut segments = root_segments(&config.root_path).map_err(|_| invalid)?;
    if segments.is_empty() {
        return Err(invalid);
    }
    let share = segments.remove(0);
    Ok((share, segments))
}

impl SmbBackend {
    pub(crate) fn new(config: NasConfig) -> Self {
        Self { config }
    }

    fn connect_client(&self) -> Result<smb2::client::SmbClient, NasError> {
        block_on_timed(smb2::client::SmbClient::connect(
            smb2::client::ClientConfig {
                addr: format!("{}:{}", self.config.host, self.config.port.unwrap_or(445)),
                timeout: OP_TIMEOUT,
                username: self.config.username.clone(),
                password: self.config.password.clone(),
                domain: String::new(),
                auto_reconnect: false,
                compression: false,
                dfs_enabled: false,
                dfs_target_overrides: Default::default(),
            },
        ))
        .map_err(|_| NasError::new(NasErrorCode::Timeout))?
        .map_err(super::map_smb_error)
    }

    /// Path of `segments` below the share, or below the configured
    /// sub-directory when `segments` is a single relative file path.
    fn path_below(sub: &[String], segments: &[String]) -> String {
        let mut all = sub.to_vec();
        all.extend(segments.iter().cloned());
        all.join("/")
    }
}

impl NasBackend for SmbBackend {
    fn test_connection(&self) -> Result<NasTestDetails, NasError> {
        let (share, sub) = split_root(&self.config)?;
        let mut client = self.connect_client()?;
        block_on_timed(async {
            let tree = client.connect_share(&share).await?;
            for depth in 1..=sub.len() {
                tree.create_directory(
                    client.connection_mut(),
                    &Self::path_below(&sub[..depth], &[]),
                )
                .await?;
            }
            let probe = Self::path_below(&sub, &[PROBE_FILE_NAME.to_string()]);
            let mut upload = client
                .upload(&tree, &probe, b"sitemark connection probe")
                .await?;
            while upload.write_next_chunk().await? {}
            drop(upload);
            // A successful stat proves the probe was stored; no size check.
            let _ = tree.stat(client.connection_mut(), &probe).await?;
            tree.delete_file(client.connection_mut(), &probe).await?;
            Ok::<(), smb2::Error>(())
        })
        .map_err(|_| NasError::new(NasErrorCode::Timeout))?
        .map_err(super::map_smb_error)?;
        Ok(NasTestDetails::default())
    }

    fn ensure_dirs(&self, segments: &[String]) -> Result<(), NasError> {
        let (share, sub) = split_root(&self.config)?;
        let mut client = self.connect_client()?;
        block_on_timed(async {
            let tree = client.connect_share(&share).await?;
            let mut full = sub.clone();
            full.extend(segments.iter().cloned());
            for depth in 1..=full.len() {
                tree.create_directory(
                    client.connection_mut(),
                    &Self::path_below(&full[..depth], &[]),
                )
                .await?;
            }
            Ok::<(), smb2::Error>(())
        })
        .map_err(|_| NasError::new(NasErrorCode::Timeout))?
        .map_err(super::map_smb_error)?;
        Ok(())
    }

    fn put_file(&self, relative_path: &str, bytes: Vec<u8>) -> Result<(), NasError> {
        let (share, sub) = split_root(&self.config)?;
        let mut client = self.connect_client()?;
        block_on_timed(async {
            let tree = client.connect_share(&share).await?;
            let path = Self::path_below(&sub, &[relative_path.to_string()]);
            let mut upload = client.upload(&tree, &path, &bytes).await?;
            while upload.write_next_chunk().await? {}
            Ok::<(), smb2::Error>(())
        })
        .map_err(|_| NasError::new(NasErrorCode::Timeout))?
        .map_err(super::map_smb_error)?;
        Ok(())
    }

    fn stat_file(&self, relative_path: &str) -> Result<Option<u64>, NasError> {
        let (share, sub) = split_root(&self.config)?;
        let mut client = self.connect_client()?;
        let stat = block_on_timed(async {
            let tree = client.connect_share(&share).await?;
            let path = Self::path_below(&sub, &[relative_path.to_string()]);
            tree.stat(client.connection_mut(), &path).await
        })
        .map_err(|_| NasError::new(NasErrorCode::Timeout))?;
        match stat {
            Ok(info) => Ok(Some(info.size)),
            Err(error) => match error.kind() {
                smb2::ErrorKind::NotFound | smb2::ErrorKind::NotADirectory => Ok(None),
                _ => Err(super::map_smb_error(error)),
            },
        }
    }

    fn delete_file(&self, relative_path: &str) -> Result<(), NasError> {
        let (share, sub) = split_root(&self.config)?;
        let mut client = self.connect_client()?;
        let deleted = block_on_timed(async {
            let tree = client.connect_share(&share).await?;
            let path = Self::path_below(&sub, &[relative_path.to_string()]);
            tree.delete_file(client.connection_mut(), &path).await
        })
        .map_err(|_| NasError::new(NasErrorCode::Timeout))?;
        match deleted {
            Ok(()) => Ok(()),
            Err(error) => match error.kind() {
                smb2::ErrorKind::NotFound => Ok(()),
                _ => Err(super::map_smb_error(error)),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::NasProtocol;
    use super::*;

    fn backend(root: &str) -> SmbBackend {
        SmbBackend::new(NasConfig {
            protocol: NasProtocol::Smb,
            host: "nas.local".to_string(),
            port: None,
            username: "u".to_string(),
            password: "p".to_string(),
            root_path: root.to_string(),
            secure_tls: false,
            accept_invalid_tls: false,
            known_sftp_fingerprint: None,
        })
    }

    #[test]
    fn splits_share_from_sub_directories() {
        let (share, sub) = split_root(&backend("/media/SiteMark").config).expect("valid");
        assert_eq!(share, "media");
        assert_eq!(sub, vec!["SiteMark".to_string()]);
        let (share, sub) = split_root(&backend("/share").config).expect("valid");
        assert_eq!(share, "share");
        assert!(sub.is_empty());
    }

    #[test]
    fn rejects_missing_share() {
        assert!(split_root(&backend("/").config).is_err());
    }

    #[test]
    fn builds_paths_below_share() {
        assert_eq!(SmbBackend::path_below(&[], &["a".to_string()]), "a");
        assert_eq!(
            SmbBackend::path_below(
                &["media".to_string()],
                &["p".to_string(), "1.jpg".to_string()]
            ),
            "media/p/1.jpg"
        );
    }

    #[test]
    fn unreachable_server_maps_to_connection_failed() {
        let backend = SmbBackend::new(NasConfig {
            protocol: NasProtocol::Smb,
            host: "127.0.0.1".to_string(),
            port: Some(1),
            username: "u".to_string(),
            password: "p".to_string(),
            root_path: "/share".to_string(),
            secure_tls: false,
            accept_invalid_tls: false,
            known_sftp_fingerprint: None,
        });
        let error = backend.test_connection().expect_err("must fail");
        assert_eq!(error.code, NasErrorCode::ConnectionFailed);
    }
}
