# 「[Fable 5.2, Opus 5.5] The island-apple workflow. .github/workflows/island-apple.yml is emitted from」
# 「[Fable 5.2, Opus 5.5] this and is never edited by hand:」
#
#   「[Fable 5.2, Opus 5.5] nix eval --json --file ci/island-apple.nix | jq . > .github/workflows/island-apple.yml」
#
# 「[Fable 5.2, Opus 5.5] JSON is YAML, so GitHub reads the emitted file as it is.」
let
  island = import ./island.nix;
in
{
  name = "island-apple";

  # 「[Fable 5.2, Opus 5.5] The island is its own bundle, and Apple signs nothing without an App ID」
  # 「[Fable 5.2, Opus 5.5] and a provisioning profile for it. This asks Apple for both with the key」
  # 「[Fable 5.2, Opus 5.5] CI holds, makes what is missing, and keeps the profile as the run's」
  # 「[Fable 5.2, Opus 5.5] artifact, for whoever sets it as IOS_ISLAND_MOBILE_PROVISION.」
  # 「[Fable 5.2, Opus 5.5] Asked for, never on a push: what it makes at Apple is what builds sign with.」
  on.workflow_dispatch = null;

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
          ISLAND_PROVISIONING_PROFILE = island.profile;
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
