# The delivered workflow. .github/workflows/delivered.yml is emitted from this
# and is never edited by hand:
#
#   nix eval --json --file ci/delivered.nix | jq . > .github/workflows/delivered.yml
#
# JSON is YAML, so GitHub reads the emitted file as it is.
let
  # The bundle identifier is tauri.conf.json's, read rather than restated.
  inherit (builtins.fromJSON (builtins.readFile ../tauri.conf.json)) identifier;
in
{
  name = "delivered";

  # What App Store Connect did with what was uploaded. The upload step exits 0
  # and the build then leaves every log this repo can read; a phone that stays
  # on an old build is a fault on this side, and this is the side asking.
  # "I keep saying the issue isn't phone side."
  on = {
    push = null;
    workflow_dispatch = null;
  };

  jobs.ask = {
    runs-on = "ubuntu-latest";
    steps = [
      { uses = "actions/checkout@v5"; }

      { run = "pip install --quiet 'pyjwt[crypto]' requests"; }

      {
        name = "What App Store Connect holds for ${identifier}";
        env = {
          APPLE_API_KEY = "\${{ secrets.APPLE_API_KEY }}";
          APPLE_API_ISSUER = "\${{ secrets.APPLE_API_ISSUER }}";
          APPLE_API_KEY_CONTENT = "\${{ secrets.APPLE_API_KEY_CONTENT }}";
        };
        run = "python3 .github/scripts/delivered.py list";
      }
    ];
  };
}
