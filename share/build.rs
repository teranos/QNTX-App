fn main() {
    tauri_plugin::Builder::new(&["pending", "read_image", "acknowledge"])
        .ios_path("ios")
        .build();
}
