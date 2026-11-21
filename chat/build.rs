use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

const COMMANDS: &[&str] = &["open", "show", "close"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios") {
        if let Err(err) = giphy() {
            println!("cargo:warning=Giphy's framework is not linked: {err}");
            std::process::exit(1);
        }
        if let Err(err) = resources() {
            println!("cargo:warning=the Swift packages' resources are not carried: {err}");
            std::process::exit(1);
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


// Exyte Chat reads its colours and images from its resource bundle (Bundle.module), and stops the app
// when the bundle is not beside the app's executable. The static library does not carry it: the
// bundles the Swift packages built are copied to ios/Bundles, and ios/project.yml copies them into
// the app.
fn resources() -> io::Result<()> {
    let out = PathBuf::from(env::var("OUT_DIR").map_err(io::Error::other)?);
    let configuration = if env::var("DEBUG").as_deref() == Ok("true") { "Debug" } else { "Release" };
    let platform = match env::var("TARGET").as_deref() {
        Ok("aarch64-apple-ios") => "iphoneos",
        _ => "iphonesimulator",
    };
    let products = format!("{configuration}-{platform}");
    let mut found = Vec::new();
    bundles(&out.join("swift-rs").join("chat"), &products, 0, &mut found)?;
    if !found.iter().any(|b| b.ends_with("Chat_ExyteChat.bundle")) {
        return Err(io::Error::other(format!(
            "no Chat_ExyteChat.bundle under {} in {products}",
            out.display()
        )));
    }
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").map_err(io::Error::other)?);
    let carried = manifest.join("ios").join("Bundles");
    if carried.exists() {
        fs::remove_dir_all(&carried)?;
    }
    for bundle in found {
        if let Some(name) = bundle.file_name() {
            copy(&bundle, &carried.join(name))?;
        }
    }
    Ok(())
}

// Every *.bundle directly in a products directory of this configuration and platform.
fn bundles(dir: &Path, products: &str, depth: u32, found: &mut Vec<PathBuf>) -> io::Result<()> {
    if depth > 6 {
        return Ok(());
    }
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }
        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.ends_with(".bundle") {
            if dir.file_name().map(|n| n.to_string_lossy() == products) == Some(true) {
                found.push(path);
            }
            continue;
        }
        if name == "checkouts" || name == "repositories" {
            continue;
        }
        bundles(&path, products, depth.saturating_add(1), found)?;
    }
    Ok(())
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
