# The testflight workflow. .github/workflows/testflight.yml is emitted from this
# and is never edited by hand:
#
#   nix eval --json --file ci/testflight.nix | jq . > .github/workflows/testflight.yml
#
# JSON is YAML, so GitHub reads the emitted file as it is.
let
  # The API origin baked into the bundle when a push builds, and the default a
  # dispatch offers.
  backendUrl = "https://api.q.sbvh.nl";
  backend = "\${{ inputs.backend_url || '${backendUrl}' }}";
  apple = builtins.fromJSON (builtins.readFile ../apple.json);
  # "the magic island"
  #
  # A press on it asks the node the page is built against.
  island = {
    node = backend;
    # 「[Opus 5.5] Where the island sends every failure: Sentry's qntx-island project.」
    sentry = "\${{ vars.ISLAND_SENTRY_DSN }}";
  };
  tag = (builtins.fromTOML (builtins.readFile ../Cargo.toml)).dependencies.sheet.tag;
in
{
  name = "testflight";

  run-name = "testflight \${{ github.ref_name }} \${{ inputs.ground }}";

  # A push to the shell is a build, a dispatch is a build, and a build carries
  # QNTX main. Always main:
  # "When App builds, I expect it to build from latest main QNTX always."
  # QNTX knows nothing of this repo; this repo is what reaches over. Nothing
  # builds unasked: a clock did, once, and spent the day's uploads on its own.
  # "I need the fastest path onto the phone, when I want it."
  on = {
    # QNTX's checks are no build of the shell.
    push.paths-ignore = [ "checks/**" "ci/checks.nix" ".github/workflows/checks.yml" ];
    workflow_dispatch.inputs = {
      backend_url = {
        description = "API origin baked into the bundle";
        type = "string";
        default = backendUrl;
      };
      ground = {
        description = "the performance and rite that dispatched this";
        type = "string";
        default = "";
      };
      # "and web version tag should trigger mobile build"
      #
      # The tag of QNTX-Web the page is built from.
      web_ref = {
        description = "the QNTX-Web ref the page is built from: a tag, or main";
        type = "string";
        default = "main";
      };
    };
  };

  jobs = {
    # Where main is, resolved once so the checkout and the build agree on it.
    main = {
      runs-on = "ubuntu-latest";
      outputs.sha = "\${{ steps.main.outputs.sha }}";
      steps = [
        {
          name = "Where main is";
          id = "main";
          run = ''
            sha=$(git ls-remote https://github.com/teranos/QNTX refs/heads/main | cut -f1)
            test -n "$sha"
            echo "sha=$sha" >> "$GITHUB_OUTPUT"
            echo "main is $sha"
          '';
        }
      ];
    };

    # "but, don't you want something like a template for both App and laye to follow?"
    #
    # The iOS job is teranos/ios-common's (ci/ios.nix), at the tag Cargo.toml
    # takes the sheet from. What is QNTX's own is passed to it here.
    build =
      import "${builtins.fetchGit {
        url = "https://github.com/teranos/ios-common";
        ref = "refs/tags/${tag}";
      }}/ci/ios.nix" {
        inherit tag island;
        inherit (apple) profile;
        # What was already compiled is reused: qntx-proto and qntx-grpc are path
        # dependencies, so their sources are part of the key.
        cache = {
          path = [ "target" ];
          key = [
            "Cargo.lock"
            "qntx/crates/**"
          ];
        };
        prepare = [
          # The shell carries no crates and no frontend. The crates come from QNTX
          # main, at the commit the job above saw. Full history: what main is gets
          # described against the tags below it.
          {
            uses = "actions/checkout@v5";
            "with" = {
              repository = "teranos/QNTX";
              ref = "\${{ needs.main.outputs.sha }}";
              path = "qntx";
              fetch-depth = 0;
              fetch-tags = true;
            };
          }
          # The page comes from QNTX-Web: its bun install fetches the browser
          # wasm from QNTX's release.
          {
            uses = "actions/checkout@v5";
            "with" = {
              repository = "teranos/QNTX-Web";
              ref = "\${{ inputs.web_ref || 'main' }}";
              path = "qntx-web";
            };
          }
          # Apple orders uploads by version, then by build within it. The version
          # is QNTX's newest release; the build is the run, which only rises. What
          # was actually built is the describe, and that is what an event names.
          {
            name = "What main is";
            id = "qntx";
            working-directory = "qntx";
            run = ''
              built=$(git describe --tags --match 'v*')
              version=$(git tag -l 'v*' | sort -V | tail -1)
              test -n "$built" && test -n "$version"
              echo "built=$built" >> "$GITHUB_OUTPUT"
              echo "version=''${version#v}" >> "$GITHUB_OUTPUT"
              echo "QNTX_TAG=$built" >> "$GITHUB_ENV"
              echo "building $built as $version"
            '';
          }
          {
            uses = "oven-sh/setup-bun@v2";
            "with".bun-version = "1.3.9";
          }
          # QNTX-Web's build reads BACKEND_URL and SENTRY_DSN and writes dist/. The
          # page leaves to the same project the shell does (src/lib.rs): a phone has
          # no console; a DSN only writes, so it sits here as a literal.
          {
            name = "Build the bundle the app carries";
            working-directory = "qntx-web";
            env = {
              BACKEND_URL = backend;
              SENTRY_DSN = "https://a67b1d3869b2fadc7a314746a35039f4@o4511990405464064.ingest.de.sentry.io/4512033476902992";
            };
            run = ''
              bun install --frozen-lockfile
              bun run build
            '';
          }
          {
            name = "The app is versioned as QNTX's newest release";
            run = ''
              python3 -c 'import json,sys; p="tauri.conf.json"; c=json.load(open(p)); c["version"]=sys.argv[1]; json.dump(c,open(p,"w"),indent=2); print("version", c["version"])' "''${{ steps.qntx.outputs.version }}"
            '';
          }
        ];
        project = [
          {
            name = "Add the screenshot share extension when provisioned";
            "if" = "vars.IOS_SHARE_EXTENSION == 'true'";
            env = {
              APPLE_DEVELOPMENT_TEAM = "\${{ secrets.APPLE_DEVELOPMENT_TEAM }}";
              SHARE_PROVISIONING_PROFILE = "\${{ vars.SHARE_PROVISIONING_PROFILE }}";
              PROVISIONING_PROFILE = apple.profile;
              ISLAND_PROVISIONING_PROFILE = apple.island.profile;
              IOS_SHARE_MOBILE_PROVISION = "\${{ secrets.IOS_SHARE_MOBILE_PROVISION }}";
            };
            run = ''
              python3 -m venv "$RUNNER_TEMP/share-tools"
              "$RUNNER_TEMP/share-tools/bin/pip" install PyYAML==6.0.3
              python3 .github/scripts/install-share-profile.py
              "$RUNNER_TEMP/share-tools/bin/python" .github/scripts/ios-share-project.py gen/apple/project.yml --version "''${{ steps.qntx.outputs.version }}" --build "''${{ steps.qntx.outputs.version }}.''${{ github.run_number }}"
            '';
          }
        ];
        # The Tauri CLI exports with the app's profile alone, and the archive
        # carries the island: it is exported naming both.
        build = ''
          if [ "$IOS_SHARE_EXTENSION" = "true" ]; then
            cargo tauri ios build --archive-only --build-number ''${{ github.run_number }}
            python3 .github/scripts/export-share-ipa.py
          else
            cargo tauri ios build --archive-only --build-number ''${{ github.run_number }}
            python3 "$IOS_COMMON/export-island.py"
          fi
        '';
        env.IOS_SHARE_EXTENSION = "\${{ vars.IOS_SHARE_EXTENSION }}";
      }
      // {
        needs = "main";
      };
  };
}
