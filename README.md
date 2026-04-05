# Paperclip VPS onboarding (Native + 9Router)

Automates [Paperclip](https://github.com/paperclipai/paperclip) on a native VPS (no Docker) so it is **usable from the VPS public IP** (or a domain) without manual `allowed-hostname` steps.

- **Default (`PAPERCLIP_NETWORK_PROFILE=vps`)**: detects the server's **public IPv4**, sets `PAPERCLIP_PUBLIC_URL` and `PAPERCLIP_ALLOWED_HOSTNAMES` (includes that IP plus `127.0.0.1` and `localhost`), restarts the service, then onboards.
- **9Router** on the same host: **`./scripts/setup-native.sh`** probes `http://127.0.0.1:<port>/v1/models`, writes **`OPENAI_BASE_URL=http://127.0.0.1:<port>/v1`**, **`OPENAI_API_KEY`**, and **`ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`** (no `/v1`, per [9Router's Claude integration](https://context7.com/decolua/9router/llms.txt)) plus **`ANTHROPIC_API_KEY`** (same Bearer as OpenAI). Keys are chosen from (in order): existing `.env`, **`NINEROUTER_API_KEY`**, the first key in **`apiKeys`** inside 9Router's **`db.json`**, or the placeholder `9router-local` if your 9Router allows open access.
- **Local-only**: `./scripts/setup-native.sh --local` keeps everything on `127.0.0.1` only.

## Requirements

- Ubuntu 22.04+ or Debian 12+ (other distros may work but require adjustment)
- Git, curl, openssl
- Node.js >= 20 (installed automatically if missing)
- pnpm (installed automatically if missing)
- PostgreSQL 15+ (installed automatically if missing)
- Outbound HTTPS (for public-IP detection), unless you set `PAPERCLIP_VPS_HOST` or `PAPERCLIP_PUBLIC_URL`
- TCP **3100** (or `PAPERCLIP_PORT`) open in your cloud firewall if you browse by public IP
- 9Router on the host if you use the default LLM proxy env vars

## One command (typical VPS)

```bash
./scripts/setup-native.sh
```

After `./scripts/setup-native.sh` finishes, the terminal shows a **clear admin invite link** (matching your public URL) and writes the same steps to **`START_HERE.txt`** in this directory (`START_HERE.txt` is gitignored). Open that invite once in a browser, then use Paperclip at your public URL.

If the UI only says "check startup logs", run:

```bash
./scripts/bootstrap-ceo-native.sh --force
```

That prints the link again and refreshes `START_HERE.txt`.

## Service management

Paperclip runs as a systemd service. Common commands:

```bash
# Check status
systemctl status paperclip

# View logs
journalctl -u paperclip -f

# Restart
systemctl restart paperclip

# Stop/Start
systemctl stop paperclip
systemctl start paperclip
```

## If the Host header error still appears

Re-sync env and restart the service (e.g. after changing IP or domain):

```bash
./scripts/reapply-vps-env-native.sh
```

Or set explicitly in `.env` then reapply:

```bash
# Either fixed IP
PAPERCLIP_VPS_HOST=203.0.113.50

# Or full URL (HTTPS / domain)
PAPERCLIP_PUBLIC_URL=https://paperclip.example.com
```

Then:

```bash
./scripts/reapply-vps-env-native.sh
```

## Options

| Flag | Meaning |
|------|---------|
| `--local` | `PAPERCLIP_NETWORK_PROFILE=local` — loopback only, SSH tunnel friendly |
| `--force-onboard` | Run `onboard -y` again even if `config.json` exists |
| `--update-vendor` | Refresh `vendor/paperclip` from git and rebuild |
| `--skip-deps` | Skip installing system dependencies (Node.js, pnpm, PostgreSQL) |
| `--dry-run` | Show what would be done without executing |

Environment (optional):

| Variable | Meaning |
|----------|---------|
| `PAPERCLIP_GIT_URL` / `PAPERCLIP_GIT_REF` | Paperclip git source |
| `VENDOR_DIR` | Clone path (default `./vendor/paperclip`) |
| `NINEROUTER_PORT` / `NINEROUTER_BIND_HOST` | Override 9Router listen address / port if autodetection fails |
| `NINEROUTER_DB_PATH` | Path to 9Router `db.json` (to read dashboard `apiKeys[]`) |
| `NINEROUTER_API_KEY` | Explicit key to store as `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` for Paperclip |
| `NINEROUTER_ANTHROPIC_BASE_URL` | Optional; default `http://127.0.0.1:<port>` for Claude → 9Router |

## Scripts

| Script | Purpose |
|--------|---------|
| `./scripts/setup-native.sh` | Full native install + VPS env + build + systemd service + onboard |
| `./scripts/reapply-vps-env-native.sh` | Refresh public URL / allowed hosts + restart service |
| `./scripts/sync-9router-env-native.sh` | Re-detect 9Router port + refresh `OPENAI_*` in `.env` + restart |
| `./scripts/bootstrap-ceo-native.sh` | New CEO invite (`--force` to replace) |
| `./scripts/print-remote-hint.sh` | SSH tunnel + public URL hints |
| `START_HERE.txt` | Written by setup / `bootstrap-ceo-native` — invite URL + public app link (gitignored) |

## Manual `.env`

See `.env.example`. If you create `.env` by hand, run `./scripts/reapply-vps-env-native.sh` once so `PAPERCLIP_PUBLIC_URL` and `PAPERCLIP_ALLOWED_HOSTNAMES` are applied.

## Re-link Paperclip after changing 9Router

If 9Router was already running when you installed Paperclip, or you changed its port or API key:

```bash
./scripts/sync-9router-env-native.sh
```

Replace the stored OpenAI key (e.g. after creating a key in the 9Router dashboard):

```bash
./scripts/sync-9router-env-native.sh --refresh-key
```

## Claude adapter + 9Router ("hello probe failed", `ANTHROPIC_API_KEY` warning)

**Claude Code** on the native host talks to **`ANTHROPIC_BASE_URL` using the Anthropic API shape.** Many 9Router setups only have **OpenAI-style** `/v1/chat/completions` wired to free keys; the Anthropic route then returns errors like *No active credentials for provider: anthropic*, and Paperclip's environment test shows **Claude hello probe failed**.

**Default in this repo:** `ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL` are **empty** so the server does not force broken Anthropic calls. Use agents that go through **`OPENAI_API_KEY` + `OPENAI_BASE_URL`** (e.g. **Codex Local**) with a 9Router model id from `/v1/models`.

### CEO / agent shows "Not logged in · Please run /login" (`claude_local`)

That adapter does **not** use 9Router's OpenAI path. It needs **either**:

1. **Anthropic API key** — add to `.env` then restart the service:
   - `ANTHROPIC_API_KEY=sk-ant-api03-...` (from [Anthropic Console](https://console.anthropic.com/))
   - Optional: `ANTHROPIC_BASE_URL=...` if 9Router (or another proxy) exposes an Anthropic-compatible endpoint.
   - Then: `systemctl restart paperclip`

2. **Claude subscription (CLI login)** — one-time, interactive, on the **VPS** (needs a terminal + browser for OAuth):

   ```bash
   cd vendor/paperclip && pnpm claude login
   ```

   Run as you normally SSH into the host; finish sign-in in the browser when the CLI prints a URL.

3. **Avoid Claude for this agent** — in Paperclip, change the CEO (or agent) **adapter** from **Claude Local** to **Codex Local** (or another OpenAI-compatible adapter) so invocations use **`OPENAI_*`** and your 9Router `/v1` setup.

**If you need the Claude adapter via 9Router Anthropic:** configure an **Anthropic** provider in the **9Router dashboard**, set `ANTHROPIC_API_KEY` and the `ANTHROPIC_BASE_URL` 9Router documents, then restart:

```bash
./scripts/reapply-vps-env-native.sh # if you only changed hostname; or:
systemctl restart paperclip
```

## SSH tunnel (optional)

If you only browse via SSH port forward, use `--local` or keep `PAPERCLIP_NETWORK_PROFILE=local`. See `./scripts/print-remote-hint.sh`.

## Troubleshooting

### Service won't start

Check logs:
```bash
journalctl -u paperclip -n 100
```

Common issues:
- PostgreSQL not running: `systemctl start postgresql`
- Port already in use: check `PAPERCLIP_PORT` in `.env`
- Database not initialized: ensure migrations ran

### Rebuilding Paperclip

If you need to rebuild after updating the vendor:
```bash
./scripts/setup-native.sh --update-vendor
```

Or manually:
```bash
cd vendor/paperclip
pnpm install --frozen-lockfile
pnpm -r build
systemctl restart paperclip
```