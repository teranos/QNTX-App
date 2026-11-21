//! The phone's power state, sent to Sentry as gauges.
//!
//! "Data in sentry about power consumption. Not a specific thing, but all things"
//!
//! Only compiled when building for iOS (`#[cfg(target_os = "ios")]`).

use std::time::{Duration, Instant};

use sentry::{metrics, protocol::Unit};
use tauri::{AppHandle, Runtime};

/// How long between two readings.
const EVERY: Duration = Duration::from_secs(300);

fn report(reading: &power::Reading, sampler: &mut power::Sampler, at: Instant) {
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

    // This process, the app's. The page is in the web view's own process.
    if let Some(bytes) = reading.memory_footprint {
        metrics::gauge("power.process.memory", bytes as f64)
            .unit(Unit::Byte)
            .capture();
    }
    if let Some(seconds) = reading.cpu_seconds {
        metrics::gauge("power.process.cpu_time", seconds).unit(Unit::Second).capture();
        if let Some(average) = sampler.average(at, seconds) {
            metrics::gauge("power.process.cpu_average", average.percent)
                .unit(Unit::Percent)
                .attribute("power.interval_seconds", average.seconds)
                .capture();
        }
    }
}

/// Reads at once and then every `EVERY`, for as long as the app runs.
pub fn watch<R: Runtime>(app: AppHandle<R>) {
    std::thread::spawn(move || {
        let mut sampler = power::Sampler::default();
        loop {
            match power::read(&app) {
                Ok(reading) => report(&reading, &mut sampler, Instant::now()),
                Err(err) => {
                    eprintln!("the phone did not say its power state: {err}");
                    sentry::capture_error(&err);
                }
            }
            std::thread::sleep(EVERY);
        }
    });
}
