# The island drawn in the iPhone Simulator. .github/workflows/island-draw.yml
# is emitted from this and is never edited by hand:
#
#   nix eval --json --file ci/island-draw.nix | jq . > .github/workflows/island-draw.yml
#
# A host that says it has Live Activities embeds the island's own widget and
# starts the island's own Live Activity, shaped as the node shapes a
# collection (ci/island-draw). It stands active, and what the island draws of
# it is kept as a screenshot. Nothing here reaches TestFlight.
{
  name = "Island drawn";

  on = {
    pull_request.paths = [ "island/**" "ci/island-draw/**" "ci/island-draw.nix" ".github/workflows/island-draw.yml" ];
    push = {
      branches = [ "main" ];
      paths = [ "island/**" "ci/island-draw/**" ];
    };
    workflow_dispatch = null;
  };

  jobs.draw = {
    name = "The island draws what waits, in the iPhone Simulator";
    runs-on = "macos-15";
    timeout-minutes = 45;
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
        name = "Draw it";
        working-directory = "ci/island-draw";
        run = "bash run.sh";
      }
      {
        "if" = "always()";
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "island-drawn";
          path = "ci/island-draw/seen";
        };
      }
    ];
  };
}
