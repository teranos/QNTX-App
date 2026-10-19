//! What the phone says about its own power.
//!
//! "Data in sentry about power consumption. Not a specific thing, but all things"
//!
//! One command, `read`, answers with what iOS reports at that moment: battery
//! level and state, Low Power Mode, thermal state. Nothing is chosen here as a
//! cause; this only reads. Off iOS there is nothing to read, and `read` says so.
//!
//! Not exposed to the page: the shell asks, and sends the answer to Sentry.

use serde::Deserialize;
use tauri::{
    plugin::{Builder, TauriPlugin},
    AppHandle, Manager, Runtime,
};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_power);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("this platform has no power state to read")]
    Unsupported,
    #[cfg(target_os = "ios")]
    #[error(transparent)]
    PluginInvoke(#[from] tauri::plugin::mobile::PluginInvokeError),
}

/// UIDevice.BatteryState.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BatteryState {
    Unknown,
    Unplugged,
    Charging,
    Full,
}

impl BatteryState {
    pub fn name(self) -> &'static str {
        match self {
            BatteryState::Unknown => "unknown",
            BatteryState::Unplugged => "unplugged",
            BatteryState::Charging => "charging",
            BatteryState::Full => "full",
        }
    }
}

/// ProcessInfo.ThermalState, in the order Apple declares it.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ThermalState {
    Nominal,
    Fair,
    Serious,
    Critical,
}

impl ThermalState {
    pub fn name(self) -> &'static str {
        match self {
            ThermalState::Nominal => "nominal",
            ThermalState::Fair => "fair",
            ThermalState::Serious => "serious",
            ThermalState::Critical => "critical",
        }
    }

    /// 0 for nominal up to 3 for critical.
    pub fn ordinal(self) -> u8 {
        match self {
            ThermalState::Nominal => 0,
            ThermalState::Fair => 1,
            ThermalState::Serious => 2,
            ThermalState::Critical => 3,
        }
    }
}

/// What the phone said at one moment.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Reading {
    /// 0.0 to 1.0, and -1.0 while the battery state is unknown.
    battery_level: f64,
    pub battery_state: BatteryState,
    pub low_power_mode: bool,
    pub thermal_state: ThermalState,
}

impl Reading {
    /// The battery level, absent while iOS does not know it.
    pub fn battery_level(&self) -> Option<f64> {
        if self.battery_level < 0.0 {
            None
        } else {
            Some(self.battery_level)
        }
    }
}

pub struct Power<R: Runtime> {
    #[cfg(target_os = "ios")]
    handle: tauri::plugin::PluginHandle<R>,
    #[cfg(not(target_os = "ios"))]
    _marker: std::marker::PhantomData<fn() -> R>,
}

impl<R: Runtime> Power<R> {
    #[cfg(target_os = "ios")]
    fn read(&self) -> Result<Reading, Error> {
        self.handle
            .run_mobile_plugin("read", ())
            .map_err(Into::into)
    }

    #[cfg(not(target_os = "ios"))]
    fn read(&self) -> Result<Reading, Error> {
        Err(Error::Unsupported)
    }
}

/// Asks the phone what it says about its power now.
pub fn read<R: Runtime>(app: &AppHandle<R>) -> Result<Reading, Error> {
    app.state::<Power<R>>().read()
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("power")
        .setup(|app, _api| {
            #[cfg(target_os = "ios")]
            let power = Power {
                handle: _api.register_ios_plugin(init_power)?,
            };
            #[cfg(not(target_os = "ios"))]
            let power = Power::<R> {
                _marker: std::marker::PhantomData,
            };
            app.manage(power);
            Ok(())
        })
        .build()
}
