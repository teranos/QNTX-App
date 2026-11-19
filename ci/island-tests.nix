# The island's tests, in the iPhone Simulator. .github/workflows/island-tests.yml
# is emitted from this and is never edited by hand:
#
#   nix eval --json --file ci/island-tests.nix | jq . > .github/workflows/island-tests.yml
#
# "cant we make it easier on me, in terms of being able to test most testable mechanical things, before its like, live on my phone ??"
#
# The island's own Swift (teranos/ios-common's island/shared and island/app,
# at the tag Cargo.toml takes the sheet from), compiled for the Simulator with
# what the build pins, and what it asks of a QNTX node tested before any build
# reaches a phone (ci/island-tests). Nothing here reaches TestFlight.
let
  tag = (builtins.fromTOML (builtins.readFile ../Cargo.toml)).dependencies.sheet.tag;
in
{
  name = "Island tests";

  on = {
    pull_request.paths = [ "Cargo.toml" "ci/island-tests/**" "ci/island-tests.nix" ".github/workflows/island-tests.yml" ".github/scripts/ci-node.py" ];
    push = {
      branches = [ "main" ];
      paths = [ "Cargo.toml" "ci/island-tests/**" ];
    };
    workflow_dispatch = null;
  };

  jobs.tests = {
    name = "The island, tested in the iPhone Simulator";
    runs-on = "macos-15";
    timeout-minutes = 90;
    steps = [
      { uses = "actions/checkout@v5"; }
      # The island, where it is kept.
      {
        uses = "actions/checkout@v5";
        "with" = {
          repository = "teranos/ios-common";
          ref = tag;
          path = "ios-common";
        };
      }
      # A QNTX node beside the Simulator, built from QNTX main, to test the
      # island against what it asks for real (.github/scripts/ci-node.py).
      {
        uses = "actions/checkout@v5";
        "with" = {
          repository = "teranos/QNTX";
          path = "qntx";
        };
      }
      {
        uses = "dtolnay/rust-toolchain@stable";
        "with".targets = "wasm32-unknown-unknown";
      }
      {
        uses = "actions/setup-go@v5";
        "with".go-version-file = "qntx/go.mod";
      }
      {
        name = "Build a node";
        working-directory = "qntx";
        run = ''
          cargo build --release --target wasm32-unknown-unknown --package ats-wasm
          cp target/wasm32-unknown-unknown/release/ats_wasm.wasm ats/wasm/ats.wasm
          cargo build --release --package ats-sqlite --features ffi --lib
          rm -f target/release/libats_sqlite.dylib target/release/deps/libats_sqlite.dylib
          mkdir -p bin
          go build -tags rustsqlite,qntxwasm -o bin/qntx ./cmd/qntx
        '';
      }
      {
        name = "Start it, with a person logged in";
        run = ''
          mkdir -p "$RUNNER_TEMP/node"
          python3 .github/scripts/ci-node.py "$PWD/qntx" "$RUNNER_TEMP/node" 18770 > node.env
          grep -e '^NODE=' -e '^PID=' node.env
          cat node.env >> "$GITHUB_ENV"
        '';
      }
      {
        # What the island hands over first, as the island hands it: the token
        # its phone starts Live Activities by, in the person's own session.
        name = "The node takes a phone's token from the person";
        run = ''
          answer=$(curl -s -w ' %{http_code}' -X POST "$NODE/api/phones" -H "Authorization: Bearer $SESSION" -H 'Content-Type: application/json' -d '{"token":"aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11","platform":"ios"}')
          echo "$answer"
          test "''${answer##* }" = 200
        '';
      }
      {
        name = "Boot an iPhone";
        run = ''
          RUNTIME=$(xcrun simctl list runtimes available -j | jq -r '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version) | last | .identifier')
          UDID=$(xcrun simctl list devices available -j | jq -r --arg rt "$RUNTIME" '[.devices[$rt][] | select(.name | startswith("iPhone"))] | first | .udid')
          echo "UDID=$UDID" >> "$GITHUB_ENV"
          echo "runtime: $RUNTIME"
          xcrun simctl boot "$UDID"
          xcrun simctl bootstatus "$UDID" -b
        '';
      }
      {
        name = "Test the island";
        working-directory = "ci/island-tests";
        run = ''
          xcodebuild -list
          # The node on this runner, and the person logged in there, for the island to ask.
          TEST_RUNNER_QNTX_TEST_NODE="$NODE" TEST_RUNNER_QNTX_TEST_SESSION="$SESSION" TEST_RUNNER_QNTX_TEST_WAITS_FOR="$WAITS_FOR" TEST_RUNNER_CI=true \
            xcodebuild test -scheme IslandTests-Package -destination "id=$UDID" -resultBundlePath island-tests.xcresult
        '';
      }
      {
        "if" = "always()";
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "island-tests";
          path = "ci/island-tests/island-tests.xcresult";
        };
      }
      {
        "if" = "always()";
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "node-log";
          path = "\${{ runner.temp }}/node/node.log";
        };
      }
    ];
  };
}
