# The island-apple workflow. .github/workflows/island-apple.yml is emitted from
# this and is never edited by hand:
#
#   nix eval --json --file ci/island-apple.nix | jq . > .github/workflows/island-apple.yml
#
# JSON is YAML, so GitHub reads the emitted file as it is.
{
  name = "island-apple";

  # The island is its own bundle, and Apple signs nothing without an App ID
  # and a provisioning profile for it. This asks Apple for both with the key
  # CI holds, makes what is missing, and keeps the profile as the run's
  # artifact, for whoever sets it as IOS_ISLAND_MOBILE_PROVISION.
  on = {
    push.paths = [ ".github/scripts/island-apple.py" ".github/workflows/island-apple.yml" ];
    workflow_dispatch = null;
  };

  jobs.ask = {
    runs-on = "ubuntu-latest";
    steps = [
      { uses = "actions/checkout@v5"; }

      { run = "pip install --quiet 'pyjwt[crypto]' requests"; }

      {
        name = "The island's App ID and profile at Apple";
        env = {
          APPLE_API_KEY = "\${{ secrets.APPLE_API_KEY }}";
          APPLE_API_ISSUER = "\${{ secrets.APPLE_API_ISSUER }}";
          APPLE_API_KEY_CONTENT = "\${{ secrets.APPLE_API_KEY_CONTENT }}";
          PROVISIONING_PROFILE = "\${{ vars.PROVISIONING_PROFILE }}";
        };
        run = "python3 .github/scripts/island-apple.py island.mobileprovision";
      }

      {
        uses = "actions/upload-artifact@v4";
        "with" = {
          name = "island-profile";
          path = "island.mobileprovision";
          retention-days = 1;
        };
      }
    ];
  };
}
