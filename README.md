# Nysonian AI guardrails

**`db-write-guard`** stops AI coding agents from writing to databases and APIs, and from reading secret files. One guard script works in Claude Code, Codex CLI, Gemini CLI and Antigravity CLI (`agy`).

## What it does

| What the AI tries | What happens |
|---|---|
| `SELECT`, `find()`, `GET` requests, normal coding | Nothing. Works as usual |
| `INSERT`, `UPDATE`, `DELETE FROM`, `ALTER`, `GRANT`, Mongo `updateOne`/`insertMany`/…, `curl -X POST/PUT/PATCH/DELETE`, MCP tools named `*create*`, `*update*`, `*delete*`, `*mutation*`, `*send*`… | Warning: **"COMPANY POLICY: AI tools must not WRITE to databases…"**. You must click Yes to continue (Claude Code, agy). Codex and Gemini CLI can't ask, so there it is blocked |
| `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE`, `deleteMany`, `FLUSHALL` | **Blocked** |
| Reading `.env`, `.env.*`, `*.pem`, `*.key`, credentials, `~/.ssh`, `~/.aws`, `.pgpass`, or dumping env vars (`printenv`, `Get-ChildItem env:`) | **Blocked**. `.env.example` / `.env.sample` / `.env.template` stay readable |

## If something is blocked

- **A write you really need:** run it yourself, through the normal change process.
- **A secret value:** look at `.env.example` for the structure, or ask a teammate. Don't paste secrets into AI chats.
- **A false alarm:** for example, text that happens to contain `UPDATE x SET`. Click Yes where offered, or run the command yourself.

## Setup

**Claude Code** is set up for you by the company. Nothing to do.

**Codex, Gemini CLI and agy:** IT installs these for you. To set it up yourself, install Git for Windows and run this in PowerShell from a checkout of this repo:

```powershell
# Install for your user
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1

# Only some tools
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Tools codex,agy

# Remove it
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Uninstall
```

Codex asks you to trust the hook once: open Codex, run `/hooks`, and trust `nysonian-db-write-guard`. Restart any open sessions after installing.

## Check it works

- Claude Code: `/plugin` lists `db-write-guard@nysonian` as enabled.
- In any of the tools, ask the AI to read a `.env` file. It should be refused with the company-policy message.

## Change the rules

Edit [`plugins/db-write-guard/scripts/db-write-guard.sh`](plugins/db-write-guard/scripts/db-write-guard.sh), add a case to [`tests/run-tests.sh`](tests/run-tests.sh), and run:

```bash
bash tests/run-tests.sh
```

It runs 58 sample tool calls in all four tools' input formats and prints `passed=58 failed=0`. Then bump `version` in `plugins/db-write-guard/.claude-plugin/plugin.json` and open a pull request.

To try the plugin in Claude Code without installing it: `claude --plugin-dir ./plugins/db-write-guard`
