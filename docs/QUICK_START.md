# Quick Start Guide

## 1. Install Paperclip with 9Router

```bash
# Clone the repository
git clone https://github.com/thinhngotony/paperclip-ai-onboarding.git
cd paperclip-ai-onboarding

# Run setup (requires 9Router already installed)
./scripts/setup-native.sh
```

## 2. Access Paperclip

After setup completes, check `START_HERE.txt` for:
- Admin invite link (first-time setup)
- Public URL

## 3. Configure Agent to Use 9Router

**IMPORTANT:** By default, agents use "Claude Local" adapter which won't work with 9Router.

1. Open Paperclip UI
2. Go to **Settings** → **Agents**
3. Select your agent (e.g., CEO)
4. Change **Adapter** to **"Codex Local"**
5. Select a model:
   - Free: `free`, `gh/gpt-4o-mini`
   - Premium: `gh/gpt-5.3-codex`, `gh/claude-opus-4.6`

See [ADAPTER_CONFIGURATION.md](ADAPTER_CONFIGURATION.md) for details.

## 4. Test Your Agent

Create a task or chat with the agent to verify it's working.

## Common Issues

### "Not logged in · Please run /login"
- Agent is using Claude Local adapter
- **Fix:** Change adapter to Codex Local (see step 3)

### Service not starting
```bash
# Check logs
journalctl -u paperclip -f

# Check 9Router
curl http://127.0.0.1:20128/v1/models
```

### Need to update 9Router config
```bash
./scripts/sync-9router-env-native.sh
```

## Available Models

View all 9Router models:
```bash
curl -s http://127.0.0.1:20128/v1/models | python3 -m json.tool | grep '"id"'
```

Recommended models:
- **Coding:** `gh/gpt-5.3-codex`, `cx/gpt-5.4`
- **General:** `gh/claude-opus-4.6`, `cu/claude-4.6-opus-max`
- **Budget:** `free`, `gh/gpt-4o-mini`, `gh/claude-haiku-4.5`
