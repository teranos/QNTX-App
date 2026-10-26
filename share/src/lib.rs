//! Durable iOS share inbox. Reading does not consume; acknowledge explicitly.
use serde::{Deserialize, Serialize};
use tauri::{plugin::{Builder, TauriPlugin}, AppHandle, Manager, Runtime};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_share);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("the screenshot share inbox is only available on iOS")]
    Unsupported,
    #[cfg(target_os = "ios")]
    #[error(transparent)]
    PluginInvoke(#[from] tauri::plugin::mobile::PluginInvokeError),
}
impl Serialize for Error {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_string())
    }
}
#[derive(Debug, Deserialize, Serialize)]
pub struct Image { pub id: String, pub name: String, pub mime: String, pub bytes: u64 }
#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Batch { pub id: String, pub created_at: f64, pub note: String, pub images: Vec<Image> }
#[derive(Debug, Deserialize, Serialize)]
pub struct Pending { pub batches: Vec<Batch> }
#[derive(Debug, Deserialize, Serialize)]
pub struct ImageData { pub mime: String, pub base64: String }

pub struct Share<R: Runtime> {
    #[cfg(target_os = "ios")]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(target_os = "ios"))]
    _marker: std::_marker::PhantomData<fn() -> R>,
}

impl<R: Runtime> Share<R> {
    #[cfg(target_os = "ios")]
    fn pending(&self) -> Result<Pending, Error> {
        self.handle.run_mobile_plugin("pending", ()).map_err(Into::into)
    }
    #[cfg(not(target_os = "ios"))]
    fn pending(&self) -> Result<Pending, Error> { Err(Error::Unsupported) }

    #[cfg(target_os = "ios")]
    fn read_image(&self, id: String, image_id: String) -> Result<ImageData, Error> {
        self.handle.run_mobile_plugin("readImage", serde_json::json!({"id": id, "imageId": image_id})).map_err(Into::into)
    }
    #[cfg(not(target_os = "ios"))]
    fn read_image(&self, _id: String, _image_id: String) -> Result<ImageData, Error> { Err(Error::Unsupported) }

    #[cfg(target_os = "ios")]
    fn acknowledge(&self, id: String) -> Result<(), Error> {
        self.handle.run_mobile_plugin("acknowledge", serde_json::json!({"id": id})).map_err(Into::into)
    }
    #[cfg(not(target_os = "ios"))]
    fn acknowledge(&self, _id: String) -> Result<(), Error> { Err(Error::Unsupported) }
}

#[tauri::command]
async fn pending<R: Runtime>(app: AppHandle<R>) -> Result<Pending, Error> {
    app.state::<Share<R>>().pending()
}

#[tauri::command]
async fn read_image<R: Runtime>(app: AppHandle<R>, id: String, image_id: String) -> Result<ImageData, Error> {
    app.state::<Share<R>>().read_image(id, image_id)
}

#[tauri::command]
async fn acknowledge<R: Runtime>(app: AppHandle<R>, id: String) -> Result<(), Error> {
    app.state::<Share<R>>().acknowledge(id)
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("share")
        .invoke_handler(tauri::generate_handler![pending, read_image, acknowledge])
        .setup(|app, _api| {
            #[cfg(target_os = "ios")]
            let share = Share { handle: _api.register_ios_plugin(init_share)? };
            #[cfg(not(target_os = "ios"))]
            let share = Share::<R> { _marker: std::_marker::PhantomData };
            app.manage(share);
            Ok(())
        }).build()
}
