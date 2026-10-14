---
name: setup-mcp
description: Set up and troubleshoot the Sentinel MCP server connection. Use when MCP tools fail, sentinel-mcp won't connect, or on a fresh machine.
---

# Setup / Troubleshoot Sentinel MCP

Run this skill whenever the Sentinel MCP server fails to connect or needs to be set up on a new machine.

This workflow supports Claude Code and Codex:
- Claude Code normally uses the project `.mcp.json`.
- Codex uses `%USERPROFILE%\.codex\config.toml` and can be configured with `codex mcp add`.

## Step-by-step procedure

### 1. Pick the correct MCP binary

For normal installed Sentinel workspaces, use the distribution MCP server installed next to Sentinel:

```text
C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe
```

Only use the repo build when explicitly testing repo or MCP server development:

```text
<repo_root>\mcp-server-rs\target\release\sentinel-mcp.exe
```

Find the repo root when using the repo build:

```powershell
git rev-parse --show-toplevel
```

### 2. Check the binary exists

For the distribution install:

```powershell
Test-Path 'C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe'
```

For the repo build:

```powershell
Test-Path '<repo_root>\mcp-server-rs\target\release\sentinel-mcp.exe'
```

If the repo build is missing, build it:

```powershell
Set-Location '<repo_root>\mcp-server-rs'
cargo build --release
```

Or use the batch file:

```powershell
& '<repo_root>\build_mcp.bat'
```

### 3. Test the binary starts and speaks MCP

Use the binary path selected in step 1:

```powershell
$mcpExe = 'C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe'
$request = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
$request | & $mcpExe
```

You should see a JSON response with `serverInfo`. If the command exits without a JSON-RPC response, check stderr and confirm the path points at `sentinel-mcp.exe`.

### 4. Configure the active agent client

Use the config format for the client you are currently running:

- Claude Code: write or repair the project `.mcp.json`.
- Codex: use `codex mcp add` or update `%USERPROFILE%\.codex\config.toml`.

#### Claude Code: write `.mcp.json`

Use Python's `json.dump()` to write this file. Shell heredocs and echo commands can corrupt Windows backslashes.

```python
import json
import os

repo_root = r"<repo_root>"
mcp_exe = r"C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe"

# Only when explicitly testing repo or MCP development:
# mcp_exe = os.path.join(repo_root, "mcp-server-rs", "target", "release", "sentinel-mcp.exe")

config = {
    "mcpServers": {
        "sentinel-mcp": {
            "type": "stdio",
            "command": mcp_exe,
            "args": []
        }
    }
}

out_path = os.path.join(repo_root, ".mcp.json")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
```

#### Codex: add the MCP server

Prefer the Codex CLI because it edits `%USERPROFILE%\.codex\config.toml` using Codex's own config format:

```powershell
codex mcp add sentinel-mcp -- "C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe"
```

For repo development:

```powershell
codex mcp remove sentinel-mcp
codex mcp add sentinel-mcp -- "<repo_root>\mcp-server-rs\target\release\sentinel-mcp.exe"
```

If editing TOML manually, preserve the rest of the file and ensure this block exists:

```toml
[mcp_servers.sentinel-mcp]
command = 'C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe'
```

### 5. Verify the config

For Claude Code, verify the project JSON:

```python
import json

with open(r"<repo_root>\.mcp.json", encoding="utf-8") as f:
    data = json.load(f)

print(json.dumps(data, indent=2))
```

For Codex, verify the registered MCP server:

```powershell
codex mcp get sentinel-mcp
codex mcp list
```

### 6. Tell the user to reconnect or restart

After writing the config, tell the user the client-specific next step:

- Claude Code: `Config written. Run /mcp to reconnect, or restart Claude Code if it still fails.`
- Codex: `Config written. Restart Codex so the MCP server list is reloaded.`

## Common failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Failed to reconnect" | `.mcp.json` has invalid JSON | Rewrite with `json.dump()` |
| "Failed to reconnect" | `.mcp.json` points to the wrong path | Rewrite with the detected path |
| "Failed to reconnect" | Binary is missing | Run `cargo build --release` in `mcp-server-rs\` |
| Server starts but tools do not appear | `/mcp` reconnect cached old state | Restart Claude Code |
| Codex tools do not appear | Codex has not reloaded `%USERPROFILE%\.codex\config.toml` | Restart Codex |
| Codex has the wrong MCP path | Old `[mcp_servers.sentinel-mcp]` entry | Run `codex mcp remove sentinel-mcp`, then `codex mcp add sentinel-mcp -- "<path>"` |
| Tools appear but all fail | Sentinel is not running | Launch Sentinel first |
| `sentinel_state` works but `sentinel_pipeline` fails | Automation is disabled in the build | Rebuild with `-DENABLE_AUTOMATION=ON` |

## Config file locations and precedence

Claude Code checks these in order:
1. `<repo_root>\.mcp.json` project config
2. `%USERPROFILE%\.claude\settings.json` global config
3. `%USERPROFILE%\.claude\projects\*\settings.local.json` project settings

Codex reads MCP servers from:
1. `%USERPROFILE%\.codex\config.toml` under `[mcp_servers.<name>]`
2. Temporary `codex -c ...` command-line overrides for that session

Codex reloads MCP server registrations at session start. Restart the Codex session after changing MCP servers.

## Dev vs Distribution

- Distribution default: `C:\Program Files\OODLabs\Sentinel\sentinel-mcp.exe`
- Repo development: `mcp-server-rs\target\release\sentinel-mcp.exe`
- The MCP server is a standalone binary. Python, venv, and pip are unnecessary.
