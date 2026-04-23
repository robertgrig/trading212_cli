# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file bash CLI for the Trading 212 Public API v0. Zero runtime deps beyond `curl` + `jq`. Agent-discoverable via the `schema` subcommand. **Demo (paper-trading) is the default env; live trading requires explicit opt-in.**

## Naming

The CLI binary is **`trading212`** (script on disk, `install.sh` symlink target, usage strings, error prefix). The credential directory and env vars intentionally stay `~/.t212/` and `T212_*` — they're stable external config surfaces and existing stored keys live there. Don't "fix" the env-var/dir names to match the binary rename.

## Install / run

```bash
./install.sh        # symlinks ~/bin/trading212 → ./trading212, mkdir -p ~/.t212
trading212 --version
trading212 auth demo    # prompts for API key + secret, writes mode-600 ~/.t212/demo.{key,secret}
trading212 account summary
```

No build step, no lint config, no tests yet. The README calls the test story out explicitly.

## Architecture (read this before editing the script)

The script is one file organized into labeled sections. Touch-points for common changes:

- **`parse_globals`** (bottom of file) strips global flags from `argv` and exports them as env vars (`T212_FLAG_ENV`, `T212_DRY_RUN`, `T212_YES`, `T212_CLIENT_ID`, `T212_VERBOSE`). Helpers read the env vars — they don't receive flags as args. If you add a new global flag, wire it here AND export it.
- **`main`** dispatches on a `"$resource:$action"` case. Adding a command = add a `cmd_<resource>_<action>` function + one case arm. Keep the pattern.
- **`http()`** is the only HTTP entry point — handles auth header, rate-limit retry (once, gated by `T212_RETRIED`), 4xx/5xx parsing via `.message // .code // .error // .detail // .`. Never call `curl` directly elsewhere.
- **`paginate()`** follows `nextPagePath` until null and returns a single merged JSON array. Two non-obvious bits to preserve: (a) it strips the `/api/v0` prefix from `nextPagePath` because `base_url()` already includes it; (b) `(.items // .)[]` handles both the `{items, nextPagePath}` envelope and bare-array responses — don't "simplify" either.
- **`_mutate()`** is the single gate for every write. It orders: dry-run short-circuit → idempotency cache check → live-confirm prompt → `http` call → idempotency record. All POST/DELETE command functions MUST go through `_mutate`; don't call `http` directly from a write path or you'll bypass all three safeties.
- **`_order_body`** is the single jq builder for every order body (`buy`/`sell`/`limit`/`stop`/`stop-limit`). Optional fields (`limitPrice`, `stopPrice`) are added only when non-empty. New order types should extend this helper rather than build JSON inline.
- **`cmd_schema`** reads the vendored `api.json` with `jq`. It's the mechanism by which agents discover the API surface — keep its output stable.
- **Credential paths and env-var names are still `T212_*` / `~/.t212/`** despite the script rename to `trading212`. Don't "fix" this to match the binary name — existing users' stored keys live there.
- **Target shell is bash 3.2** (macOS default). No `declare -n` / nameref, no `${var,,}`, no associative arrays in new code. The order-cmd flag parsing uses inline `while/case` rather than a shared nameref helper for this reason.

### Env resolution precedence

`--live`/`--demo` flag (`T212_FLAG_ENV`) > `$T212_ENV` env > default `demo`. Only `demo|live` are valid. `base_url()` returns the URL *including* `/api/v0`, so every path passed to `http`/`paginate` must start at `/equity/...`, not `/api/v0/equity/...`.

`T212_HOME` (default `~/.t212`) overrides the credential/cache dir; `T212_API_JSON` overrides the `api.json` path (falls back to `$T212_HOME/api.json` if the script-local copy is missing). Useful for isolated test runs.

### Live-trade safety invariants

- Live mutations show a stderr banner and require typing `yes` interactively.
- The interactive prompt is skipped **only when BOTH** `T212_NONINTERACTIVE=1` AND `T212_YES=1` (set via `--yes`) are present. Either alone is not enough. Don't loosen this.
- `--dry-run` prints the resolved `curl` (with `Authorization` redacted) and exits 0 before any network call or idempotency record.

### Idempotency shim

Opt-in via `--safe` (auto-uuid) or `--client-id <id>`. Hash inputs: `env + method + path + body + client-id`. Cache at `~/.t212/submitted/<sha256>`. Replays responses for ≤60s-old duplicates. Entries older than 1440 min are purged opportunistically during `trading212 auth`. This is a shell-history-rerun shim, not real server-side idempotency (the API has none).

## Working with `api.json`

Vendored OpenAPI 3.0.1 spec (~76 KB). Prefer targeted `jq` queries over full reads:

```bash
jq '.paths["/api/v0/equity/orders/limit"]' api.json    # one endpoint
jq '.components.schemas.HistoricalOrder' api.json      # one schema
jq '.paths | keys' api.json                            # path list
```

Re-fetch from `https://docs.trading212.com/_bundle/api.json?download` if stale. Pies endpoints exist in the spec but are deprecated — they're intentionally **not wired into commands**; `trading212 schema` still exposes them. Don't add pies command handlers without confirming with the user.

## Design decisions

Auth is `Authorization: Basic base64(API_KEY:API_SECRET)` — two files per env at `~/.t212/{env}.key` + `~/.t212/{env}.secret` (mode 600). This matches the spec's `authWithSecretKey` security scheme. Bearer was tried briefly but Trading 212 issues a key+secret pair (not a single token), so Bearer silently fails or 401s. The spec's second scheme `legacyApiKeyHeader` (raw key in `Authorization`) is not wired — only use if Trading 212 later issues a legacy-style key without a secret. Other non-auth decisions: cursor pagination via `nextPagePath`, `x-ratelimit-reset` is a Unix epoch (not seconds-to-wait), there is no `/positions/{ticker}` endpoint (`positions show` is a client-side filter over the list), and `remaining:0` on a 200 is a budget indicator — only 429 triggers retry.
