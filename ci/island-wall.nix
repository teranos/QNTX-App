# The island's wall. .github/workflows/island-wall.yml is emitted from this and
# is never edited by hand:
#
#   nix eval --json --file ci/island-wall.nix | jq . > .github/workflows/island-wall.yml
#
# "we can also keep it at full compliance for this critical piece of infrastructure"
#
# Every way the island's Swift could let a failure go is refused, read from
# its syntax (ci/island-wall). A pull request that brings one in is not merged.
{
  name = "Island wall";

  on = {
    pull_request.paths = [ "island/**" "ci/island-wall/**" "ci/island-wall.nix" ".github/workflows/island-wall.yml" ];
    push = {
      branches = [ "main" ];
      paths = [ "island/**" "ci/island-wall/**" ];
    };
    workflow_dispatch = null;
  };

  jobs.wall = {
    name = "The island lets no failure go";
    runs-on = "macos-15";
    timeout-minutes = 30;
    steps = [
      { uses = "actions/checkout@v5"; }
      {
        name = "Build the wall";
        working-directory = "ci/island-wall";
        run = "swift build -c release";
      }
      {
        # A wall that refuses nothing proves nothing: it is run first on a file
        # holding every way it refuses, and must refuse each of them.
        name = "The wall refuses every way it is to refuse";
        working-directory = "ci/island-wall";
        run = ''
          set +e
          .build/release/island-wall refused > refused.txt
          status=$?
          set -e
          cat refused.txt
          test "$status" -eq 1
          tail -1 refused.txt | grep -q -F "1 files read, 11 refused"
        '';
      }
      {
        name = "Read the island's Swift";
        working-directory = "ci/island-wall";
        run = ".build/release/island-wall ../../island";
      }
    ];
  };
}
