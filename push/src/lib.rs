//! The token Apple gives a phone, for the node to reach it by. The node tells
//! the phone what is about to be said to an agent, fifteen minutes before it is
//! (teranos/QNTX, server/phones.go); the page asks here for the token and hands
//! it to the node in the person's own session. On iOS only: off it, there is none.

use serde::{Deserialize, Serialize};
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_push);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("this platform hands out no push token")]
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

/// The phone's token as Apple gave it, in hex, and the platform it is a token of.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Token {
    pub token: String,
    pub platform: String,
}

pub struct Push<R: Runtime> {
    #[cfg(target_os = "ios")]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(target_os = "ios"))]
    _marker: std::marker::PhantomData<fn() -> R>,
}

impl<R: Runtime> Push<R> {
    #[cfg(target_os = "ios")]
    pub fn token(&self) -> Result<Token, Error> {
        self.handle.run_mobile_plugin("token", ()).map_err(Into::into)
    }

    #[cfg(not(target_os = "ios"))]
    pub fn token(&self) -> Result<Token, Error> {
        Err(Error::Unsupported)
    }
}

#[tauri::command]
async fn token<R: Runtime>(app: AppHandle<R>) -> Result<Token, Error> {
    app.state::<Push<R>>().token()
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("push")
        .invoke_handler(tauri::generate_handler![token])
        .setup(|app, _api| {
            #[cfg(target_os = "ios")]
            let push = Push {
                handle: _api.register_ios_plugin(init_push)?,
            };
            #[cfg(not(target_os = "ios"))]
            let push = Push::<R> {
                _marker: std::marker::PhantomData,
            };
            app.manage(push);
            Ok(())
        })
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_token_is_read_as_the_phone_sends_it() {
        let read: Result<Token, _> = serde_json::from_str(r#"{"token":"aa11","platform":"ios"}"#);
        assert!(matches!(read, Ok(Token { ref token, ref platform }) if token == "aa11" && platform == "ios"));
    }

    #[test]
    fn what_it_could_not_do_reaches_the_page_as_words() {
        let said = serde_json::to_string(&Error::Unsupported);
        assert!(matches!(said.as_deref(), Ok("\"this platform hands out no push token\"")));
    }
}
