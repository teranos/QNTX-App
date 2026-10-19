# The checks workflow, emitted to .github/workflows/checks.yml and never edited by hand:
#   nix eval --json --file ci/checks.nix | jq . > .github/workflows/checks.yml

# "it needs to run one, on tag"

# "MAKE IT OWNED BY QNTX-App"
let
  tag = "\${{ needs.tag.outputs.tag }}";

  # This repo, then QNTX at the tag at qntx/, with checks/ laid over it at QNTX's paths.
  # Full history: golangci answers for what changed since the tag before.
  overQNTX = [
    { uses = "actions/checkout@v5"; }

    {
      name = "QNTX at ${tag}";
      uses = "actions/checkout@v5";
      "with" = {
        repository = "teranos/QNTX";
        ref = tag;
        path = "qntx";
        fetch-depth = 0;
      };
    }

    {
      name = "The checks, laid over QNTX";
      run = "rsync -a --exclude README.md checks/ qntx/";
    }
  ];

  # Each check says what it found; one red check does not hide the next.
  always = step: step // { "if" = "always()"; };

  fresh = "needs.tag.outputs.fresh == 'true'";
in
{
  name = "checks";

  # QNTX knows nothing of this repo, so the tag is asked for every hour, not told.
  # A tag already checked is not checked again.
  on = {
    schedule = [{ cron = "17 * * * *"; }];
    workflow_dispatch = null;
  };

  concurrency = {
    group = "checks";
    cancel-in-progress = false;
  };

  jobs = {
    tag = {
      runs-on = "ubuntu-latest";
      outputs = {
        tag = "\${{ steps.newest.outputs.tag }}";
        fresh = "\${{ steps.seen.outputs.cache-hit != 'true' }}";
      };
      steps = [
        {
          id = "newest";
          name = "QNTX's newest tag";
          run = ''
            newest=$(git ls-remote --tags --refs https://github.com/teranos/QNTX 'v*' | cut -f2 | cut -d/ -f3 | sort -V | tail -1)
            echo "tag=$newest" >> "$GITHUB_OUTPUT"
            echo "QNTX's newest tag is $newest"
          '';
        }

        {
          id = "seen";
          name = "Whether it was checked";
          uses = "actions/cache/restore@v4";
          "with" = {
            path = "checked";
            key = "checked-\${{ steps.newest.outputs.tag }}";
            lookup-only = true;
          };
        }
      ];
    };

    go = {
      needs = "tag";
      "if" = fresh;
      runs-on = "ubuntu-latest";
      steps = overQNTX ++ [
        {
          uses = "actions/setup-go@v5";
          "with".go-version-file = "qntx/go.mod";
        }

        {
          uses = "dtolnay/rust-toolchain@stable";
          "with".targets = "wasm32-unknown-unknown";
        }

        {
          name = "What golangci builds against";
          working-directory = "qntx";
          run = ''
            cargo install wasm-pack --locked
            make ats
            make rust-sqlite
          '';
        }

        {
          name = "Build tags";
          working-directory = "qntx";
          run = "go run ./internal/tools/tagcheck";
        }

        (always {
          name = "Goroutines through sacred";
          working-directory = "qntx";
          run = "go run ./internal/tools/spawncheck";
        })

        (always {
          name = "Nil is nil";
          working-directory = "qntx";
          run = "go run ./internal/tools/nilcheck";
        })

        (always {
          name = "golangci, on what changed since the tag before";
          working-directory = "qntx";
          run = ''
            before=$(git tag -l 'v*' | sort -V | grep -B1 -x -F '${tag}' | head -1)
            go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.7.2 run --new-from-rev "$before" ./...
          '';
        })
      ];
    };

    web = {
      needs = "tag";
      "if" = fresh;
      runs-on = "ubuntu-latest";
      steps = overQNTX ++ [
        {
          uses = "oven-sh/setup-bun@v2";
          "with".bun-version = "latest";
        }

        {
          working-directory = "qntx/web";
          run = "bun install";
        }

        {
          name = "The web bans";
          working-directory = "qntx/web";
          run = "bun x eslint ts --max-warnings 0";
        }

        (always {
          name = "Text size is the package's";
          working-directory = "qntx/web";
          run = "bun run font-size-ban.ts";
        })

        (always {
          name = "The bans' own tests";
          working-directory = "qntx/web";
          run = "bun test font-size-ban.test.ts ts/table-cell.lint.test.ts";
        })
      ];
    };

    rust = {
      needs = "tag";
      "if" = fresh;
      runs-on = "ubuntu-latest";
      # The toolchain QNTX's flake pins: stable moves, and a newer clippy names what QNTX's never did.
      steps = overQNTX ++ [
        {
          uses = "cachix/install-nix-action@v30";
          "with".extra_nix_config = ''
            experimental-features = nix-command flakes
          '';
        }

        {
          name = "Formatting";
          working-directory = "qntx";
          run = "nix develop --command cargo fmt --all --check";
        }

        (always {
          name = "Clippy";
          working-directory = "qntx";
          run = "nix develop --command cargo clippy --workspace --exclude ats-duckdb --exclude qntx-reduce-plugin --all-targets";
          env.RUSTFLAGS = "-Dwarnings";
        })
      ];
    };

    # Every element of the tag's page, against the node, as its CI user (checks/web/browser).
    elements = {
      needs = "tag";
      "if" = fresh;
      runs-on = "ubuntu-latest";
      steps = overQNTX ++ [
        {
          uses = "dtolnay/rust-toolchain@stable";
          "with".targets = "wasm32-unknown-unknown";
        }

        {
          working-directory = "qntx";
          run = ''
            cargo install wasm-pack --locked
            make ats laye
          '';
        }

        {
          uses = "oven-sh/setup-bun@v2";
          "with".bun-version = "latest";
        }

        {
          working-directory = "qntx/web";
          run = ''
            bun install
            bunx playwright install --with-deps chromium webkit
          '';
        }

        {
          name = "Every element can be reached whole";
          working-directory = "qntx/web";
          env = {
            CI = "1";
            QNTX_GATE_API = "\${{ vars.QNTX_GATE_API }}";
            QNTX_GATE_ORIGIN = "\${{ vars.QNTX_GATE_ORIGIN }}";
            QNTX_GATE_TOKEN = "\${{ secrets.QNTX_GATE_TOKEN }}";
          };
          run = "bunx playwright test -c browser live.browser.ts --workers 1";
        }
      ];
    };

    # Whatever the checks found, the tag was checked.
    checked = {
      needs = [ "tag" "go" "web" "rust" "elements" ];
      "if" = "always() && ${fresh}";
      runs-on = "ubuntu-latest";
      steps = [
        {
          run = "mkdir -p checked && echo '${tag}' > checked/tag";
        }

        {
          uses = "actions/cache/save@v4";
          "with" = {
            path = "checked";
            key = "checked-${tag}";
          };
        }
      ];
    };
  };
}
