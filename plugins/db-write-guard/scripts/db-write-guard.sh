#!/usr/bin/env bash
# Claude Code PreToolUse hook: stops AI-driven database/API WRITES and secret reads.
# - Reading .env / keys / credential files      -> deny  (blocked, no override)
# - Destructive keywords (DROP, TRUNCATE, ...)  -> deny  (blocked, no override)
# - Normal writes (INSERT, UPDATE, POST, ...)   -> ask   (user sees policy warning, must click Yes)
# - Everything else                             -> no decision (normal permission flow)
# Reads the tool call JSON on stdin. Needs only bash + grep (Git Bash on Windows).

input="$(cat)"

decide() {
  # $1 = deny|ask, $2 = message shown to the user and Claude
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}

has() { printf '%s' "$input" | grep -qiE "$1"; }

# Secret files: .env, .env.production, *.pem, *.key, credentials, ~/.aws, ~/.ssh, .pgpass.
# Templates such as .env.example / .env.sample / .env.template stay readable.
secret_path='(^|[\\/" =])\.env(\.[a-z0-9_-]+)?([^a-z0-9_.-]|$)|\.(pem|key|pfx|p12)\b|credentials(\.json)?\b|[\\/]\.aws[\\/]|[\\/]\.ssh[\\/]|\.pgpass|\.my\.cnf'
secret_template='\.env\.(example|sample|template|dist)'
secret_reader='"tool_name":"(Read|Grep)"|\b(cat|type|less|more|head|tail|gc|get-content|source|grep|findstr|sed|awk|strings)\b'
if has "$secret_path" && ! has "$secret_template" && has "$secret_reader"; then
  decide deny "COMPANY POLICY: AI tools must not read secret files (.env, keys, credentials). Use .env.example for structure, or ask a teammate for the value you need."
fi
if has '\b(printenv|get-childitem[[:space:]]+env:|gci[[:space:]]+env:)\b|"command":"(env|set)"'; then
  decide deny "COMPANY POLICY: AI tools must not dump environment variables; they often hold secrets."
fi

# Destructive: never allowed through AI.
if has '\b(drop[[:space:]]+(table|database|schema|collection|index|view)|truncate([[:space:]]+table)?[[:space:]]+[a-z_."]+|dropDatabase|\.drop\(|deleteMany|flushall|flushdb)\b'; then
  decide deny "COMPANY POLICY: destructive database operations through AI tools are not allowed. Run this yourself through the approved change process."
fi

# SQL / NoSQL writes.
if has '\b(insert[[:space:]]+into|update[[:space:]]+[a-z_."]+[[:space:]]+set|delete[[:space:]]+from|alter[[:space:]]+table|create[[:space:]]+(table|index|user|role|database)|grant[[:space:]]|revoke[[:space:]]|merge[[:space:]]+into|upsert|insertOne|insertMany|updateOne|updateMany|replaceOne|deleteOne|findOneAndUpdate|findOneAndDelete|bulkWrite)\b'; then
  decide ask "COMPANY POLICY: AI tools must not WRITE to databases. Read-only queries are fine. Only click Yes if you are certain and have approval."
fi

# HTTP writes against APIs (curl / Invoke-RestMethod) and MCP tools named like create/update/delete.
if has '(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|--request[[:space:]]+(POST|PUT|PATCH|DELETE)|-Method[[:space:]]+(Post|Put|Patch|Delete)|"tool_name":"mcp__[^"]*(create|update|delete|insert|write|mutation|send|remove|upsert)[^"]*")'; then
  decide ask "COMPANY POLICY: this looks like a WRITE to an external API or system. AI tools should be read-only. Click Yes only if this change is approved."
fi

exit 0
