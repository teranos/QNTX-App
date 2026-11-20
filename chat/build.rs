const COMMANDS: &[&str] = &["open", "show", "close"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
}
