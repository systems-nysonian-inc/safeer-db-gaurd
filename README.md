# Nysonian AI guardrails

**`db-write-guard`** stops AI coding agents from writing to databases and APIs, and from reading secret files. One guard script works in four tools:

| Tool | How it's installed | Writes (`UPDATE`, `POST`…) | Destructive (`DROP`…) and secret reads |
|---|---|---|---|
| Claude Code | Plugin, pushed from the claude.ai admin console | Warns, user clicks Yes to continue | Blocked |
| Antigravity CLI (`agy`) | `install\install-windows.ps1` | Warns, user clicks Yes to continue | Blocked |
| Codex CLI | `install\install-windows.ps1`, or ChatGPT admin console | **Blocked** (Codex hooks can't ask yet) | Blocked |
| Gemini CLI | `install\install-windows.ps1` | **Blocked** (Gemini hooks can't ask) | Blocked |

The rules are the same everywhere:

| What Claude tries | What happens |
|---|---|
| `SELECT`, `find()`, `GET` requests, normal coding | Nothing. Works as usual |
| `INSERT`, `UPDATE`, `DELETE FROM`, `ALTER`, `GRANT`, Mongo `updateOne`/`insertMany`/…, `curl -X POST/PUT/PATCH/DELETE`, MCP tools named `*create*`, `*update*`, `*delete*`, `*mutation*`, `*send*`… | The user sees **"COMPANY POLICY: AI tools must not WRITE to databases… Only click Yes if you are certain and have approval."** and must approve |
| `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE`, `deleteMany`, `FLUSHALL` | **Blocked.** No override |
| Reading `.env`, `.env.*`, `*.pem`, `*.key`, credentials, `~/.ssh`, `~/.aws`, `.pgpass`, or dumping env vars (`printenv`, `Get-ChildItem env:`) | **Blocked.** `.env.example` / `.env.sample` / `.env.template` stay readable |

It does **not** cover chat apps (claude.ai, Claude Desktop chat, ChatGPT, Gemini web) or Claude Cowork. Use connector permissions and Desktop policies for those.

## Claude Code: roll it out to the whole team (Owner or Primary Owner)

Covers Claude Code in the terminal, VS Code and JetBrains extensions, and the Claude Desktop **Code** tab.

1. **Give everyone read access to this repo.** It is private, and each person's Claude Code clones it with their own git credentials. Either add the team to the repo with Read access, or make the repo public (it contains no secrets).
2. Open **claude.ai → Organization settings → Claude Code → Managed settings**.
3. Paste the contents of [`admin/managed-settings.json`](admin/managed-settings.json) and save. If managed settings already exist there, merge the keys instead of replacing them.
4. Each teammate restarts Claude Code. On first start they see a one-time security prompt to accept the company policy. After that the plugin installs and stays on; users cannot disable it.

What the admin settings do:

- `extraKnownMarketplaces` + `enabledPlugins`: install `db-write-guard` for everyone and lock it on.
- `strictKnownMarketplaces`: only this repo and Anthropic's official marketplace can supply plugins, so nobody can install an unvetted plugin that weakens the guard.
- `permissions.deny`: a second, built-in layer that stops Claude reading or editing secret files. Deny rules apply in every permission mode, including bypass mode.

Bypass mode (`--dangerously-skip-permissions`) is left available. To turn it off for everyone, add `"disableBypassPermissionsMode": "disable"` inside `permissions`.

## Codex, Gemini CLI and agy: install on each Windows PC

Those tools have no Claude-style admin console that can deliver files, so the guard is installed on each PC. It needs Git for Windows (for `bash`).

From a checkout of this repo, in PowerShell:

```powershell
# For yourself (no admin rights needed; you can remove it again)
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1

# For every user of the PC, locked for Codex and Gemini CLI (run PowerShell as administrator)
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Scope Machine

# Remove it
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Uninstall
```

Add `-Tools codex,agy` to set up only some tools. The script backs up each file it changes (`*.nysonian-db-write-guard.bak`) and leaves your own hooks and settings in place.

| Tool | `-Scope User` writes to | `-Scope Machine` writes to |
|---|---|---|
| Codex | `~\.codex\hooks.json` (each user approves it once in Codex with `/hooks`) | `%ProgramData%\OpenAI\Codex\requirements.toml` (managed; users can't turn it off, no approval step) |
| Gemini CLI | `~\.gemini\settings.json` | `C:\ProgramData\gemini-cli\settings.json` (system settings; override user settings) |
| agy | `~\.gemini\config\hooks.json` | Same, current user only (agy has no system-wide location) |

The guard itself goes to `~\.nysonian-guard\` (User) or `C:\ProgramData\NysonianGuard\` (Machine).

**Codex from the ChatGPT admin console:** if you have ChatGPT Business or Enterprise, you can instead paste [`admin/codex-requirements.toml`](admin/codex-requirements.toml) into **Admin Console → Agent security → Edit as TOML**. The guard files must still be on each PC, so run the installer with `-Scope Machine` first.

**Locking it down:** `-Scope Machine` only holds on PCs where the user isn't a local administrator; an admin can edit any file. agy settings always live in the user's own folder, so a user can remove the agy hook.

## Check it works

On a teammate's machine:

- Run `/plugin` in Claude Code. `db-write-guard@nysonian` should be listed as enabled.
- Run `/status`. **Setting sources** should include the managed (remote) settings.
- Ask Claude to read `.env`. It should be refused with the company-policy message.

## Test the hook locally

```bash
bash tests/run-tests.sh
```

Runs the guard against 49 sample tool calls in all four tools' input formats (reads, secret reads, destructive commands, writes) and prints `passed=49 failed=0`.

To try the plugin in a real session without installing it:

```bash
claude --plugin-dir ./plugins/db-write-guard
```

## Change the rules

Edit [`plugins/db-write-guard/scripts/db-write-guard.sh`](plugins/db-write-guard/scripts/db-write-guard.sh), add a case to `tests/run-tests.sh`, run the tests, bump `version` in `plugins/db-write-guard/.claude-plugin/plugin.json`, and push. Teammates pick up the new version through auto-update.

## Limits

- **Keyword matching.** It catches normal write statements, but a deliberately disguised command (for example, SQL built from pieces at runtime) can slip past. Treat it as a guardrail, not a security boundary.
- **Non-interactive runs.** In `claude -p`, scripts and CI, nobody can click Yes, so every warning acts as a block.
- **Bash required.** The hook runs with `bash`, which Claude Code on Windows already needs (Git for Windows).
- **Folder names with spaces.** agy can't run a hook from a path with spaces. The installer uses the Windows short path when needed and warns if the drive has short paths turned off.
- **Re-run after updates.** Claude Code picks up guard changes automatically. For Codex, Gemini CLI and agy, pull the repo and run the installer again.
- **False positives.** Text that merely contains a write keyword, such as `echo "UPDATE x SET y"` or a commit message with `GRANT `, also triggers the warning. Clicking Yes lets it through.
