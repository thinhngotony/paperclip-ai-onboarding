# Paperclip VPS onboarding (Docker + 9Router)

Automates [Paperclip](https://github.com/paperclipai/paperclip) on Docker so it is **usable from the VPS public IP** (or a domain) without manual `allowed-hostname` steps.

- **Default (`PAPERCLIP_NETWORK_PROFILE=vps`)**: detects the server’s **public IPv4**, sets `PAPERCLIP_PUBLIC_URL` and `PAPERCLIP_ALLOWED_HOSTNAMES` (includes that IP plus `127.0.0.1` and `localhost`), recreates the app container, then onboards.
- **9Router** on the same host: by default only **`OPENAI_*`** is set so **Codex / OpenAI-compatible** agents can use `http://host.docker.internal:<port>/v1` with a dashboard API key (default port `20128`).
- **Local-only**: `./scripts/setup.sh --local` keeps everything on `127.0.0.1` only.

## Requirements

- Docker + `docker compose`
- Git, curl, openssl
- Outbound HTTPS (for public-IP detection), unless you set `PAPERCLIP_VPS_HOST` or `PAPERCLIP_PUBLIC_URL`
- TCP **3100** (or `PAPERCLIP_PORT`) open in your cloud firewall if you browse by public IP
- 9Router on the host if you use the default LLM proxy env vars

## One command (typical VPS)

```bash
./scripts/setup.sh
```

After `./scripts/setup.sh` finishes, the terminal shows a **clear admin invite link** (matching your public URL) and writes the same steps to **`START_HERE.txt`** in this directory (`START_HERE.txt` is gitignored). Open that invite once in a browser, then use Paperclip at your public URL.

If the UI only says “check startup logs”, run:

```bash
./scripts/bootstrap-ceo.sh --force
```

That prints the link again and refreshes `START_HERE.txt`.

## If the Host header error still appears

Re-sync env and recreate the server (e.g. after changing IP or domain):

```bash
./scripts/reapply-vps-env.sh
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
./scripts/reapply-vps-env.sh
```

## Options

| Flag | Meaning |
|------|--------|
| `--local` | `PAPERCLIP_NETWORK_PROFILE=local` — loopback only, SSH tunnel friendly |
| `--force-onboard` | Run `onboard -y` again even if `config.json` exists |
| `--update-vendor` | Refresh `vendor/paperclip` from git and rebuild |

Environment (optional):

| Variable | Meaning |
|----------|--------|
| `PAPERCLIP_GIT_URL` / `PAPERCLIP_GIT_REF` | Paperclip git source |
| `VENDOR_DIR` | Clone path (default `./vendor/paperclip`) |

## Scripts

| Script | Purpose |
|--------|--------|
| `./scripts/setup.sh` | Full install + VPS env + compose + onboard |
| `./scripts/reapply-vps-env.sh` | Refresh public URL / allowed hosts + recreate server |
| `./scripts/bootstrap-ceo.sh` | New CEO invite (`--force` to replace) |
| `./scripts/print-remote-hint.sh` | SSH tunnel + public URL hints |
| `START_HERE.txt` | Written by setup / `bootstrap-ceo` — invite URL + public app link (gitignored) |

## Manual `.env`

See `.env.example`. If you create `.env` by hand, run `./scripts/reapply-vps-env.sh` once so `PAPERCLIP_PUBLIC_URL` and `PAPERCLIP_ALLOWED_HOSTNAMES` are applied.

## Claude adapter + 9Router (“hello probe failed”, `ANTHROPIC_API_KEY` warning)

**Claude Code** in the container talks to **`ANTHROPIC_BASE_URL` using the Anthropic API shape.** Many 9Router setups only have **OpenAI-style** `/v1/chat/completions` wired to free keys; the Anthropic route then returns errors like *No active credentials for provider: anthropic*, and Paperclip’s environment test shows **Claude hello probe failed**.

**Default in this repo:** `ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL` are **empty** so the server does not force broken Anthropic calls. Use agents that go through **`OPENAI_API_KEY` + `OPENAI_BASE_URL`** (e.g. **Codex Local**) with a 9Router model id from `/v1/models`.

**If you need the Claude adapter:** configure an **Anthropic** (or Claude-via-subscription) provider in the **9Router dashboard**, then set in `.env` the API key and base URL 9Router documents for Anthropic traffic, and recreate the server:

```bash
./scripts/reapply-vps-env.sh   # if you only changed hostname; or:
docker compose --env-file .env up -d --no-deps --force-recreate server
```

## SSH tunnel (optional)

If you only browse via SSH port forward, use `--local` or keep `PAPERCLIP_NETWORK_PROFILE=local`. See `./scripts/print-remote-hint.sh`.
