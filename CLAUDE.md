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
trading212 auth demo    # prompts for API key + secret, writes mode-600 files
trading212 account summary
```

No build step, no lint config, no tests yet. The README calls the test story out explicitly.

## Architecture (read this before editing the script)

The script is one file organized into labeled sections. Touch-points for common changes:

- **`parse_globals`** (bottom of file) strips global flags from `argv` and exports them as env vars (`T212_FLAG_ENV`, `T212_DRY_RUN`, `T212_YES`, `T212_CLIENT_ID`, `T212_VERBOSE`). Helpers read the env vars — they don't receive flags as args. If you add a new global flag, wire it here AND export it.
- **`main`** dispatches on a `"$resource:$action"` case. Adding a command = add a `cmd_<resource>_<action>` function + one case arm. Keep the pattern.
- **`http()`** is the only HTTP entry point — handles auth header, rate-limit retry (once, gated by `T212_RETRIED`), 4xx/5xx parsing via `.message // .code // .error // .detail // .`. Never call `curl` directly elsewhere.
- **`paginate()`** follows `nextPagePath` until null and returns a single merged JSON array. **It strips the `/api/v0` prefix** from `nextPagePath` because `base_url()` already includes that prefix — don't "simplify" this away.
- **`_mutate()`** is the single gate for every write. It orders: dry-run short-circuit → idempotency cache check → live-confirm prompt → `http` call → idempotency record. All POST/DELETE command functions MUST go through `_mutate`; don't call `http` directly from a write path or you'll bypass all three safeties.
- **`cmd_schema`** reads the vendored `api.json` with `jq`. It's the mechanism by which agents discover the API surface — keep its output stable.
- **Credential paths and env-var names are still `T212_*` / `~/.t212/`** despite the script rename to `trading212`. Don't "fix" this to match the binary name — existing users' stored keys live there.

### Env resolution precedence

`--live`/`--demo` flag (`T212_FLAG_ENV`) > `$T212_ENV` env > default `demo`. Only `demo|live` are valid. `base_url()` returns the URL *including* `/api/v0`, so every path passed to `http`/`paginate` must start at `/equity/...`, not `/api/v0/equity/...`.

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

## Design decisions from Phase 0

`PHASE0.md` is the pre-code validation transcript. Read it when touching auth, rate limits, pagination, or error handling — it captures *why* the current shapes are what they are (HTTP Basic forcing two credential files, `x-ratelimit-reset` being a Unix epoch and not seconds-to-wait, the `/positions/{ticker}` endpoint not existing, etc.).
