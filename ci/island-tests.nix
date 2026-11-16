# The island's tests, in the iPhone Simulator. .github/workflows/island-tests.yml
# is emitted from this and is never edited by hand:
#
#   nix eval --json --file ci/island-tests.nix | jq . > .github/workflows/island-tests.yml
#
# "cant we make it easier on me, in terms of being able to test most testable mechanical things, before its like, live on my phone ??"
#
# The island's own Swift (island/shared, island/app), compiled for the
# Simulator with what the build pins, and what it decides tested before any
# build reaches a phone (ci/island-tests). Nothing here reaches TestFlight.
{
  name = "Island tests";

  on = {
    pull_request.paths = [ "island/**" "ci/island-tests/**" "ci/island-tests.nix" ".github/workflows/island-tests.yml" ];
    push = {
      branches = [ "main" ];
      paths = [ "island/**" "ci/island-tests/**" ];
    };
    workflow_dispatch = null;
  };

  jobs.tests = {
    name = "The island, tested in the iPhone Simulator";
    runs-on = "macos-15";
    timeout-minutes = 45;
    steps = [
      { uses = "actions/checkout@v5"; }
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
    ];
  };
}
