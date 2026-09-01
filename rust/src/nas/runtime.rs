//! Shared blocking wrapper for the async SFTP/SMB stacks.
//!
//! russh and smb2 are tokio-based while every bridge entry point is a
//! blocking function executed on a worker thread, so all async work is run
//! through one lazily-created runtime instead of building one per call.

use std::sync::OnceLock;
use std::time::Duration;

use tokio::runtime::Runtime;

/// Overall budget for one network operation; uploads of multi-MB watermarked
/// JPEGs on a LAN finish well inside it.
pub(crate) const OP_TIMEOUT: Duration = Duration::from_secs(180);

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

pub(crate) fn block_on<F, T>(future: F) -> T
where
    F: std::future::Future<Output = T>,
{
    let runtime = RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .expect("tokio runtime for NAS sync")
    });
    runtime.block_on(future)
}

/// Runs `future` under the overall operation timeout. The timeout future
/// must be constructed inside a runtime context — `tokio::time::timeout`
/// captures the current timer eagerly — so this wraps instead of the
/// call sites.
pub(crate) fn block_on_timed<F, T>(future: F) -> Result<T, tokio::time::error::Elapsed>
where
    F: std::future::Future<Output = T>,
{
    block_on(async move { tokio::time::timeout(OP_TIMEOUT, future).await })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn block_on_completes_a_future() {
        let value = block_on(async { 21 * 2 });
        assert_eq!(value, 42);
    }

    #[test]
    fn block_on_timed_passes_values_through() {
        let value: Result<u8, _> = block_on_timed(async { 7u8 });
        assert_eq!(value, Ok(7));
    }

    #[test]
    fn timeout_construction_inside_runtime_context() {
        // Regression: constructing tokio::time::timeout outside the runtime
        // panicked with "no reactor running".
        let _ = block_on_timed(async { tokio::time::sleep(Duration::from_millis(1)).await });
    }
}
