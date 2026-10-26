//! "the magic island": an approval (ADR-052 in teranos/QNTX) as a Live
//! Activity on the Dynamic Island and the lock screen, started, moved and
//! ended by the page. The widget in island/widget draws it.
//!
//! `start` resolves with the island's id; `update` and `end` take it. Off iOS
//! there is no island, and each says so.

use serde::{Deserialize, Serialize};
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_island);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("the island is not on this platform")]
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

/// One check on the pull request's head, and the segment it is drawn as:
/// waiting, running, done or failed.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Check {
    pub name: String,
    pub state: String,
}

/// What an approval starts the island with.
#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Start {
    /// owner/repo#n.
    pub pull_request: String,
    pub title: String,
    pub says: String,
    pub checks: Vec<Check>,
}

/// What moves or ends the island: which one, and what stands now.
#[derive(Debug, Deserialize, Serialize)]
pub struct Move {
    pub id: String,
    pub says: String,
    pub checks: Vec<Check>,
}

/// The island started: the id `update` and `end` name it by.
#[derive(Debug, Deserialize, Serialize)]
pub struct Started {
    pub id: String,
}

pub struct Island<R: Runtime> {
    #[cfg(target_os = "ios")]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(target_os = "ios"))]
    _marker: std::marker::PhantomData<fn() -> R>,
}

impl<R: Runtime> Island<R> {
    #[cfg(target_os = "ios")]
    pub fn start(&self, start: Start) -> Result<Started, Error> {
        self.handle
            .run_mobile_plugin("start", start)
            .map_err(Into::into)
    }

    #[cfg(target_os = "ios")]
    pub fn moved(&self, command: &str, moved: Move) -> Result<(), Error> {
        self.handle
            .run_mobile_plugin(command, moved)
            .map_err(Into::into)
    }

    #[cfg(not(target_os = "ios"))]
    pub fn start(&self, _start: Start) -> Result<Started, Error> {
        Err(Error::Unsupported)
    }

    #[cfg(not(target_os = "ios"))]
    pub fn moved(&self, _command: &str, _moved: Move) -> Result<(), Error> {
        Err(Error::Unsupported)
    }
}

#[tauri::command]
async fn start<R: Runtime>(app: AppHandle<R>, start: Start) -> Result<Started, Error> {
    app.state::<Island<R>>().start(start)
}

#[tauri::command]
async fn update<R: Runtime>(app: AppHandle<R>, moved: Move) -> Result<(), Error> {
    app.state::<Island<R>>().moved("update", moved)
}

#[tauri::command]
async fn end<R: Runtime>(app: AppHandle<R>, moved: Move) -> Result<(), Error> {
    app.state::<Island<R>>().moved("end", moved)
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("island")
        .invoke_handler(tauri::generate_handler![start, update, end])
        .setup(|app, _api| {
            #[cfg(target_os = "ios")]
            let island = Island {
                handle: _api.register_ios_plugin(init_island)?,
            };
            #[cfg(not(target_os = "ios"))]
            let island = Island::<R> {
                _marker: std::marker::PhantomData,
            };
            app.manage(island);
            Ok(())
        })
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_approval_starts_the_island_as_the_swift_side_reads_it() {
        let start: Result<Start, _> = serde_json::from_str(
            r#"{"pullRequest":"teranos/QNTX#1396","title":"The extended card says how it is cached","says":"waits on you","checks":[{"name":"Go Build","state":"done"},{"name":"Go Tests","state":"running"}]}"#,
        );
        assert_eq!(
            start.as_ref().map(|s| s.pull_request.as_str()).ok(),
            Some("teranos/QNTX#1396")
        );
        assert_eq!(start.as_ref().map(|s| s.checks.len()).ok(), Some(2));
        let back = start.ok().and_then(|s| serde_json::to_string(&s).ok());
        assert!(back.is_some_and(|json| json.contains(r#""pullRequest":"teranos/QNTX#1396""#)));
    }

    #[cfg(not(target_os = "ios"))]
    #[test]
    fn off_ios_there_is_no_island() {
        let island = Island::<tauri::Wry> {
            _marker: std::marker::PhantomData,
        };
        let started = island.start(Start {
            pull_request: "teranos/QNTX#1".into(),
            title: "t".into(),
            says: "waits on you".into(),
            checks: vec![],
        });
        assert_eq!(
            started.err().map(|err| err.to_string()).as_deref(),
            Some("the island is not on this platform")
        );
    }
}
