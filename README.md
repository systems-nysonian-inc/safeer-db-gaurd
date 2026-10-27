# Nysonian Claude Code guardrails

A Claude Code plugin marketplace with one plugin, **`db-write-guard`**. It stops AI-driven database and API writes, and stops Claude reading secret files.

| What Claude tries | What happens |
|---|---|
| `SELECT`, `find()`, `GET` requests, normal coding | Nothing. Works as usual |
| `INSERT`, `UPDATE`, `DELETE FROM`, `ALTER`, `GRANT`, Mongo `updateOne`/`insertMany`/…, `curl -X POST/PUT/PATCH/DELETE`, MCP tools named `*create*`, `*update*`, `*delete*`, `*mutation*`, `*send*`… | The user sees **"COMPANY POLICY: AI tools must not WRITE to databases… Only click Yes if you are certain and have approval."** and must approve |
| `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE`, `deleteMany`, `FLUSHALL` | **Blocked.** No override |
| Reading `.env`, `.env.*`, `*.pem`, `*.key`, credentials, `~/.ssh`, `~/.aws`, `.pgpass`, or dumping env vars (`printenv`, `Get-ChildItem env:`) | **Blocked.** `.env.example` / `.env.sample` / `.env.template` stay readable |

It covers Claude Code in the terminal, VS Code and JetBrains extensions, and the Claude Desktop **Code** tab. It does **not** cover claude.ai chat, Claude Desktop chat, or Cowork. Use the admin-console connector permissions and Desktop policies for those.

## Roll it out to the whole team (Owner or Primary Owner)

1. **Give everyone read access to this repo.** It is private, and each person's Claude Code clones it with their own git credentials. Either add the team to the repo with Read access, or make the repo public (it contains no secrets).
2. Open **claude.ai → Organization settings → Claude Code → Managed settings**.
3. Paste the contents of [`admin/managed-settings.json`](admin/managed-settings.json) and save. If managed settings already exist there, merge the keys instead of replacing them.
4. Each teammate restarts Claude Code. On first start they see a one-time security prompt to accept the company policy. After that the plugin installs and stays on; users cannot disable it.

What the admin settings do:

- `extraKnownMarketplaces` + `enabledPlugins`: install `db-write-guard` for everyone and lock it on.
- `strictKnownMarketplaces`: only this repo and Anthropic's official marketplace can supply plugins, so nobody can install an unvetted plugin that weakens the guard.
- `permissions.deny`: a second, built-in layer that stops Claude reading or editing secret files.
- `disableBypassPermissionsMode`: nobody can run Claude Code with all permission prompts switched off.

## Check it works

On a teammate's machine:

- Run `/plugin` in Claude Code. `db-write-guard@nysonian` should be listed as enabled.
- Run `/status`. **Setting sources** should include the managed (remote) settings.
- Ask Claude to read `.env`. It should be refused with the company-policy message.

## Test the hook locally

```bash
bash tests/run-tests.sh
```

Runs the guard against 32 sample tool calls (reads, secret reads, destructive commands, writes) and prints `passed=32 failed=0`.

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
- **False positives.** Text that merely contains a write keyword, such as `echo "UPDATE x SET y"` or a commit message with `GRANT `, also triggers the warning. Clicking Yes lets it through.
