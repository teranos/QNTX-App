//! The shake the phone feels, and the snapshot it carries: README.md says what
//! the page sees. The accelerometer is read natively, CoreMotion on iOS and
//! SensorManager on Android, neither behind a prompt.

use serde::{Deserialize, Serialize};
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_shake);

/// The event a shake reaches the page as, payload [`Shaken`].
pub const EVENT: &str = "shake";

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("the shake is not on this platform")]
    Unsupported,
    #[cfg(any(target_os = "ios", target_os = "android"))]
    #[error(transparent)]
    PluginInvoke(#[from] tauri::plugin::mobile::PluginInvokeError),
}

impl Serialize for Error {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_string())
    }
}

/// What a shake carries: the moment it happened, unix milliseconds.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Shaken {
    pub at: u64,
}

/// The web view as the page sees it: a PNG data URL, and its size in pixels.
#[derive(Debug, Deserialize, Serialize)]
pub struct Snapshot {
    pub png: String,
    pub width: u32,
    pub height: u32,
}

/// What the native side is handed once: the channel every shake comes down.
#[cfg(any(target_os = "ios", target_os = "android"))]
#[derive(Serialize)]
struct Watch {
    handler: tauri::ipc::Channel<serde_json::Value>,
}

pub struct Shake<R: Runtime> {
    #[cfg(any(target_os = "ios", target_os = "android"))]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    _marker: std::marker::PhantomData<fn() -> R>,
}

impl<R: Runtime> Shake<R> {
    #[cfg(any(target_os = "ios", target_os = "android"))]
    pub fn snapshot(&self) -> Result<Snapshot, Error> {
        self.handle
            .run_mobile_plugin("snapshot", ())
            .map_err(Into::into)
    }

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    pub fn snapshot(&self) -> Result<Snapshot, Error> {
        Err(Error::Unsupported)
    }
}

#[tauri::command]
async fn snapshot<R: Runtime>(app: AppHandle<R>) -> Result<Snapshot, Error> {
    app.state::<Shake<R>>().snapshot()
}

/// Hands the native side the channel, and emits what comes down it to the page.
#[cfg(any(target_os = "ios", target_os = "android"))]
fn watch<R: Runtime>(
    app: &AppHandle<R>,
    handle: &tauri::plugin::PluginHandle<R>,
) -> Result<(), Error> {
    use tauri::{
        ipc::{Channel, InvokeResponseBody},
        Emitter,
    };

    let page = app.clone();
    let handler = Channel::<serde_json::Value>::new(move |body| {
        let shaken: Shaken = match body {
            InvokeResponseBody::Json(json) => serde_json::from_str(&json)?,
            InvokeResponseBody::Raw(bytes) => serde_json::from_slice(&bytes)?,
        };
        page.emit(EVENT, shaken)
    });
    handle.run_mobile_plugin::<()>("watch", Watch { handler })?;
    Ok(())
}

/// The Kotlin package the Android side lives in: android/src/main/java/ShakePlugin.kt.
#[cfg(target_os = "android")]
const ANDROID_PACKAGE: &str = "qntx.shake";

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("shake")
        .invoke_handler(tauri::generate_handler![snapshot])
        .setup(|app, _api| {
            #[cfg(target_os = "ios")]
            let handle = _api.register_ios_plugin(init_shake)?;
            #[cfg(target_os = "android")]
            let handle = _api.register_android_plugin(ANDROID_PACKAGE, "ShakePlugin")?;

            // A phone with no accelerometer still runs the app; it feels no shake.
            #[cfg(any(target_os = "ios", target_os = "android"))]
            if let Err(err) = watch(app, &handle) {
                eprintln!("the shake is not watched: {err}");
            }

            #[cfg(any(target_os = "ios", target_os = "android"))]
            let shake = Shake { handle };
            #[cfg(not(any(target_os = "ios", target_os = "android")))]
            let shake = Shake::<R> {
                _marker: std::marker::PhantomData,
            };
            app.manage(shake);
            Ok(())
        })
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_event_is_shake_and_carries_the_moment() {
        let json = serde_json::to_string(&Shaken { at: 1_700_000_000_000 });
        assert_eq!(EVENT, "shake");
        assert_eq!(json.ok().as_deref(), Some(r#"{"at":1700000000000}"#));
    }

    #[test]
    fn a_snapshot_is_a_png_data_url_with_its_size() {
        let shape: Result<Snapshot, _> = serde_json::from_str(
            r#"{"png":"data:image/png;base64,iVBORw0KGgo=","width":3,"height":2}"#,
        );
        let Ok(shape) = shape else {
            return assert!(false, "the snapshot shape did not parse");
        };
        assert!(shape.png.starts_with("data:image/png;base64,"));
        assert_eq!((shape.width, shape.height), (3, 2));
    }

    #[cfg(not(any(target_os = "ios", target_os = "android")))]
    #[test]
    fn off_a_phone_the_snapshot_is_unsupported() {
        let shake = Shake::<tauri::Wry> {
            _marker: std::marker::PhantomData,
        };
        let unsupported = shake.snapshot().err().map(|err| err.to_string());
        assert_eq!(
            unsupported.as_deref(),
            Some("the shake is not on this platform")
        );
    }
}
