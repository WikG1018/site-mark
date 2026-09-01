//! Minimal WebDAV client on top of `ureq`.
//!
//! The v1 surface (decision D-023) needs exactly five verbs: `MKCOL` to grow
//! the directory tree, `PUT` to upload a watermarked JPEG, `HEAD` to verify
//! a stored file, `DELETE` for the connection probe, and the basic-auth and
//! TLS handling ureq already provides. No XML (no `PROPFIND`), no locks, no
//! `MOVE` — deliberately, so the client stays auditable.

use std::time::Duration;

use super::{
    encode_url_segment, root_segments, NasBackend, NasConfig, NasError, NasErrorCode,
    NasTestDetails, PROBE_FILE_NAME,
};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(180);

/// Certificate verifier that accepts anything. Only wired when the user
/// explicitly opts into accepting self-signed NAS certificates; the flag is
/// per-config and defaults to off.
#[cfg(feature = "flutter")]
#[derive(Debug)]
struct AcceptAnyServerCert;

#[cfg(feature = "flutter")]
impl rustls::client::danger::ServerCertVerifier for AcceptAnyServerCert {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        vec![
            rustls::SignatureScheme::RSA_PKCS1_SHA256,
            rustls::SignatureScheme::RSA_PKCS1_SHA384,
            rustls::SignatureScheme::RSA_PKCS1_SHA512,
            rustls::SignatureScheme::RSA_PSS_SHA256,
            rustls::SignatureScheme::RSA_PSS_SHA384,
            rustls::SignatureScheme::RSA_PSS_SHA512,
            rustls::SignatureScheme::ECDSA_NISTP256_SHA256,
            rustls::SignatureScheme::ECDSA_NISTP384_SHA384,
            rustls::SignatureScheme::ED25519,
        ]
    }
}

pub(crate) struct WebdavBackend {
    config: NasConfig,
    agent: ureq::Agent,
}

impl WebdavBackend {
    pub(crate) fn new(config: NasConfig) -> Self {
        let builder = ureq::AgentBuilder::new()
            .timeout_connect(CONNECT_TIMEOUT)
            .timeout(REQUEST_TIMEOUT);
        // Opt-in verifier for self-signed NAS certificates. Only compiled on
        // the Flutter line, where the rustls backend is available.
        #[cfg(feature = "flutter")]
        let builder = if config.accept_invalid_tls {
            let rustls_config = rustls::ClientConfig::builder()
                .dangerous()
                .with_custom_certificate_verifier(std::sync::Arc::new(AcceptAnyServerCert))
                .with_no_client_auth();
            builder.tls_config(std::sync::Arc::new(rustls_config))
        } else {
            builder
        };
        Self {
            config,
            agent: builder.build(),
        }
    }

    fn scheme(&self) -> Result<&'static str, NasError> {
        if !self.config.secure_tls {
            return Ok("http");
        }
        // HTTPS needs the rustls backend, which the HarmonyOS build excludes
        // to stay C-free; SFTP and SMB remain the encrypted options there.
        #[cfg(not(feature = "flutter"))]
        return Err(NasError::new(NasErrorCode::TlsUnsupported));
        #[cfg(feature = "flutter")]
        Ok("https")
    }

    fn base_url(&self) -> Result<String, NasError> {
        let scheme = self.scheme()?;
        let host = &self.config.host;
        // ureq takes credentials from the URL's userinfo and sends Basic
        // auth itself; components are percent-encoded so any byte passes.
        let userinfo = format!(
            "{}:{}@",
            encode_url_segment(&self.config.username),
            encode_url_segment(&self.config.password)
        );
        Ok(match self.config.port {
            Some(port) => format!("{scheme}://{userinfo}{host}:{port}"),
            None => format!("{scheme}://{userinfo}{host}"),
        })
    }

    fn url_for(&self, segments: &[String], collection: bool) -> Result<String, NasError> {
        let mut url = self.base_url()?;
        url.push('/');
        for segment in segments {
            url.push_str(&encode_url_segment(segment));
            url.push('/');
        }
        if !collection {
            url.pop();
        }
        Ok(url)
    }

    /// Full URL for a file stored under the configured root.
    fn file_url(&self, relative_path: &str) -> Result<String, NasError> {
        let mut segments = root_segments(&self.config.root_path)?;
        segments.extend(relative_path.split('/').map(str::to_string));
        self.url_for(&segments, false)
    }

    fn map_transport(transport: &ureq::Transport) -> NasError {
        // TLS failures surface under multiple kinds ("tls connection init
        // failed" lands in ConnectionFailed); the message is the only
        // reliable distinguisher. These strings never reach the UI.
        let message = transport
            .message()
            .map(|message| message.to_lowercase())
            .unwrap_or_default();
        if message.contains("tls") || message.contains("certificate") {
            return NasError::new(NasErrorCode::TlsError);
        }
        match transport.kind() {
            ureq::ErrorKind::Dns | ureq::ErrorKind::ConnectionFailed => {
                NasError::new(NasErrorCode::ConnectionFailed)
            }
            // Socket timeouts are folded into Io; the message tells them
            // apart from other I/O failures.
            ureq::ErrorKind::Io => {
                if message.contains("timed out") {
                    NasError::new(NasErrorCode::Timeout)
                } else {
                    NasError::new(NasErrorCode::ConnectionFailed)
                }
            }
            _ => NasError::new(NasErrorCode::ProtocolError),
        }
    }

    fn map_response_error(error: ureq::Error) -> NasError {
        match error {
            ureq::Error::Status(status, _) => Self::map_status(status),
            ureq::Error::Transport(transport) => Self::map_transport(&transport),
        }
    }

    fn map_status(status: u16) -> NasError {
        match status {
            401 | 403 => NasError::new(NasErrorCode::AuthFailed),
            507 => NasError::new(NasErrorCode::QuotaInsufficient),
            _ => NasError::new(NasErrorCode::ProtocolError),
        }
    }
}

impl NasBackend for WebdavBackend {
    fn test_connection(&self) -> Result<NasTestDetails, NasError> {
        // The probe exercises exactly the operations a real upload needs —
        // MKCOL walk, PUT, HEAD and DELETE — and leaves nothing behind.
        self.ensure_dirs(&[])?;
        self.put_file(PROBE_FILE_NAME, b"sitemark connection probe".to_vec())?;
        let size = self.stat_file(PROBE_FILE_NAME)?;
        if size.is_none_or(|bytes| bytes == 0) {
            return Err(NasError::new(NasErrorCode::ProtocolError));
        }
        self.delete_file(PROBE_FILE_NAME)?;
        Ok(NasTestDetails::default())
    }

    fn ensure_dirs(&self, segments: &[String]) -> Result<(), NasError> {
        // `segments` are relative to the root; the root itself is part of
        // the tree that has to exist, so it is walked first.
        let mut full = root_segments(&self.config.root_path)?;
        full.extend(segments.iter().cloned());
        for depth in 1..=full.len() {
            let url = self.url_for(&full[..depth], true)?;
            // ureq reports 4xx/5xx as Err(Status); a 405 (collection
            // already exists) is success here, so errors are matched, not
            // pre-converted by `map_err`.
            match self.agent.request("MKCOL", &url).call() {
                Ok(response) => match response.status() {
                    200..=299 => {}
                    status => return Err(Self::map_status(status)),
                },
                Err(ureq::Error::Status(405, _)) => {}
                Err(ureq::Error::Status(status, _)) => return Err(Self::map_status(status)),
                Err(other) => return Err(Self::map_response_error(other)),
            }
        }
        Ok(())
    }

    fn put_file(&self, relative_path: &str, bytes: Vec<u8>) -> Result<(), NasError> {
        let url = self.file_url(relative_path)?;
        let response = self
            .agent
            .put(&url)
            .send(&bytes[..])
            .map_err(Self::map_response_error)?;
        match response.status() {
            200..=299 => Ok(()),
            status => Err(Self::map_status(status)),
        }
    }

    fn stat_file(&self, relative_path: &str) -> Result<Option<u64>, NasError> {
        let url = self.file_url(relative_path)?;
        let response = match self.agent.head(&url).call() {
            Ok(response) => response,
            Err(ureq::Error::Status(404, _)) => return Ok(None),
            Err(other) => return Err(Self::map_response_error(other)),
        };
        match response.status() {
            200..=299 => Ok(response
                .header("Content-Length")
                .and_then(|value| value.parse::<u64>().ok())),
            404 => Ok(None),
            status => Err(Self::map_status(status)),
        }
    }

    fn delete_file(&self, relative_path: &str) -> Result<(), NasError> {
        let url = self.file_url(relative_path)?;
        // ureq reports 4xx/5xx as Err(Status); 404 means already absent.
        match self.agent.request("DELETE", &url).call() {
            Ok(response) => match response.status() {
                200..=299 => Ok(()),
                status => Err(Self::map_status(status)),
            },
            Err(ureq::Error::Status(404, _)) => Ok(()),
            Err(ureq::Error::Status(status, _)) => Err(Self::map_status(status)),
            Err(other) => Err(Self::map_response_error(other)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::NasProtocol;
    use super::*;
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpListener;
    use std::thread;

    /// A scripted WebDAV-ish server: consumes one HTTP request per
    /// connection and answers with the next canned response.
    fn spawn_scripted_server(responses: Vec<(String, String)>) -> (String, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr").to_string();
        let handle = thread::spawn(move || {
            for (expected_prefix, response) in responses {
                let (stream, _) = match listener.accept() {
                    Ok(accepted) => accepted,
                    Err(_) => return,
                };
                let mut reader = BufReader::new(stream);
                let mut request_line = String::new();
                if reader.read_line(&mut request_line).is_err() {
                    return;
                }
                let mut content_length = 0usize;
                let mut expects_continue = false;
                loop {
                    let mut line = String::new();
                    if reader.read_line(&mut line).is_err() {
                        return;
                    }
                    if line == "\r\n" || line.is_empty() {
                        break;
                    }
                    let lower = line.to_ascii_lowercase();
                    if let Some(value) = lower.strip_prefix("content-length:") {
                        content_length = value.trim().parse().unwrap_or(0);
                    }
                    if lower.starts_with("expect:") && lower.contains("100-continue") {
                        expects_continue = true;
                    }
                }
                // ureq sends Expect: 100-continue for non-trivial bodies and
                // waits for the interim response before uploading them.
                if expects_continue && content_length > 0 {
                    let mut stream = reader.into_inner();
                    let _ = stream.write_all(b"HTTP/1.1 100 Continue\r\n\r\n");
                    let _ = stream.flush();
                    let mut reader = BufReader::new(stream);
                    let mut body = vec![0u8; content_length];
                    let _ = reader.read_exact(&mut body);
                    let mut stream = reader.into_inner();
                    let _ = stream.write_all(response.as_bytes());
                    let _ = stream.flush();
                    drain(&mut stream);
                    continue;
                }
                if content_length > 0 {
                    let mut body = vec![0u8; content_length];
                    let _ = reader.read_exact(&mut body);
                }
                assert!(
                    request_line.starts_with(&expected_prefix),
                    "expected request {expected_prefix:?}, got {request_line:?}"
                );
                let mut stream = reader.into_inner();
                let _ = stream.write_all(response.as_bytes());
                let _ = stream.flush();
                drain(&mut stream);
            }
        });
        (addr, handle)
    }

    /// Closing a socket with unread receive-buffer bytes sends a RST that
    /// can swallow the response just written; drain until the client hangs
    /// up instead.
    fn drain(stream: &mut std::net::TcpStream) {
        let mut sink = [0u8; 512];
        while let Ok(read) = stream.read(&mut sink) {
            if read == 0 {
                break;
            }
        }
    }

    fn response(status_line: &str) -> String {
        format!("HTTP/1.1 {status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    }

    fn backend_for(addr: &str, secure_tls: bool) -> WebdavBackend {
        let (host, port) = addr.split_once(':').expect("host:port");
        WebdavBackend::new(NasConfig {
            protocol: NasProtocol::Webdav,
            host: host.to_string(),
            port: Some(port.parse().expect("port")),
            username: "user".to_string(),
            password: "pass".to_string(),
            root_path: "/SiteMark".to_string(),
            secure_tls,
            accept_invalid_tls: false,
            known_sftp_fingerprint: None,
        })
    }

    #[cfg(feature = "flutter")]
    #[test]
    fn https_with_plain_http_server_reports_tls_error() {
        // A plain-HTTP server cannot complete a TLS handshake, so the client
        // must surface a TLS category instead of a raw transport message.
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr").to_string();
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                drop(stream);
            }
        });
        let backend = backend_for(&addr, true);
        let error = backend.test_connection().expect_err("tls must fail");
        assert_eq!(error.code, NasErrorCode::TlsError);
    }

    #[cfg(not(feature = "flutter"))]
    #[test]
    fn https_requested_without_tls_feature_is_unsupported() {
        // On the HarmonyOS line (no TLS feature) HTTPS must fail fast with a
        // dedicated category instead of a confusing transport error.
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr").to_string();
        drop(listener);
        let backend = backend_for(&addr, true);
        let error = backend.test_connection().expect_err("must fail");
        assert_eq!(error.code, NasErrorCode::TlsUnsupported);
    }

    #[test]
    fn probe_writes_heads_and_deletes() {
        let probe = format!("/SiteMark/{PROBE_FILE_NAME}");
        let (addr, server) = spawn_scripted_server(vec![
            (
                "MKCOL /SiteMark/ HTTP/1.1".to_string(),
                response("201 Created"),
            ),
            (format!("PUT {probe}"), response("201 Created")),
            (
                format!("HEAD {probe}"),
                "HTTP/1.1 200 OK\r\nContent-Length: 26\r\nConnection: close\r\n\r\n".to_string(),
            ),
            (format!("DELETE {probe}"), response("204 No Content")),
        ]);
        let backend = backend_for(&addr, false);
        let details = backend.test_connection().expect("probe must succeed");
        assert_eq!(details, NasTestDetails::default());
        server.join().expect("server thread");
    }

    #[test]
    fn unauthorized_put_maps_to_auth_failed() {
        // test_connection starts with the MKCOL walk, so the 401 arrives there.
        let (addr, server) = spawn_scripted_server(vec![(
            "MKCOL /SiteMark/ HTTP/1.1".to_string(),
            response("401 Unauthorized"),
        )]);
        let backend = backend_for(&addr, false);
        let error = backend.test_connection().expect_err("auth must fail");
        assert_eq!(error.code, NasErrorCode::AuthFailed);
        server.join().expect("server thread");
    }

    #[test]
    fn ensure_dirs_walks_levels_and_ignores_405() {
        let (addr, server) = spawn_scripted_server(vec![
            (
                "MKCOL /SiteMark/ HTTP/1.1".to_string(),
                response("405 Method Not Allowed"),
            ),
            (
                "MKCOL /SiteMark/%E4%BA%91%E6%B9%96%E4%B9%8B%E5%9F%8E/ HTTP/1.1".to_string(),
                response("201 Created"),
            ),
        ]);
        let backend = backend_for(&addr, false);
        backend
            .ensure_dirs(&["云湖之城".to_string()])
            .expect("mkcol walk must succeed");
        server.join().expect("server thread");
    }

    #[test]
    fn put_file_uploads_body_and_stat_reads_length() {
        let (addr, server) = spawn_scripted_server(vec![
            (
                "PUT /SiteMark/p/003.jpg".to_string(),
                response("201 Created"),
            ),
            (
                "HEAD /SiteMark/p/003.jpg".to_string(),
                "HTTP/1.1 200 OK\r\nContent-Length: 12345\r\nConnection: close\r\n\r\n".to_string(),
            ),
        ]);
        let backend = backend_for(&addr, false);
        backend
            .put_file("p/003.jpg", vec![0xAB; 3210])
            .expect("put must succeed");
        let size = backend.stat_file("p/003.jpg").expect("stat must succeed");
        assert_eq!(size, Some(12345));
        server.join().expect("server thread");
    }

    #[test]
    fn stat_missing_file_is_none() {
        let (addr, server) = spawn_scripted_server(vec![(
            "HEAD /SiteMark/p/404.jpg".to_string(),
            response("404 Not Found"),
        )]);
        let backend = backend_for(&addr, false);
        let size = backend.stat_file("p/404.jpg").expect("stat must succeed");
        assert_eq!(size, None);
        server.join().expect("server thread");
    }

    #[test]
    fn quota_error_maps_to_dedicated_category() {
        let (addr, server) = spawn_scripted_server(vec![(
            "PUT ".to_string(),
            response("507 Insufficient Storage"),
        )]);
        let backend = backend_for(&addr, false);
        let error = backend
            .put_file("p/x.jpg", vec![0; 8])
            .expect_err("must fail");
        assert_eq!(error.code, NasErrorCode::QuotaInsufficient);
        server.join().expect("server thread");
    }

    #[test]
    fn unreachable_server_maps_to_connection_failed() {
        // Port 1 on localhost: nothing listens, connect fails fast.
        let backend = WebdavBackend::new(NasConfig {
            protocol: NasProtocol::Webdav,
            host: "127.0.0.1".to_string(),
            port: Some(1),
            username: "u".to_string(),
            password: "p".to_string(),
            root_path: "/".to_string(),
            secure_tls: false,
            accept_invalid_tls: false,
            known_sftp_fingerprint: None,
        });
        let error = backend.test_connection().expect_err("must fail");
        assert_eq!(error.code, NasErrorCode::ConnectionFailed);
    }
}
