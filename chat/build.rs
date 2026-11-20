use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

const COMMANDS: &[&str] = &["open", "show", "close"];

/// Where tauri.ios.conf.json's `bundle.iOS.frameworks` finds Giphy's framework, for Xcode to link and embed.
const EMBEDDED: &str = "ios/Frameworks/GiphyUISDK.xcframework";

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
// here, and the app embeds it (Xcode, through bundle.iOS.frameworks).
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

    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").map_err(io::Error::other)?);
    let embedded = manifest.join(EMBEDDED);
    if embedded.exists() {
        fs::remove_dir_all(&embedded)?;
    }
    copy(&xcframework, &embedded)
}

fn copy(from: &Path, to: &Path) -> io::Result<()> {
    fs::create_dir_all(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        let kind = entry.file_type()?;
        if kind.is_dir() {
            copy(&entry.path(), &target)?;
        } else if kind.is_symlink() {
            let link = fs::read_link(entry.path())?;
            #[cfg(unix)]
            std::os::unix::fs::symlink(link, &target)?;
            #[cfg(not(unix))]
            drop(link);
        } else {
            fs::copy(entry.path(), &target)?;
        }
    }
    Ok(())
}
