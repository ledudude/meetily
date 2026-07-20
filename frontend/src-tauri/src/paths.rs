//! Portable-aware path resolution.
//!
//! Resolution order for the app data root:
//!   1. `MEETILY_DATA_DIR` environment variable (absolute path preferred).
//!   2. `portable.txt` marker file located next to the executable
//!      -> use `<exe_dir>/data` (portable mode).
//!   3. Fallback -> Tauri `app_data_dir()` (per-user OS default).
//!
//! Modules that already have an `AppHandle` should call [`data_dir`] /
//! [`models_dir`] / [`recordings_dir`]. Modules invoked before Tauri is
//! initialised (or without an `AppHandle`) can use [`portable_root`] to opt
//! into portable overrides without breaking the per-user default.

use std::path::PathBuf;
use std::sync::OnceLock;
use tauri::{AppHandle, Manager, Runtime};

static DATA_ROOT: OnceLock<PathBuf> = OnceLock::new();

/// Portable data root when the app is running in portable mode.
///
/// Returns `None` when neither `MEETILY_DATA_DIR` nor `portable.txt` is
/// present, meaning the caller should use its normal per-user default.
pub fn portable_root() -> Option<PathBuf> {
    // 1. Explicit environment override wins.
    if let Ok(dir) = std::env::var("MEETILY_DATA_DIR") {
        let trimmed = dir.trim();
        if !trimmed.is_empty() {
            return Some(PathBuf::from(trimmed));
        }
    }

    // 2. `portable.txt` beside the executable enables portable mode.
    let exe = std::env::current_exe().ok()?;
    let exe_dir = exe.parent()?.to_path_buf();
    if exe_dir.join("portable.txt").is_file() {
        return Some(exe_dir.join("data"));
    }

    None
}

/// Whether the app is currently running in portable mode.
pub fn is_portable() -> bool {
    portable_root().is_some()
}

/// Resolved application data root.
///
/// Uses [`portable_root`] when available and falls back to
/// `AppHandle::path().app_data_dir()` otherwise. The directory is created on
/// first access so callers can immediately write to it.
pub fn data_dir<R: Runtime>(app: &AppHandle<R>) -> PathBuf {
    let dir = DATA_ROOT
        .get_or_init(|| match portable_root() {
            Some(p) => p,
            None => app
                .path()
                .app_data_dir()
                .expect("failed to resolve app_data_dir"),
        })
        .clone();
    if !dir.exists() {
        if let Err(e) = std::fs::create_dir_all(&dir) {
            log::warn!("failed to create data dir {}: {}", dir.display(), e);
        }
    }
    dir
}

/// `<data_dir>/models` — shared root for whisper/parakeet/summary models.
pub fn models_dir<R: Runtime>(app: &AppHandle<R>) -> PathBuf {
    let dir = data_dir(app).join("models");
    if !dir.exists() {
        let _ = std::fs::create_dir_all(&dir);
    }
    dir
}

/// `<data_dir>/recordings` — used when the app is in portable mode.
pub fn recordings_dir<R: Runtime>(app: &AppHandle<R>) -> PathBuf {
    let dir = data_dir(app).join("recordings");
    if !dir.exists() {
        let _ = std::fs::create_dir_all(&dir);
    }
    dir
}

/// Compute the on-disk path for a tauri-plugin-store JSON file.
///
/// * Portable mode -> `<data_dir>/<name>` (absolute, kept alongside the DB).
/// * Otherwise     -> the plain `name` (the plugin resolves it to its default
///                    per-user location, preserving the existing behaviour).
///
/// Using this helper keeps the plugin's default path logic intact for regular
/// installs while making portable builds fully self-contained.
pub fn store_path<R: Runtime>(app: &AppHandle<R>, name: &str) -> std::path::PathBuf {
    if is_portable() {
        data_dir(app).join(name)
    } else {
        std::path::PathBuf::from(name)
    }
}