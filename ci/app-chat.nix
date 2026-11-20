# The native chat on an iPhone: the app built for the Simulator, the page opening
# the chat as QNTX-Web does (ci/app-chat/probe.html), and the app still running
# forty seconds later. .github/workflows/app-chat.yml is emitted from this and is
# never edited by hand:
#
#   nix eval --json --file ci/app-chat.nix | jq . > .github/workflows/app-chat.yml
#
# "Use native / Exyte". The TestFlight build that first carried it stopped on the
# phone; nothing of it reaches TestFlight again before this passes.
{
  name = "App chat";

  on = {
    pull_request.paths = [ "ci/boot-iphone.sh" "ci/sim-ready.sh" "ci/app-chat/**" "ci/app-chat.nix" ".github/workflows/app-chat.yml" "chat/**" "Cargo.toml" "Cargo.lock" "power/**" "shake/**" "src/**" "tauri.conf.json" "tauri.ios.conf.json" "Info.ios.plist" ];
    workflow_dispatch = null;
  };

  # A push to the pull request ends the run of the one before: one macOS runner per pull request.
  concurrency = {
    group = "app-chat-\${{ github.ref }}";
    cancel-in-progress = true;
  };

  jobs.ios = {
    name = "QNTX-App's native chat in the iPhone Simulator";
    runs-on = "xcode-27";
    timeout-minutes = 90;
    steps = [
      { uses = "actions/checkout@v5"; }
      {
        name = "Xcode 27.2, as the TestFlight build has: Exyte Chat's Swift packages resolve for iOS there, and not with macos-15's Xcode";
        run = "sudo xcode-select -s /Applications/Xcode_27.2.app\nxcodebuild -version\n";
      }
      {
        uses = "actions/checkout@v5";
        "with" = {
          repository = "teranos/QNTX";
          path = "qntx";
        };
      }
      # The page comes from QNTX-Web main, as the shell's frontendDist expects:
      # "web needs to leave the repo"
      {
        uses = "actions/checkout@v5";
        "with" = {
          repository = "teranos/QNTX-Web";
          path = "qntx-web";
        };
      }
      {
        uses = "dtolnay/rust-toolchain@stable";
        "with".targets = "aarch64-apple-ios-sim, wasm32-unknown-unknown";
      }
      {
        uses = "jetli/wasm-pack-action@v0.4.0";
        "with".version = "v0.13.1";
      }
      {
        uses = "oven-sh/setup-bun@v2";
        "with".bun-version = "1.3.3";
      }
      {
        name = "Fetch tauri-cli 2.12.6";
        run = ''
          curl -sSL -o cargo-tauri.zip https://github.com/tauri-apps/tauri/releases/download/tauri-cli-v2.12.6/cargo-tauri-aarch64-apple-darwin.zip
          mkdir -p "$HOME/.cargo/bin"
          unzip -o -q cargo-tauri.zip -d "$HOME/.cargo/bin"
          rm cargo-tauri.zip
          cargo tauri --version
        '';
      }
      {
        uses = "actions/setup-python@v5";
        "with".python-version = "3.11";
      }
      { run = "cargo tauri ios init"; }
      {
        name = "Boot an iPhone";
        run = ''
          bash ci/boot-iphone.sh
        '';
      }
      {
        name = "QNTX's page as the TestFlight build makes it";
        # The page is told where its node is, as the TestFlight build tells it.
        # Without it the page asks the app's own scheme, is answered with the
        # app's index.html, and stops on "Unrecognized token '<'" before the door.
        # No SENTRY_DSN here: a page that reports is the app's, and a Simulator's
        # reports would be mixed with a phone's.
        env.BACKEND_URL = "https://api.q.sbvh.nl";
        working-directory = "qntx-web";
        run = ''
          bun install --frozen-lockfile
          bun run build
        '';
      }
      {
        name = "The native chat, opened";
        timeout-minutes = 60;
        run = "bash ci/app-chat/run.sh";
      }
      {
        "if" = "failure()";
        name = "Why the app is gone, as the simulator's crash report says";
        run = ''
          for i in $(seq 1 18); do ls ~/Library/Logs/DiagnosticReports/QNTX*.ips >/dev/null 2>&1 && break; sleep 10; done
          python3 ci/app-idle/crash.py ~/Library/Logs/DiagnosticReports || true
          # The app once more, its console attached: a Swift fatal error says its message there.
          xcrun simctl terminate "$UDID" nl.sbvh.qntx || true
          perl -e 'alarm 40; exec @ARGV' xcrun simctl launch --console-pty "$UDID" nl.sbvh.qntx 2>&1 | grep -v '^$' | tail -60 || true
          xcrun simctl spawn "$UDID" log show --last 10m --style compact --predicate 'process == "QNTX" OR eventMessage CONTAINS "QNTX"' 2>/dev/null | grep -iE "dyld|crash|terminat|fatal|abort|Library not loaded" | head -40 || true
        '';
      }
      {
        "if" = "always()";
        name = "What the screen showed";
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "app-chat";
          path = "chat-shots";
          retention-days = 14;
          if-no-files-found = "warn";
        };
      }
    ];
  };
}
