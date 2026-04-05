# Configuring Paperclip Agents to Use 9Router

## Problem
By default, Paperclip agents may use the "Claude Local" adapter, which requires:
- Claude CLI authentication (`pnpm claude login`)
- OR an Anthropic API key

This doesn't use 9Router's free models.

## Solution: Change Agent Adapter to Use 9Router

### Step 1: Access Paperclip UI
Open your Paperclip instance:
- Public: http://YOUR_IP:3100
- Local: http://127.0.0.1:3100

### Step 2: Configure Agent Adapter
1. Navigate to **Settings** or **Agents** section
2. Select your agent (e.g., CEO)
3. Change **Adapter** from "Claude Local" to one of:
   - **Codex Local** (recommended for 9Router)
   - **OpenCode Local** (alternative)

### Step 3: Select 9Router Model
After changing adapter, select a model from 9Router's available models:

**Free/Budget Models:**
- `free` - Free tier model
- `gh/gpt-4o-mini` - GitHub free tier
- `gh/claude-haiku-4.5` - GitHub free tier

**Premium Models (if you have 9Router credits):**
- `gh/gpt-5.3-codex` - Latest GPT coding model
- `gh/claude-opus-4.6` - Latest Claude Opus
- `cu/claude-4.6-opus-max` - Cursor tier
- `cx/gpt-5.4` - Codex tier

**View all available models:**
```bash
curl -s http://127.0.0.1:20128/v1/models | python3 -m json.tool
```

### Step 4: Test the Agent
Create a new task or chat with the agent to verify it's using 9Router.

## Alternative: Use Claude Adapter with 9Router Anthropic Endpoint

If you want to keep using "Claude Local" adapter but route through 9Router:

1. **Configure 9Router Anthropic provider** in 9Router dashboard
2. **Set environment variables** in `/etc/paperclip/.env`:
   ```bash
   ANTHROPIC_API_KEY=9router-local
   ANTHROPIC_BASE_URL=http://127.0.0.1:20128
   ```
3. **Restart Paperclip**:
   ```bash
   systemctl restart paperclip
   ```

**Note:** This requires 9Router to have Anthropic provider configured. Most 9Router setups only have OpenAI-compatible endpoints, so using Codex/OpenCode adapter is simpler.

## Troubleshooting

### Error: "Not logged in · Please run /login"
**Cause:** Agent is using Claude Local adapter without authentication

**Solution:** Change adapter to Codex Local or OpenCode Local (see Step 2 above)

### Error: "No active credentials for provider: anthropic"
**Cause:** 9Router doesn't have Anthropic provider configured

**Solution:** Use Codex Local adapter instead, which uses OpenAI-compatible endpoint

### Agent not responding
**Check:**
1. 9Router is running: `curl http://127.0.0.1:20128/v1/models`
2. Paperclip logs: `journalctl -u paperclip -f`
3. Environment variables in `/etc/paperclip/.env`:
   ```bash
   OPENAI_BASE_URL=http://127.0.0.1:20128/v1
   OPENAI_API_KEY=9router-local
   ```

### Too many models in 9Router
If 9Router shows too many models and you want to limit them:

1. **In Paperclip UI:** Just select the models you want to use for each agent
2. **In 9Router:** Configure model filtering in 9Router dashboard settings
3. **Recommended models for Paperclip:**
   - For coding: `gh/gpt-5.3-codex`, `cx/gpt-5.4`
   - For general tasks: `gh/claude-opus-4.6`, `cu/claude-4.6-opus-max`
   - For budget: `free`, `gh/gpt-4o-mini`

## Model Selection Guide

### By Use Case

**Coding & Development:**
- `gh/gpt-5.3-codex` - Best for code generation
- `cx/gpt-5.4` - Latest Codex tier
- `gh/gpt-5.1-codex-max` - Maximum context

**General AI Assistant:**
- `gh/claude-opus-4.6` - Best reasoning
- `cu/claude-4.6-opus-max` - Maximum capability
- `gh/claude-sonnet-4.6` - Balanced performance

**Budget/Free:**
- `free` - Basic free tier
- `gh/gpt-4o-mini` - Fast and cheap
- `gh/claude-haiku-4.5` - Fast Claude

### By Provider Prefix

- `gh/` - GitHub tier (free/paid)
- `cu/` - Cursor tier
- `cx/` - Codex tier
- `cc/` - Claude Code tier
- `kc/` - Kimi/other providers
- `kr/` - Korean providers
- No prefix - Direct/combo models

## Environment Variables Reference

```bash
# OpenAI-compatible endpoint (used by Codex Local, OpenCode Local)
OPENAI_BASE_URL=http://127.0.0.1:20128/v1
OPENAI_API_KEY=9router-local

# Anthropic endpoint (used by Claude Local adapter)
ANTHROPIC_BASE_URL=http://127.0.0.1:20128
ANTHROPIC_API_KEY=9router-local

# 9Router configuration
NINEROUTER_PORT=20128
NINEROUTER_BIND_HOST=127.0.0.1
```

After changing environment variables, restart Paperclip:
```bash
systemctl restart paperclip
```
