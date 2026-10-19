//! The phone's power state, sent to Sentry as gauges.
//!
//! "Data in sentry about power consumption. Not a specific thing, but all things"
//!
//! Only compiled when building for iOS (`#[cfg(target_os = "ios")]`).

use std::time::Duration;

use sentry::{metrics, protocol::Unit};
use tauri::{AppHandle, Runtime};

/// How long between two readings.
const EVERY: Duration = Duration::from_secs(300);

fn report(reading: &power::Reading) {
    if let Some(level) = reading.battery_level() {
        metrics::gauge("power.battery.level", level)
            .unit(Unit::Ratio)
            .attribute("power.battery.state", reading.battery_state.name().to_string())
            .capture();
    }
    metrics::gauge("power.low_power_mode", if reading.low_power_mode { 1.0 } else { 0.0 }).capture();
    metrics::gauge("power.thermal.state", f64::from(reading.thermal_state.ordinal()))
        .attribute("power.thermal.name", reading.thermal_state.name().to_string())
        .capture();
}

/// Reads at once and then every `EVERY`, for as long as the app runs.
pub fn watch<R: Runtime>(app: AppHandle<R>) {
    std::thread::spawn(move || loop {
        match power::read(&app) {
            Ok(reading) => report(&reading),
            Err(err) => {
                eprintln!("the phone did not say its power state: {err}");
                sentry::capture_error(&err);
            }
        }
        std::thread::sleep(EVERY);
    });
}
