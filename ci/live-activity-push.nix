# 「[Opus 5.5] Whether the iPhone Simulator starts a Live Activity from a push.」
# 「[Opus 5.5] .github/workflows/live-activity-push.yml is emitted from this and is never」
# 「[Opus 5.5] edited by hand:」
#
#   「[Opus 5.5] nix eval --json --file ci/live-activity-push.nix | jq . > .github/workflows/live-activity-push.yml」
#
# 「[Opus 5.5] Its answer decides how the island's tests in the Simulator start what they」
# 「[Opus 5.5] test: by the push the node sends, or by the app. Nothing here reaches」
# 「[Opus 5.5] TestFlight.」
{
  name = "Live Activity push in the Simulator";

  on = {
    pull_request.paths = [ "ci/live-activity-push/**" "ci/live-activity-push.nix" ".github/workflows/live-activity-push.yml" ];
    workflow_dispatch = null;
  };

  jobs.probe = {
    name = "A push starts a Live Activity in the iPhone Simulator";
    runs-on = "macos-15";
    timeout-minutes = 30;
    steps = [
      { uses = "actions/checkout@v5"; }
      { run = "brew install xcodegen"; }
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
        name = "Push, and see";
        working-directory = "ci/live-activity-push";
        run = "bash run.sh";
      }
      {
        "if" = "always()";
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "live-activity-push";
          path = "ci/live-activity-push/seen";
        };
      }
    ];
  };
}
