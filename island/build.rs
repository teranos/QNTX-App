const COMMANDS: &[&str] = &["start", "update", "end"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS).ios_path("ios").build();
}
