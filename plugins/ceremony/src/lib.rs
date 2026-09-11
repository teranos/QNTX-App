//! The provider ceremony, in the sheet iOS gives a web sign-in.
//!
//! The App's page lives at a scheme, so a provider's page inside its WebView
//! has no Safari session, no autofill and no passkey. The ceremony ran in
//! Safari instead, and Safari handed the ticket back through qntx:// as a deep
//! link: an app switch out, an app switch back, and a listener in between.
//!
//! "Can we please for iPhone just do the most standard boring native thing?"
//!
//! ASWebAuthenticationSession is that thing: a system sheet inside the App,
//! backed by Safari's cookies and passkeys, that hands the callback URL
//! straight back. One command, `run`, resolves with the URL the node sent the
//! sheet to. Off iOS there is no sheet, and `run` says so.

use serde::{Deserialize, Serialize};
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_ceremony);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("the ceremony sheet is not on this platform")]
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

/// What the sheet is given: where to go, and the scheme it comes back on.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Run {
    url: String,
    scheme: String,
}

/// Where the sheet came back: the URL the node sent it to, ticket and all.
#[derive(Debug, Deserialize, Serialize)]
pub struct CameBack {
    pub url: String,
}

pub struct Ceremony<R: Runtime> {
    #[cfg(target_os = "ios")]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(target_os = "ios"))]
    _marker: std::marker::PhantomData<fn() -> R>,
}

impl<R: Runtime> Ceremony<R> {
    #[cfg(target_os = "ios")]
    pub fn run(&self, url: String, scheme: String) -> Result<CameBack, Error> {
        self.handle
            .run_mobile_plugin("run", Run { url, scheme })
            .map_err(Into::into)
    }

    #[cfg(not(target_os = "ios"))]
    pub fn run(&self, _url: String, _scheme: String) -> Result<CameBack, Error> {
        Err(Error::Unsupported)
    }
}

#[tauri::command]
async fn run<R: Runtime>(
    app: AppHandle<R>,
    url: String,
    scheme: String,
) -> Result<CameBack, Error> {
    app.state::<Ceremony<R>>().run(url, scheme)
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("ceremony")
        .invoke_handler(tauri::generate_handler![run])
        .setup(|app, _api| {
            #[cfg(target_os = "ios")]
            let ceremony = Ceremony {
                handle: _api.register_ios_plugin(init_plugin_ceremony)?,
            };
            #[cfg(not(target_os = "ios"))]
            let ceremony = Ceremony::<R> {
                _marker: std::marker::PhantomData,
            };
            app.manage(ceremony);
            Ok(())
        })
        .build()
}
