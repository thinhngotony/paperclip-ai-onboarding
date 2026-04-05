# How to Use ANY Model from 9Router in Paperclip

## Quick Fix for Your Current Issue

Your agent is configured with `claude-haiku-4-6` which doesn't exist.

**Replace it with one of these:**
- `gh/claude-haiku-4.5` (closest match)
- `cc/claude-haiku-4-5-20251001` (alternative)
- `cu/claude-4.5-haiku` (alternative)
- `kr/claude-haiku-4.5` (alternative)

## Step-by-Step Instructions

### 1. Access Paperclip UI
**IMPORTANT: Port is 3101, not 3100**

Open in browser:
```
http://42.96.13.174:3101
```

### 2. Navigate to Agent Settings
1. Log in to Paperclip
2. Click **Settings** (gear icon) or **Agents** in sidebar
3. Find your agent (the one showing errors)
4. Click to edit

### 3. Change Adapter (REQUIRED)
Change **Adapter** to:
- **Codex Local** ✅ (recommended)
- OR **OpenCode Local** ✅

**DO NOT use "Claude Local"** - it has model prefix issues with 9Router

### 4. Choose ANY Model from the List

You have **83 models** available. Pick ANY model ID from `docs/ALL_AVAILABLE_MODELS.txt`

**Copy the EXACT model ID** (with prefix, case-sensitive):

#### Popular Choices:

**Best for Coding:**
```
cx/gpt-5.4
gh/gpt-5.3-codex
cu/gpt-5.3-codex
gh/grok-code-fast-1
```

**Best Quality:**
```
gh/claude-opus-4.6
cu/claude-4.6-opus-max
opus-4.5
kc/anthropic/claude-opus-4-20250514
```

**Balanced:**
```
gh/claude-sonnet-4.6
cu/claude-4.5-sonnet
gh/gpt-4o
```

**Fast/Budget:**
```
free
gh/gpt-4o-mini
gh/claude-haiku-4.5
super
```

**Reasoning:**
```
kc/deepseek/deepseek-reasoner
cu/claude-4.5-opus-high-thinking
```

### 5. Save and Test
1. Click **Save**
2. Create a task or chat with the agent
3. Should work with ANY model you selected!

## Command to List All Models

Run this anytime to see all available models:
```bash
curl -s http://127.0.0.1:20128/v1/models | python3 -c "import sys,json; print('\n'.join([m['id'] for m in json.load(sys.stdin)['data']]))"
```

## Why Your Current Model Doesn't Work

You configured: `claude-haiku-4-6`
9Router has: `gh/claude-haiku-4.5`, `cc/claude-haiku-4-5-20251001`, etc.

**The model ID must match EXACTLY** (including prefix and version number).

## Model Naming Convention

9Router uses: `[provider]/[model-name]`

Examples:
- `gh/claude-opus-4.6` = GitHub provider + Claude Opus 4.6
- `cu/gpt-5.3-codex` = Cursor provider + GPT-5.3 Codex
- `free` = No prefix (direct model)

## No Limits!

You can use **ANY of the 83 models** in Paperclip:
- ✅ All Claude models (Haiku, Sonnet, Opus)
- ✅ All GPT models (3.5, 4, 5, 5.1, 5.2, 5.3, 5.4)
- ✅ Gemini models
- ✅ DeepSeek models
- ✅ Grok models
- ✅ Custom models (nvidia, kimi, etc.)

Just use the **Codex Local** adapter and paste the exact model ID.

## Troubleshooting

### Error: "model doesn't exist"
- Check you're using **Codex Local** adapter (not Claude Local)
- Verify model ID is EXACT (copy from list)
- Model IDs are case-sensitive

### Error: "Claude hello probe failed"
- Ignore this - it's just a startup test
- Your agent will work fine with Codex Local adapter

### Can't access UI
- Use port **3101** not 3100
- Check firewall allows port 3101
- Or use SSH tunnel: `ssh -L 3101:127.0.0.1:3101 user@42.96.13.174`

## Summary

1. ✅ You have 83 models available
2. ✅ Use Codex Local adapter
3. ✅ Copy exact model ID from list
4. ✅ No restrictions - use ANY model!

See `docs/ALL_AVAILABLE_MODELS.txt` for complete list.
