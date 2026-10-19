//! What the phone says about its own power.
//!
//! "Data in sentry about power consumption. Not a specific thing, but all things"
//!
//! One command, `read`, answers with what iOS reports at that moment: battery
//! level and state, Low Power Mode, thermal state, and this process's memory
//! footprint and CPU time. Nothing is chosen here as a cause; this only reads.
//! Off iOS there is nothing to read, and `read` says so.
//!
//! The process is the app's. The page runs in the web view's own process, which
//! these do not include.
//!
//! Not exposed to the page: the shell asks, and sends the answer to Sentry.

use std::time::Instant;

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
    /// This process's `phys_footprint` in bytes, absent when the call failed.
    pub memory_footprint: Option<u64>,
    /// User and system CPU time of this process since it started, in seconds,
    /// absent when the call failed.
    pub cpu_seconds: Option<f64>,
}

/// CPU use averaged over the time between two readings.
#[derive(Debug, PartialEq)]
pub struct Average {
    /// Percent of one core, so it passes 100 when more than one is busy.
    pub percent: f64,
    /// The wall time the average is over.
    pub seconds: f64,
}

/// "A selection range of 15 seconds or more": WebKit counts CPU use as the
/// change in CPU time over the change in monotonic time (`CPUTime::percentageCPUUsageSince`).
/// This is that, between one reading and the next.
#[derive(Default)]
pub struct Sampler {
    last: Option<(Instant, f64)>,
}

impl Sampler {
    /// The average since the last reading. None for the first reading, when no
    /// time passed, and when the CPU time went backwards.
    pub fn average(&mut self, at: Instant, cpu_seconds: f64) -> Option<Average> {
        let before = self.last.replace((at, cpu_seconds));
        let (then, was) = before?;
        let wall = at.duration_since(then).as_secs_f64();
        let used = cpu_seconds - was;
        if wall <= 0.0 || used < 0.0 {
            return None;
        }
        Some(Average {
            percent: used * 100.0 / wall,
            seconds: wall,
        })
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn after(base: Instant, seconds: u64) -> Instant {
        base.checked_add(Duration::from_secs(seconds)).unwrap_or(base)
    }

    // The first reading has nothing to be averaged against.
    #[test]
    fn the_first_reading_says_no_average() {
        let mut sampler = Sampler::default();
        assert_eq!(sampler.average(Instant::now(), 4.0), None);
    }

    // 3 seconds of CPU in 300 is 1%: under what WebKit asks of an idle page.
    #[test]
    fn cpu_time_over_wall_time_is_a_percent() {
        let base = Instant::now();
        let mut sampler = Sampler::default();
        assert_eq!(sampler.average(base, 10.0), None);
        let got = sampler.average(after(base, 300), 13.0);
        assert_eq!(got, Some(Average { percent: 1.0, seconds: 300.0 }));
    }

    // Two cores busy for the whole time is 200% of one.
    #[test]
    fn more_than_one_core_passes_a_hundred() {
        let base = Instant::now();
        let mut sampler = Sampler::default();
        assert_eq!(sampler.average(base, 0.0), None);
        let got = sampler.average(after(base, 10), 20.0);
        assert_eq!(got, Some(Average { percent: 200.0, seconds: 10.0 }));
    }

    // The next average is from the last reading, not from the first.
    #[test]
    fn each_average_is_since_the_one_before() {
        let base = Instant::now();
        let mut sampler = Sampler::default();
        assert_eq!(sampler.average(base, 0.0), None);
        assert!(sampler.average(after(base, 100), 50.0).is_some());
        let got = sampler.average(after(base, 200), 51.0);
        assert_eq!(got, Some(Average { percent: 1.0, seconds: 100.0 }));
    }

    // No time passing, or CPU time going backwards, is not an average.
    #[test]
    fn a_reading_that_cannot_be_averaged_says_none() {
        let base = Instant::now();
        let mut sampler = Sampler::default();
        assert_eq!(sampler.average(base, 5.0), None);
        assert_eq!(sampler.average(base, 6.0), None);
        assert_eq!(sampler.average(after(base, 10), 2.0), None);
    }
}
