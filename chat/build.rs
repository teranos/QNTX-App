use std::{env, io, path::PathBuf};

const COMMANDS: &[&str] = &["open", "show", "close"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios") {
        if let Err(err) = giphy() {
            println!("cargo:warning=Giphy's framework is not linked: {err}");
        }
    }
}

// Exyte Chat depends on Giphy's SDK, which is only a binary framework, and a dynamic one. The Swift
// package is built into a static library that does not carry it: the library is linked against it
// here, and the app embeds it (Xcode, through bundle.iOS.frameworks, fetched by ios/giphy.sh).
fn giphy() -> io::Result<()> {
    let out = PathBuf::from(env::var("OUT_DIR").map_err(io::Error::other)?);
    let xcframework = out
        .join("swift-rs")
        .join("chat")
        .join("checkouts")
        .join("giphy-ios-sdk")
        .join("GiphyUISDK.xcframework");
    let slice = match env::var("TARGET").as_deref() {
        Ok("aarch64-apple-ios") => "ios-arm64",
        _ => "ios-arm64_x86_64-simulator",
    };
    let framework_dir = xcframework.join(slice);
    if !framework_dir.join("GiphyUISDK.framework").exists() {
        return Err(io::Error::other(format!(
            "no {}",
            framework_dir.join("GiphyUISDK.framework").display()
        )));
    }
    println!(
        "cargo:rustc-link-search=framework={}",
        framework_dir.display()
    );
    println!("cargo:rustc-link-lib=framework=GiphyUISDK");

    Ok(())
}

