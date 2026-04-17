# trading212_cli

A bash CLI for the [Trading 212 Public API](https://docs.trading212.com/api): single-file executable, zero runtime deps beyond `curl` + `jq`, agent-discoverable via `trading212 schema`.

The executable is named `trading212`; the config directory is `~/.t212/` and env vars are `T212_*` (kept stable regardless of binary name).

**Defaults to the demo (paper-trading) environment.** Live trading requires explicit opt-in.

## Install (local)

```bash
cd ~/Private/trading212_cli
./install.sh     # symlinks ~/bin/trading212 → ~/Private/trading212_cli/trading212
```

`~/bin` must be on `$PATH`. If it isn't, the installer prints the export line to add to `~/.zshrc`.

## Auth

Generate an API key pair in the Trading 212 app → Settings → API (Beta). Then:

```bash
trading212 auth demo     # stores ~/.t212/demo.{key,secret} (mode 600)
trading212 auth live     # stores ~/.t212/live.{key,secret}
```

Credentials are sent as `Authorization: Basic base64(API_KEY:API_SECRET)` per the API spec. Plain file storage (mode 600 in a 700 directory). No keychain.

## Quick tour

```bash
trading212 env                            # prints active env + base URL
trading212 account summary
trading212 positions list
trading212 instruments search AAPL
trading212 orders list
trading212 history orders --all           # follows cursor pagination
trading212 schema                         # list all endpoints
trading212 schema GET /api/v0/equity/orders
```

## Placing orders (demo)

```bash
trading212 orders buy AAPL 1
trading212 orders sell AAPL 0.5           # CLI flips the sign for you
trading212 orders limit AAPL 1 --price 175.50
trading212 orders cancel 12345678
```

## Placing orders (live)

Opt in per-command — CLI prints a stderr banner and prompts for `yes`:

```bash
trading212 --live orders buy AAPL 1
#=> !! LIVE TRADING - real money at risk
#=> !! POST /equity/orders/market
#=> Type 'yes' to continue:
```

Or per-session:

```bash
T212_ENV=live trading212 orders buy AAPL 1
```

To script live trades without the prompt, BOTH must be set:

```bash
T212_NONINTERACTIVE=1 trading212 --live --yes orders buy AAPL 1
```

## Safety tools

- **`--dry-run`** on any mutation prints the resolved `curl` and exits 0 without sending. Headers redacted.

  ```bash
  trading212 --live orders buy AAPL 1 --dry-run
  ```

- **`--safe` / `--client-id <uuid>`** — idempotency shim. The CLI hashes `env + method + path + body + client-id` and caches the response at `~/.t212/submitted/<hash>`. A second submission within 60s replays the cached response instead of re-sending. Not a substitute for server-side idempotency (the API lacks one) but catches shell-history re-runs.

  ```bash
  trading212 --live orders buy AAPL 1 --safe
  ```

- **Rate-limit retry** — on a real 429, the CLI sleeps until `x-ratelimit-reset` (Unix timestamp) and retries **once**. A second 429 fails loudly. `x-ratelimit-remaining: 0` on a 200 is just a budget indicator and is NOT treated as a failure.

## Schema (agent-friendly)

```bash
trading212 schema                         # METHOD<tab>path<tab>summary for all 22 endpoints
trading212 schema --json                  # full OpenAPI spec (agent mode)
trading212 schema GET /api/v0/equity/orders/{id}
```

`api.json` is vendored alongside the script (fetched from `https://docs.trading212.com/_bundle/api.json?download`).

## Full command map

| Command | Method | Endpoint |
|---|---|---|
| `trading212 auth demo\|live` | — | — |
| `trading212 env` | — | — |
| `trading212 schema [...]` | — | local |
| `trading212 account summary` | GET | `/equity/account/summary` |
| `trading212 instruments list [--all]` | GET | `/equity/metadata/instruments` |
| `trading212 instruments search <q>` | GET | `/equity/metadata/instruments` (client filter) |
| `trading212 exchanges list` | GET | `/equity/metadata/exchanges` |
| `trading212 positions list` | GET | `/equity/positions` |
| `trading212 positions show <ticker>` | GET | `/equity/positions` (client filter) |
| `trading212 orders list` | GET | `/equity/orders` |
| `trading212 orders show <id>` | GET | `/equity/orders/{id}` |
| `trading212 orders buy <ticker> <qty>` | POST | `/equity/orders/market` |
| `trading212 orders sell <ticker> <qty>` | POST | `/equity/orders/market` (qty negated) |
| `trading212 orders limit <t> <q> --price P [--tif]` | POST | `/equity/orders/limit` |
| `trading212 orders stop <t> <q> --stop S [--tif]` | POST | `/equity/orders/stop` |
| `trading212 orders stop-limit <t> <q> --stop --price [--tif]` | POST | `/equity/orders/stop_limit` |
| `trading212 orders cancel <id>` | DELETE | `/equity/orders/{id}` |
| `trading212 history orders [--all] [--limit N] [--ticker T]` | GET | `/equity/history/orders` |
| `trading212 history dividends [...]` | GET | `/equity/history/dividends` |
| `trading212 history transactions [...]` | GET | `/equity/history/transactions` |
| `trading212 exports list` | GET | `/equity/history/exports` |
| `trading212 exports request [flags]` | POST | `/equity/history/exports` |

Pies endpoints are present in `api.json` but not wired into commands (spec marks them deprecated). Use `trading212 schema` if you need them.

## Design notes

- **Auth**: `Authorization: Basic base64(API_KEY:API_SECRET)`.
- **Pagination**: cursor-based; response is `{items, nextPagePath}`. `--all` follows `nextPagePath` until it's null.
- **Errors**: 4xx/5xx bodies are parsed with `.message // .code // .error // .detail // .`, printed via `die()`.
- **Tests**: none yet.
