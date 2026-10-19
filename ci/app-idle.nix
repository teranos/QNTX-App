# The app on an iPhone, left alone. .github/workflows/app-idle.yml is emitted
# from this and is never edited by hand:
#
#   nix eval --json --file ci/app-idle.nix | jq . > .github/workflows/app-idle.yml
#
# "WebKit's own guidance suggests aiming for less than 3% average CPU usage
# during an idle session, with a recording of at least 15 seconds to avoid
# overreacting to brief spikes. Sustained high CPU activity is a warning sign
# for battery drain."
#
# The app shows QNTX in Apple's web view, not Safari, so this builds this shell
# for the Simulator, with QNTX's main beside it as the shell expects, and leaves
# it alone once it is up. Which screen that is, is read from the screenshot it
# keeps. In the Simulator the app and the web view's processes are
# processes of the runner, which ci/app-idle/sample.py reads. Nothing here
# reaches TestFlight.
{
  name = "App idle";

  on = {
    pull_request.paths = [ "ci/app-idle/**" "ci/app-idle.nix" ".github/workflows/app-idle.yml" "sheet/**" "power/**" "src/**" "tauri.conf.json" "tauri.ios.conf.json" "Info.ios.plist" ];
    workflow_dispatch = null;
  };

  # A push to the pull request ends the run of the one before: one macOS runner per pull request.
  concurrency = {
    group = "app-idle-\${{ github.ref }}";
    cancel-in-progress = true;
  };

  jobs.ios = {
    name = "QNTX-App idle in the iPhone Simulator";
    runs-on = "macos-15";
    timeout-minutes = 90;
    steps = [
      {
        # The runner is 0% idle for minutes after the build, and what is busiest
        # is Spotlight (mds, mdworker_shared, mds_stores) indexing the tree the
        # build just wrote. Off before anything is written, so the CPU that is
        # read is not shared with it.
        name = "Spotlight stays out of the way";
        run = "sudo mdutil -a -i off";
      }
      { uses = "actions/checkout@v5"; }
      {
        uses = "actions/checkout@v5";
        "with" = {
          repository = "teranos/QNTX";
          path = "qntx";
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
        name = "Fetch tauri-cli 2.11.4";
        run = ''
          curl -sSL -o cargo-tauri.zip https://github.com/tauri-apps/tauri/releases/download/tauri-cli-v2.11.4/cargo-tauri-aarch64-apple-darwin.zip
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
          RUNTIME=$(xcrun simctl list runtimes available -j | jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version) | last | .identifier')
          UDID=$(xcrun simctl list devices available -j | jq -r --arg rt "$RUNTIME" '[.devices[$rt][] | select(.name | startswith("iPhone"))] | first | .udid')
          echo "UDID=$UDID" >> "$GITHUB_ENV"
          xcrun simctl boot "$UDID"
          xcrun simctl bootstatus "$UDID" -b
        '';
      }
      {
        # What the sampler sends to Sentry with: the SDK for Python, as pinned.
        name = "Sentry's SDK for the sampler";
        run = "python3 -m pip install --quiet sentry-sdk==2.72.0";
      }
      {
        name = "QNTX's page as the TestFlight build makes it";
        # The page is told where its node is, as the TestFlight build tells it.
        # Without it the page asks the app's own scheme, is answered with the
        # app's index.html, and stops on "Unrecognized token '<'" before the door.
        # No SENTRY_DSN here: a page that reports is the app's, and a Simulator's
        # reports would be mixed with a phone's.
        env.BACKEND_URL = "https://api.q.sbvh.nl";
        run = "(cd qntx && make web)";
      }
      {
        name = "The app, left alone";
        # A run that hangs ends here, its log kept.
        timeout-minutes = 60;
        # What the sampler reads is sent to the project the shell leaves to
        # (src/lib.rs), as environment ci with ci.* names. A DSN only writes,
        # so it sits here as a literal.
        env.SENTRY_DSN = "https://a67b1d3869b2fadc7a314746a35039f4@o4511990405464064.ingest.de.sentry.io/4512033476902992";
        run = "bash ci/app-idle/run.sh launch";
      }
      {
        "if" = "always()";
        name = "What was read";
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "app-idle";
          path = "idle-samples";
          retention-days = 14;
          if-no-files-found = "warn";
        };
      }
    ];
  };
}
