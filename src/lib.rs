// Library entry point for mobile platforms (iOS/Android)
// Desktop builds use src/main.rs directly

// iOS-specific features (biometrics, permissions, etc.)
#[cfg(target_os = "ios")]
mod ios;

// Android-specific features (biometrics, permissions, etc.)
#[cfg(target_os = "android")]
mod android;

// For mobile platforms, we need to export the app initialization
// Desktop continues to use the main.rs binary

// The entry point answers to nobody, so a Tauri that will not run ends the
// process with the reason on stderr, which iOS keeps in the device log.
fn ran(result: tauri::Result<()>) {
    if let Err(err) = result {
        eprintln!("tauri application did not run: {err}");
        sentry::capture_error(&err);
        // exit runs no destructors, so the guard never flushes; this does.
        if let Some(client) = sentry::Hub::current().client() {
            let flushed = client.close(Some(std::time::Duration::from_secs(2)));
            if !flushed {
                eprintln!("the failure above did not reach sentry within 2s");
            }
        }
        std::process::exit(1);
    }
}

// A DSN is an ingest key: it can only write, which is why it stands here as a
// literal, the way the node's does in am.toml. The release is the QNTX tag the
// workflow built from, so an event says which frontend it was carrying.
const SENTRY_DSN: &str = "https://a67b1d3869b2fadc7a314746a35039f4@o4511990405464064.ingest.de.sentry.io/4512033476902992";

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut options = sentry::ClientOptions::default();
    options.release = option_env!("QNTX_TAG").map(Into::into).or_else(|| sentry::release_name!());
    options.send_default_pii = true;
    let _sentry = sentry::init((SENTRY_DSN, options));

    // Initialize platform-specific features
    #[cfg(target_os = "ios")]
    ios::init();

    #[cfg(target_os = "android")]
    android::init();

    // Build mobile app (no sidecar, no desktop-only features)
    #[cfg(target_os = "ios")]
    {
        ran(tauri::Builder::default()
            .plugin(tauri_plugin_shell::init())
            .plugin(tauri_plugin_opener::init())
            .plugin(tauri_plugin_notification::init())
            // qntx:// opened by Safari lands here as a deep-link://new-url event.
            .plugin(tauri_plugin_deep_link::init())
            // The ceremony in the system sheet, back without leaving the app.
            .plugin(sheet::init())
            .invoke_handler(tauri::generate_handler![
                ios::ios_authenticate_biometric,
                ios::ios_biometric_available,
                ios::ios_request_permissions,
                ios::ios_device_info,
            ])
            .run(tauri::generate_context!()));
    }

    #[cfg(target_os = "android")]
    {
        // NOTE: tauri_plugin_notification requires POST_NOTIFICATIONS permission on Android 13+
        // Ensure android_request_permissions is called before sending notifications
        ran(tauri::Builder::default()
            .plugin(tauri_plugin_shell::init())
            .plugin(tauri_plugin_opener::init())
            .plugin(tauri_plugin_notification::init())
            .plugin(sheet::init())
            .invoke_handler(tauri::generate_handler![
                android::android_authenticate_biometric,
                android::android_biometric_available,
                android::android_request_permissions,
                android::android_device_info,
            ])
            .run(tauri::generate_context!()));
    }

    // Fallback for other platforms (shouldn't be reached in practice)
    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    {
        ran(tauri::Builder::default()
            .plugin(tauri_plugin_shell::init())
            .plugin(tauri_plugin_opener::init())
            .plugin(tauri_plugin_notification::init())
            .plugin(sheet::init())
            .run(tauri::generate_context!()));
    }
}
