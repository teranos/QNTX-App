# QNTX's checks

"it needs to be abolutely clear you cant attribute meaning to nil like granting all namepsaces"

"i want it to operate under the assumption of no linter surveilance"

"it needs to not know it is being scrutised on this Axis."

"IT IS POST MERGE, SO AFTER THE FACT, THAT SOMETIES BUT NOT ALWAYS, THAT THERE WOULD BE ANOTHER ROUND, ANOTHER PR, WHERE WE FIX IT, BUT THIS ISNT UNCONDITIONAL, THIS IS SUBJECT TO HUMAN COICE ON HOW TO SPEND AI CODING AGENT BUDGET AND WHAT MODEL TO MAKE IT DO IT."

"THE BANS, THE CHECKS, THEY SHOULD BE OWNED BY NOT QNTX"

"SAME FOR THE REGEX BAN, MAKE IT NOT OWNED BY QNTX, MAKE IT AN AFTER THE FACT CLEAN UP AND CONSIDERATIONS THING"

"MAKE IT OWNED BY QNTX-App"

QNTX does not run these and does not mention them. This repo reaches over, as
it does for the build: `checks.yml` checks QNTX out at its newest `v*` tag,
lays what is here over it at the same paths, and runs them. Each tag is
checked once. A dispatch names the QNTX ref it checks, `main`, a tag or a
commit, and checks it whether or not it was checked before. A red run is a
finding, not a gate.

## What is held

**Zero means zero:** `0` always means literal zero, with no special disabled or unlimited semantics. `0` workers is no workers. `0` ticker interval is no ticking. For unlimited, use a high value. For the default, omit the field.

**Nil is nil:** nil, empty and zero mean nothing. Meaning given to nothing is banned outright: no granting all namespaces, no unrestricted, no every. Banned the same way: a discarded result, a catch-all branch, a fallback value, an error logged and carried on from, a config default.

**Regex:** banned in code; string methods (`split`, `indexOf`, `includes`, `startsWith`, `endsWith`, `slice`) instead. No tool holds it: it is a consideration for the round after.

## What runs

- `internal/tools/nilcheck`, `spawncheck`, `tagcheck`, and `.golangci.yml`: Go and Rust.
- `web/eslint.config.js`, `web/eslint-suppressions.json`, `web/font-size-ban.ts`: the web bans.
- `cargo fmt --check` and `cargo clippy -Dwarnings`.
- `web/browser/live.browser.ts` with `web/ts/specimens.ts`: every element, on the node, as its CI user.
- `.github/workflows/live-gate.yml` and `live-verdict.yml` are kept as QNTX had them, and run nowhere.
