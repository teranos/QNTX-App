//! The chat with an agent, drawn natively on iOS by Exyte Chat: the phone's own
//! text field and keyboard. The page keeps the conversation: it opens the chat,
//! shows it what was said, and is told down the channel what was typed.
//! Off iOS each command says it cannot, and the page keeps its own chat.

use serde::{Deserialize, Serialize};
use tauri::{
    ipc::Channel,
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_chat);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("the native chat is only on iOS")]
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

/// One thing said, as the chat shows it: whose it is, and when (unix milliseconds).
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Said {
    pub id: String,
    pub text: String,
    pub mine: bool,
    pub at: f64,
}

/// What the chat opens with: its title, and the channel what is typed comes down.
#[cfg(target_os = "ios")]
#[derive(Serialize)]
struct Open {
    title: String,
    handler: Channel<serde_json::Value>,
}

/// The conversation as it stands, and whether the agent is answering.
#[derive(Debug, Deserialize, Serialize)]
pub struct Shown {
    pub messages: Vec<Said>,
    pub answering: bool,
}

pub struct Chat<R: Runtime> {
    #[cfg(target_os = "ios")]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(target_os = "ios"))]
    _marker: std::marker::PhantomData<fn() -> R>,
}

impl<R: Runtime> Chat<R> {
    #[cfg(target_os = "ios")]
    fn open(&self, title: String, handler: Channel<serde_json::Value>) -> Result<(), Error> {
        self.handle
            .run_mobile_plugin("open", Open { title, handler })
            .map_err(Into::into)
    }
    #[cfg(not(target_os = "ios"))]
    fn open(&self, _title: String, _handler: Channel<serde_json::Value>) -> Result<(), Error> {
        Err(Error::Unsupported)
    }

    #[cfg(target_os = "ios")]
    fn show(&self, shown: Shown) -> Result<(), Error> {
        self.handle
            .run_mobile_plugin("show", shown)
            .map_err(Into::into)
    }
    #[cfg(not(target_os = "ios"))]
    fn show(&self, _shown: Shown) -> Result<(), Error> {
        Err(Error::Unsupported)
    }

    #[cfg(target_os = "ios")]
    fn close(&self) -> Result<(), Error> {
        self.handle
            .run_mobile_plugin("close", ())
            .map_err(Into::into)
    }
    #[cfg(not(target_os = "ios"))]
    fn close(&self) -> Result<(), Error> {
        Err(Error::Unsupported)
    }
}

#[tauri::command]
async fn open<R: Runtime>(
    app: AppHandle<R>,
    title: String,
    handler: Channel<serde_json::Value>,
) -> Result<(), Error> {
    app.state::<Chat<R>>().open(title, handler)
}

#[tauri::command]
async fn show<R: Runtime>(
    app: AppHandle<R>,
    messages: Vec<Said>,
    answering: bool,
) -> Result<(), Error> {
    app.state::<Chat<R>>().show(Shown {
        messages,
        answering,
    })
}

#[tauri::command]
async fn close<R: Runtime>(app: AppHandle<R>) -> Result<(), Error> {
    app.state::<Chat<R>>().close()
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("chat")
        .invoke_handler(tauri::generate_handler![open, show, close])
        .setup(|app, _api| {
            #[cfg(target_os = "ios")]
            let chat = Chat {
                handle: _api.register_ios_plugin(init_chat)?,
            };
            #[cfg(not(target_os = "ios"))]
            let chat = Chat::<R> {
                _marker: std::marker::PhantomData,
            };
            app.manage(chat);
            Ok(())
        })
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn what_is_shown_is_the_messages_and_whether_it_answers() {
        let shown: Result<Shown, _> = serde_json::from_str(
            r#"{"messages":[{"id":"0","text":"hi","mine":true,"at":1700000000000}],"answering":true}"#,
        );
        let Ok(shown) = shown else {
            return assert!(false, "the shown shape did not parse");
        };
        assert!(shown.answering);
        assert_eq!(shown.messages.len(), 1);
        assert!(shown.messages.iter().all(|said| said.mine && said.text == "hi"));
    }

    #[cfg(not(target_os = "ios"))]
    #[test]
    fn off_ios_it_says_it_cannot() {
        let chat = Chat::<tauri::Wry> {
            _marker: std::marker::PhantomData,
        };
        let said = chat.close().err().map(|err| err.to_string());
        assert_eq!(said.as_deref(), Some("the native chat is only on iOS"));
    }
}
