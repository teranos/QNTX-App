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

    build = {
      needs = "main";
      runs-on = "macos-latest";
      steps = [
        { uses = "actions/checkout@v5"; }

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

        # The page comes from QNTX-Web main:
        # "web needs to leave the repo"
        # Its bun install fetches the browser wasm from QNTX's release.
        {
          uses = "actions/checkout@v5";
          "with" = {
            repository = "teranos/QNTX-Web";
            ref = "main";
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
          uses = "dtolnay/rust-toolchain@stable";
          id = "rust";
          "with" = {
            targets = "aarch64-apple-ios";
            components = "clippy";
          };
        }

        {
          uses = "oven-sh/setup-bun@v2";
          "with".bun-version = "1.3.9";
        }

        # What was already compiled is reused: clippy and the IPA both compile
        # tauri, sentry and the two QNTX path crates into target/. qntx-proto and
        # qntx-grpc are path dependencies, so their sources are part of the key.
        {
          name = "The shell compiled last time";
          uses = "actions/cache@v4";
          "with" = {
            path = "target";
            key = "shell-\${{ steps.rust.outputs.cachekey }}-\${{ hashFiles('Cargo.lock', 'qntx/crates/**') }}";
            restore-keys = ''
              shell-''${{ steps.rust.outputs.cachekey }}-
            '';
          };
        }

        # QNTX-Web's build reads BACKEND_URL and SENTRY_DSN and writes dist/. The
        # page leaves to the same project the shell does (src/lib.rs): a phone has
        # no console; a DSN only writes, so it sits here as a literal.
        {
          name = "Build the bundle the app carries";
          working-directory = "qntx-web";
          env = {
            BACKEND_URL = "\${{ inputs.backend_url || '${backendUrl}' }}";
            SENTRY_DSN = "https://a67b1d3869b2fadc7a314746a35039f4@o4511990405464064.ingest.de.sentry.io/4512033476902992";
          };
          run = ''
            bun install --frozen-lockfile
            bun run build
          '';
        }

        # The wall in Cargo.toml is a list of denials, and this is what asks it.
        # After the bundle: generate_context! refuses a frontendDist that is not there.
        {
          name = "The lib answers for every error";
          run = "cargo clippy --lib --target aarch64-apple-ios";
        }

        # The release binary, not a six-minute compile of the CLI on every run.
        {
          name = "Fetch tauri-cli 2.11.4";
          run = ''
            curl -sSL -o cargo-tauri.zip https://github.com/tauri-apps/tauri/releases/download/tauri-cli-v2.11.4/cargo-tauri-aarch64-apple-darwin.zip
            unzip -o -q cargo-tauri.zip -d "$HOME/.cargo/bin"
            rm cargo-tauri.zip
            cargo tauri --version
          '';
        }

        {
          name = "The app is versioned as QNTX's newest release";
          run = ''
            python3 -c 'import json,sys; p="tauri.conf.json"; c=json.load(open(p)); c["version"]=sys.argv[1]; json.dump(c,open(p,"w"),indent=2); print("version", c["version"])' "''${{ steps.qntx.outputs.version }}"
          '';
        }

        { run = "cargo tauri ios init"; }

        {
          name = "Sign against the profile, not an account";
          env = {
            APPLE_DEVELOPMENT_TEAM = "\${{ secrets.APPLE_DEVELOPMENT_TEAM }}";
            PROVISIONING_PROFILE = "\${{ vars.PROVISIONING_PROFILE }}";
            # Unset, the island's widget is not in the project and the build is
            # as it was: the export below names the app's profile alone.
            ISLAND_PROVISIONING_PROFILE = "\${{ vars.ISLAND_PROVISIONING_PROFILE }}";
          };
          run = ''
            python3 .github/scripts/ios-project.py gen/apple/project.yml
            cd gen/apple && xcodegen generate
          '';
        }

        {
          name = "Build signed IPA";
          env = {
            IOS_CERTIFICATE = "\${{ secrets.IOS_CERTIFICATE }}";
            IOS_CERTIFICATE_PASSWORD = "\${{ secrets.IOS_CERTIFICATE_PASSWORD }}";
            IOS_MOBILE_PROVISION = "\${{ secrets.IOS_MOBILE_PROVISION }}";
            APPLE_DEVELOPMENT_TEAM = "\${{ secrets.APPLE_DEVELOPMENT_TEAM }}";
          };
          run = ''
            cargo tauri ios build \
              --export-method app-store-connect \
              --build-number ''${{ github.run_number }}
          '';
        }

        {
          name = "Locate IPA";
          id = "ipa";
          run = ''
            FOUND=$(find . -name '*.ipa' -type f | head -1)
            if [ -z "$FOUND" ]; then
              find gen/apple/build -type f 2>/dev/null
              echo "no ipa produced"
              exit 1
            fi
            echo "path=$FOUND" >> "$GITHUB_OUTPUT"
            echo "Found $FOUND"
          '';
        }

        {
          name = "Upload to TestFlight";
          env = {
            APPLE_API_KEY = "\${{ secrets.APPLE_API_KEY }}";
            APPLE_API_ISSUER = "\${{ secrets.APPLE_API_ISSUER }}";
            APPLE_API_KEY_CONTENT = "\${{ secrets.APPLE_API_KEY_CONTENT }}";
          };
          run = ''
            mkdir -p ~/.appstoreconnect/private_keys
            echo "$APPLE_API_KEY_CONTENT" | base64 --decode \
              > ~/.appstoreconnect/private_keys/AuthKey_$APPLE_API_KEY.p8
            xcrun altool --upload-app \
              -f "''${{ steps.ipa.outputs.path }}" \
              --api-key "$APPLE_API_KEY" \
              --api-issuer "$APPLE_API_ISSUER"
          '';
        }

        # altool exits 0 when Apple has the bytes, and nothing after that reached
        # any log: ten green runs sat in App Store Connect as
        # MISSING_EXPORT_COMPLIANCE while the phone stayed on build 8. Green
        # means a tester can install it, or the run is red and says why.
        {
          name = "Delivered to testers";
          env = {
            APPLE_API_KEY = "\${{ secrets.APPLE_API_KEY }}";
            APPLE_API_ISSUER = "\${{ secrets.APPLE_API_ISSUER }}";
            APPLE_API_KEY_CONTENT = "\${{ secrets.APPLE_API_KEY_CONTENT }}";
            BUILD = "\${{ steps.qntx.outputs.version }}.\${{ github.run_number }}";
          };
          run = ''
            python3 -m venv "$RUNNER_TEMP/asc"
            "$RUNNER_TEMP/asc/bin/pip" install --quiet 'pyjwt[crypto]' requests
            "$RUNNER_TEMP/asc/bin/python" .github/scripts/delivered.py wait "$BUILD"
          '';
        }
      ];
    };
  };
}
