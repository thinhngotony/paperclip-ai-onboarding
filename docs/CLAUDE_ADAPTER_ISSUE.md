# Claude Local Adapter Issue with 9Router

## Problem

The "Claude Local" adapter in Paperclip uses the Claude CLI, which has a **model prefix incompatibility** with 9Router.

### What Happens

1. Claude CLI tries to use model: `claude-sonnet-4-6` (no prefix)
2. 9Router expects model: `gh/claude-sonnet-4-6` (with provider prefix)
3. Result: "There's an issue with the selected model" error

### Why This Happens

- Claude CLI doesn't add provider prefixes to model names
- 9Router requires provider prefixes for most models (gh/, cu/, cx/, cc/)
- Only a few models work without prefix: `claude`, `free`, `super`

## Solution: Use Codex Local Adapter Instead

**RECOMMENDED:** Change your agent adapter from "Claude Local" to "Codex Local"

### Steps:
1. Open Paperclip UI
2. Go to Settings → Agents
3. Select your agent
4. Change **Adapter** from "Claude Local" to **"Codex Local"**
5. Select a model with prefix:
   - `gh/gpt-5.3-codex` (coding)
   - `gh/claude-opus-4.6` (best quality)
   - `gh/claude-sonnet-4.6` (balanced)
   - `free` (budget)

Codex Local adapter uses OpenAI-compatible API which works perfectly with 9Router's model prefixes.

## Alternative: Use Direct Anthropic API

If you must use Claude Local adapter:

### Option 1: Real Anthropic API Key
```bash
# Edit /etc/paperclip/.env
ANTHROPIC_API_KEY=sk-ant-api03-YOUR_KEY_HERE
ANTHROPIC_BASE_URL=https://api.anthropic.com

# Restart
systemctl restart paperclip
```

### Option 2: Claude CLI Login
```bash
cd /opt/paperclip
sudo -u paperclip pnpm claude login
# Follow browser OAuth flow
systemctl restart paperclip
```

### Option 3: Configure 9Router with Unprefixed Models

This requires 9Router configuration changes (advanced):
- Add models without prefixes: `claude-sonnet-4-6`, `claude-opus-4-6`
- Not recommended as it breaks 9Router's provider system

## Why We Don't Set ANTHROPIC_* by Default

Previous versions of this setup configured:
```bash
ANTHROPIC_BASE_URL=http://127.0.0.1:20128
ANTHROPIC_API_KEY=9router-local
```

This caused:
- ❌ Claude CLI fails with "model doesn't exist" errors
- ❌ Confusing error messages for users
- ❌ Users think 9Router is broken

By NOT setting ANTHROPIC_*, users are forced to either:
- ✅ Use Codex Local adapter (works perfectly)
- ✅ Add real Anthropic API key (clear requirement)
- ✅ Run claude login (clear requirement)

## Technical Details

### Claude CLI Model Resolution

When Claude CLI runs with `ANTHROPIC_BASE_URL=http://127.0.0.1:20128`:

1. CLI defaults to model: `claude-sonnet-4-6`
2. Makes request to: `POST http://127.0.0.1:20128/v1/messages`
3. Request body: `{"model": "claude-sonnet-4-6", ...}`
4. 9Router looks for model ID: `claude-sonnet-4-6`
5. 9Router only has: `gh/claude-sonnet-4-6`, `cc/claude-sonnet-4-6`, etc.
6. Returns error: "model doesn't exist"

### Why Codex Local Works

Codex Local adapter:
1. Uses OpenAI-compatible API
2. Sends model ID exactly as configured in UI
3. User configures: `gh/gpt-5.3-codex`
4. Request: `{"model": "gh/gpt-5.3-codex", ...}`
5. 9Router finds exact match
6. ✅ Works perfectly

## Error Messages Explained

### "Claude hello probe failed"
- Paperclip tests Claude adapter on startup
- Test fails because model doesn't exist
- Agent shows as "Failed" in UI

### "There's an issue with the selected model (claude-sonnet-4-6)"
- Claude CLI tried to use default model
- Model doesn't exist in 9Router (needs prefix)

### "ANTHROPIC_API_KEY is set. Claude will use API-key auth"
- Warning that Claude CLI will use API key instead of subscription
- Not an error, just informational

## Recommended Configuration

**For 9Router users:**
```bash
# /etc/paperclip/.env
OPENAI_BASE_URL=http://127.0.0.1:20128/v1
OPENAI_API_KEY=9router-local

# NO ANTHROPIC_* variables
# Use Codex Local adapter in Paperclip UI
```

**For Anthropic API users:**
```bash
# /etc/paperclip/.env
OPENAI_BASE_URL=http://127.0.0.1:20128/v1
OPENAI_API_KEY=9router-local

ANTHROPIC_API_KEY=sk-ant-api03-YOUR_KEY
ANTHROPIC_BASE_URL=https://api.anthropic.com

# Can use both Claude Local and Codex Local adapters
```

## Summary

- ❌ Claude Local + 9Router = Model prefix incompatibility
- ✅ Codex Local + 9Router = Works perfectly
- ✅ Claude Local + Real Anthropic API = Works perfectly

**Default setup now uses Codex Local adapter only.**
