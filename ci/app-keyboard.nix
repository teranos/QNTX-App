# The app on an iPhone, and a tap on a box. .github/workflows/app-keyboard.yml
# is emitted from this and is never edited by hand:
#
#   nix eval --json --file ci/app-keyboard.nix | jq . > .github/workflows/app-keyboard.yml
#
# "you tap a box to type, and the only thing that happens is the keyboard
# coming up. No zoom, nothing moves, nothing refocuses. The same as Claude or
# ChatGPT on your phone."
#
# The app shows QNTX in Apple's web view, not Safari, so this builds this
# shell for the Simulator, with QNTX's main beside it for the crates and
# QNTX-Web's main for the page, as the shell expects. Nothing here reaches TestFlight.
{
  name = "App keyboard";

  on = {
    pull_request.paths = [ "ci/boot-iphone.sh" "ci/sim-ready.sh" "ci/app-keyboard/**" "ci/app-keyboard.nix" ".github/workflows/app-keyboard.yml" "power/**" "shake/**" "src/**" "tauri.conf.json" "tauri.ios.conf.json" "Info.ios.plist" ];
    workflow_dispatch = null;
  };

  jobs.ios = {
    name = "QNTX-App in the iPhone Simulator";
    runs-on = "xcode-27";
    # Three scenarios of up to 45 minutes each, and the setup and what is kept around them.
    timeout-minutes = 180;
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
      {
        uses = "actions/checkout@v5";
        "with" = {
          repository = "teranos/QNTX-Web";
          path = "qntx-web";
        };
      }
      {
        uses = "dtolnay/rust-toolchain@stable";
        "with".targets = "aarch64-apple-ios-sim";
      }
      {
        uses = "oven-sh/setup-bun@v2";
        "with".bun-version = "1.3.9";
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
      {
        name = "A finger, and eyes";
        run = ''
          curl -sSL https://github.com/facebook/idb/releases/download/v1.1.8/idb-companion.universal.tar.gz | tar -xz
          COMPANION=$(dirname "$(find "$PWD" -name idb_companion -type f -perm -u+x | head -1)")
          echo "$COMPANION" >> "$GITHUB_PATH"
          python -m pip install --quiet fb-idb pillow
        '';
      }
      { run = "cargo tauri ios init"; }
      {
        name = "Boot an iPhone, with its own keyboard";
        run = ''
          defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
          source ci/boot-iphone.sh
          # idb taps through SimulatorKit, which it looks for inside Xcode; Xcode 27.2
          # does not keep it there. Wherever it is, it is linked where idb looks.
          SK="$(xcode-select -p)/Library/PrivateFrameworks/SimulatorKit.framework"
          if [ ! -e "$SK" ]; then
            FOUND=$(find /Library/Developer /Applications /System/Library/PrivateFrameworks -maxdepth 7 -name SimulatorKit.framework -type d 2>/dev/null | grep -v "^$SK" | head -1 || true)
            echo "SimulatorKit: ''${FOUND:-not found}"
            test -n "$FOUND"
            sudo mkdir -p "$(dirname "$SK")"
            sudo ln -s "$FOUND" "$SK"
          fi
        '';
      }
      {
        name = "A bare page without the viewport line: the web view zooms, and this run sees it";
        # A case that hangs ends here, its log kept, and the next case still runs.
        timeout-minutes = 45;
        run = ''
          mkdir -p qntx-web/dist
          sed 's|<!-- VIEWPORT -->|<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">|' ci/app-keyboard/page.html > qntx-web/dist/index.html
          bash ci/app-keyboard/run.sh without
        '';
      }
      {
        "if" = "always()";
        name = "The same page, with html and body pinned to the window and not scrolling";
        # A case that hangs ends here, its log kept, and the next case still runs.
        timeout-minutes = 45;
        run = ''
          (cd qntx-web && bun install --frozen-lockfile)
          (cd qntx-web && bun run build)
          python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); a=s.index("<meta name=\"viewport\""); b=s.index(">", a)+1; s=s[:a]+sys.argv[2]+s[b:]; c=s.index("</head>"); open(p,"w").write(s[:c]+"<style>html, body { height: 100%; overflow: hidden; }</style>"+s[c:])' qntx-web/dist/index.html '<meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">'
          bash ci/app-keyboard/run.sh pinned
        '';
      }
      {
        "if" = "always()";
        name = "QNTX's page as QNTX-Web main builds it, holding where its window stood while a field has the keyboard";
        # Pinned, the window still went from 778 to 743 tall and the page scrolled
        # 35 to match, in a shell with or without the web view's inset adjustment.
        timeout-minutes = 45;
        run = ''
          (cd qntx-web && bun install --frozen-lockfile)
          (cd qntx-web && bun run build)
          python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); c=s.index("</head>"); open(p,"w").write(s[:c]+open(sys.argv[2]).read()+s[c:])' qntx-web/dist/index.html ci/app-keyboard/hold-page.html
          bash ci/app-keyboard/run.sh page
        '';
      }
      {
        "if" = "always()";
        name = "What the screen said";
        run = ''
          cat verdicts.txt
          grep -q '^without: zoomed$' verdicts.txt || echo "without the line the page did not zoom"
          grep -q '^pinned: stayed$' verdicts.txt || echo "pinned, QNTX's page did more than bring the keyboard"
          grep -q '^page: stayed$' verdicts.txt
        '';
      }
      {
        "if" = "always()";
        name = "The screens";
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "app-keyboard";
          path = "keyboard-shots";
          retention-days = 14;
        };
      }
    ];
  };
}
