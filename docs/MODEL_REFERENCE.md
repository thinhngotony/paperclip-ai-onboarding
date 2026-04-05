# 9Router Model Reference for Paperclip

## Quick Reference: Correct Model IDs

### Claude Models

**Haiku (Fast, Budget):**
- `gh/claude-haiku-4.5` ✅ (GitHub tier)
- `cc/claude-haiku-4-5-20251001` ✅ (Claude Code tier)
- `cu/claude-4.5-haiku` ✅ (Cursor tier)
- `kr/claude-haiku-4.5` ✅ (Korean tier)
- ❌ `claude-haiku-4-6` (DOES NOT EXIST)

**Sonnet (Balanced):**
- `gh/claude-sonnet-4.6` ✅ (Latest, GitHub tier)
- `gh/claude-sonnet-4.5` ✅ (GitHub tier)
- `cc/claude-sonnet-4-6` ✅ (Claude Code tier)
- `cu/claude-4.5-sonnet` ✅ (Cursor tier)

**Opus (Most Capable):**
- `gh/claude-opus-4.6` ✅ (Latest, GitHub tier)
- `cc/claude-opus-4-6` ✅ (Claude Code tier)
- `cu/claude-4.6-opus-max` ✅ (Cursor tier, maximum capability)
- `gh/claude-opus-4.5` ✅ (GitHub tier)

### GPT Models

**GPT-4 Series:**
- `gh/gpt-4o` ✅ (GitHub tier)
- `gh/gpt-4o-mini` ✅ (Fast, budget)
- `gh/gpt-4.1` ✅ (GitHub tier)

**GPT-5 Series (Coding):**
- `cx/gpt-5.4` ✅ (Latest, Codex tier)
- `gh/gpt-5.3-codex` ✅ (GitHub tier)
- `cu/gpt-5.3-codex` ✅ (Cursor tier)
- `cx/gpt-5.3-codex` ✅ (Codex tier)
- `gh/gpt-5.2-codex` ✅ (GitHub tier)
- `gh/gpt-5.1-codex-max` ✅ (Maximum context)

**GPT-5 General:**
- `cu/gpt-5.2` ✅ (Cursor tier)
- `cx/gpt-5.2` ✅ (Codex tier)
- `gh/gpt-5.2` ✅ (GitHub tier)

### Other Models

**Free/Budget:**
- `free` ✅ (Basic free tier)
- `super` ✅ (Combo model)

**Gemini:**
- `gh/gemini-2.5-pro` ✅
- `cu/gemini-3-flash-preview` ✅

**DeepSeek:**
- `kc/deepseek/deepseek-chat` ✅
- `kc/deepseek/deepseek-reasoner` ✅

## Provider Prefixes Explained

- `gh/` - GitHub tier (often free or included with GitHub Copilot)
- `cu/` - Cursor tier (requires Cursor subscription)
- `cx/` - Codex tier (premium coding models)
- `cc/` - Claude Code tier
- `kc/` - Kimi/other cloud providers
- `kr/` - Korean providers
- No prefix - Direct/combo models (e.g., `free`, `super`, `claude`)

## Common Mistakes

### ❌ Wrong Model IDs
```
claude-haiku-4-6          → Doesn't exist
claude-opus-4-6           → Missing prefix
gpt-5.3-codex             → Missing prefix
claude-sonnet-4.6         → Missing prefix
```

### ✅ Correct Model IDs
```
gh/claude-haiku-4.5       → Correct
gh/claude-opus-4.6        → Correct
gh/gpt-5.3-codex          → Correct
gh/claude-sonnet-4.6      → Correct
```

## How to List All Available Models

```bash
# List all models with IDs
curl -s http://127.0.0.1:20128/v1/models | python3 -m json.tool

# List only model IDs
curl -s http://127.0.0.1:20128/v1/models | python3 -c "import sys,json; print('\n'.join([m['id'] for m in json.load(sys.stdin)['data']]))"

# List Claude models only
curl -s http://127.0.0.1:20128/v1/models | python3 -c "import sys,json; print('\n'.join([m['id'] for m in json.load(sys.stdin)['data'] if 'claude' in m['id'].lower()]))"

# List GPT models only
curl -s http://127.0.0.1:20128/v1/models | python3 -c "import sys,json; print('\n'.join([m['id'] for m in json.load(sys.stdin)['data'] if 'gpt' in m['id'].lower()]))"

# Count total models
curl -s http://127.0.0.1:20128/v1/models | python3 -c "import sys,json; print(f\"Total models: {len(json.load(sys.stdin)['data'])}\")"
```

## Recommended Models by Use Case

### For Coding Tasks
1. `cx/gpt-5.4` - Latest Codex tier (best for code)
2. `gh/gpt-5.3-codex` - GitHub tier (good balance)
3. `cu/gpt-5.3-codex` - Cursor tier (alternative)

### For General AI Assistant
1. `cu/claude-4.6-opus-max` - Maximum capability
2. `gh/claude-opus-4.6` - Latest Opus
3. `gh/claude-sonnet-4.6` - Balanced performance

### For Budget/Free Usage
1. `free` - Basic free tier
2. `gh/gpt-4o-mini` - Fast and cheap
3. `gh/claude-haiku-4.5` - Fast Claude

### For Maximum Context
1. `gh/gpt-5.1-codex-max` - Maximum context for coding
2. `cu/claude-4.6-opus-max` - Maximum Claude capability

## Updating Model in Paperclip

1. Open Paperclip UI
2. Go to **Settings** → **Agents**
3. Select your agent
4. In the **Model** field, enter the exact model ID from the list above
5. Save changes
6. Test the agent

## Troubleshooting Model Issues

### Error: "There's an issue with the selected model"

**Check:**
1. Model ID is exactly as shown in 9Router (case-sensitive)
2. Model ID includes provider prefix (e.g., `gh/`, `cu/`)
3. Model exists in your 9Router instance

**Fix:**
```bash
# List available models
curl -s http://127.0.0.1:20128/v1/models | python3 -c "import sys,json; print('\n'.join([m['id'] for m in json.load(sys.stdin)['data']]))"

# Copy exact model ID and paste into Paperclip
```

### Model works in curl but not in Paperclip

**Check:**
1. Adapter is set to "Codex Local" or "OpenCode Local" (not "Claude Local")
2. `OPENAI_BASE_URL` in `/etc/paperclip/.env` is `http://127.0.0.1:20128/v1`
3. Restart Paperclip after changing .env: `systemctl restart paperclip`

## Model Naming Convention

9Router uses this format: `[provider]/[model-name]`

Examples:
- `gh/claude-opus-4.6` = GitHub provider + Claude Opus 4.6
- `cu/gpt-5.3-codex` = Cursor provider + GPT-5.3 Codex
- `cx/gpt-5.4` = Codex provider + GPT-5.4
- `free` = No provider prefix (direct model)

Always use the exact ID as shown in `/v1/models` endpoint.
