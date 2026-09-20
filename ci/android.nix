# The android workflow, emitted from this and never edited by hand: nix eval --json --file ci/android.nix | jq . > .github/workflows/android.yml
# JSON is YAML, so GitHub reads the emitted file as it is.
let
  backendUrl = "https://api.q.sbvh.nl";
  ndkVersion = "27.0.12077973";
in
{
  name = "android";

  run-name = "android \${{ github.ref_name }} \${{ inputs.ground }}";

  # No store to update itself from here, so the build is the release: a tagged GitHub Release carrying the signed APK, which is what the app's own in-app updater will come to check against.
  on = {
    push = null;
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
      runs-on = "ubuntu-latest";
      permissions.contents = "write";
      steps = [
        { uses = "actions/checkout@v5"; }

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
            targets = "wasm32-unknown-unknown, aarch64-linux-android, armv7-linux-androideabi, i686-linux-android, x86_64-linux-android";
            components = "clippy";
          };
        }

        {
          uses = "jetli/wasm-pack-action@v0.4.0";
          "with".version = "v0.13.1";
        }

        {
          uses = "oven-sh/setup-bun@v2";
          "with".bun-version = "1.3.3";
        }

        {
          uses = "actions/setup-java@v4";
          "with" = {
            distribution = "temurin";
            java-version = "21";
          };
        }

        {
          uses = "android-actions/setup-android@v3";
        }

        {
          name = "Install the NDK cargo tauri android build needs";
          run = ''
            sdkmanager --install "ndk;${ndkVersion}"
            echo "ANDROID_NDK_HOME=$ANDROID_HOME/ndk/${ndkVersion}" >> "$GITHUB_ENV"
          '';
        }

        {
          name = "The wasm compiled last time";
          uses = "actions/cache@v4";
          "with" = {
            path = ''
              qntx/target
              ~/.cargo/registry/index
              ~/.cargo/registry/cache
              ~/.cargo/git/db
            '';
            key = "wasm-\${{ steps.rust.outputs.cachekey }}-\${{ hashFiles('qntx/Cargo.lock', 'qntx/crates/**') }}";
            restore-keys = ''
              wasm-''${{ steps.rust.outputs.cachekey }}-
            '';
          };
        }

        {
          name = "The shell compiled last time";
          uses = "actions/cache@v4";
          "with" = {
            path = "target";
            key = "shell-android-\${{ steps.rust.outputs.cachekey }}-\${{ hashFiles('Cargo.lock', 'qntx/crates/**') }}";
            restore-keys = ''
              shell-android-''${{ steps.rust.outputs.cachekey }}-
            '';
          };
        }

        {
          name = "Build the bundle the app carries";
          working-directory = "qntx";
          env = {
            BACKEND_URL = "\${{ inputs.backend_url || '${backendUrl}' }}";
            SENTRY_DSN = "https://a67b1d3869b2fadc7a314746a35039f4@o4511990405464064.ingest.de.sentry.io/4512033476902992";
          };
          run = "make web";
        }

        {
          name = "The lib answers for every error";
          run = "cargo clippy --lib --target aarch64-linux-android";
        }

        {
          name = "Fetch tauri-cli 2.11.4";
          run = ''
            curl -sSL -o cargo-tauri.zip https://github.com/tauri-apps/tauri/releases/download/tauri-cli-v2.11.4/cargo-tauri-x86_64-unknown-linux-gnu.zip
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

        {
          name = "The signing key, from the secret it lives in";
          env = {
            ANDROID_KEYSTORE_BASE64 = "\${{ secrets.ANDROID_KEYSTORE_BASE64 }}";
            ANDROID_KEYSTORE_PASSWORD = "\${{ secrets.ANDROID_KEYSTORE_PASSWORD }}";
          };
          run = ''
            mkdir -p "$HOME/.keystores/qntx-app"
            echo "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$HOME/.keystores/qntx-app/upload-keystore.jks"
            {
              echo "password=$ANDROID_KEYSTORE_PASSWORD"
              echo "keyAlias=upload"
              echo "storeFile=$HOME/.keystores/qntx-app/upload-keystore.jks"
            } > "$HOME/.keystores/qntx-app/keystore.properties"
          '';
        }

        { run = "cargo tauri android init"; }

        {
          name = "Build signed APK";
          run = "cargo tauri android build --apk true";
        }

        {
          name = "Locate APK";
          id = "apk";
          run = ''
            FOUND=$(find gen/android -name '*.apk' -type f | head -1)
            if [ -z "$FOUND" ]; then
              echo "no apk produced"
              exit 1
            fi
            echo "path=$FOUND" >> "$GITHUB_OUTPUT"
            echo "Found $FOUND"
          '';
        }

        {
          name = "Publish the release the updater will find";
          env.GH_TOKEN = "\${{ github.token }}";
          run = ''
            tag="android-''${{ steps.qntx.outputs.version }}.''${{ github.run_number }}"
            gh release create "$tag" "''${{ steps.apk.outputs.path }}" \
              --title "$tag" \
              --notes "Built from ''${{ steps.qntx.outputs.built }}"
          '';
        }
      ];
    };
  };
}
