# Paperclip local onboarding (Docker + 9Router)

Automates [Paperclip](https://github.com/paperclipai/paperclip) on Docker with:

- **UI and auth** at `http://127.0.0.1:3100` (no temporary public domain)
- **9Router** on the same machine: LLM traffic goes to `http://host.docker.internal:<port>/v1` from the Paperclip container (9Router itself stays on `http://127.0.0.1:20128` by default on the host)
- **Postgres** in Compose, **first admin** via `paperclipai onboard -y` (bootstrap CEO invite printed once)

## Requirements

- Docker + `docker compose`
- Git, curl, openssl
- 9Router listening on the host (default port `20128`)

## One command

```bash
./scripts/setup.sh
```

First run creates `.env` with generated secrets, clones Paperclip into `vendor/paperclip` (gitignored), builds the image, starts the stack, waits for `/api/health`, runs onboarding, and restarts the server.

## Options

| Flag | Meaning |
|------|--------|
| `--force-onboard` | Run onboarding again even if `config.json` already exists |
| `--update-vendor` | `git fetch` / reset Paperclip source to `PAPERCLIP_GIT_REF`, then rebuild |

Environment (optional):

| Variable | Default | Meaning |
|----------|---------|--------|
| `PAPERCLIP_GIT_URL` | `https://github.com/paperclipai/paperclip.git` | Upstream repo |
| `PAPERCLIP_GIT_REF` | `master` | Branch or tag |
| `VENDOR_DIR` | `./vendor/paperclip` | Clone path |

## After install

- Open the printed **invite URL** once to create the instance admin.
- Pick **model IDs** from your 9Router `/v1/models` list for agents (e.g. combo names like `free` / `super`).

New invite after admin exists:

```bash
./scripts/bootstrap-ceo.sh
```

## Manual `.env`

Copy `.env.example` to `.env` and set `BETTER_AUTH_SECRET` / `PAPERCLIP_AGENT_JWT_SECRET` if you do not use the generated file from `setup.sh`.
