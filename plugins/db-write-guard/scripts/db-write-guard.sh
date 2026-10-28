#!/usr/bin/env bash
# PreToolUse / BeforeTool hook: stops AI-driven database/API WRITES and secret reads.
# - Reading .env / keys / credential files      -> deny  (blocked, no override)
# - Destructive keywords (DROP, TRUNCATE, ...)  -> deny  (blocked, no override)
# - Normal writes (INSERT, UPDATE, POST, ...)   -> ask   (user sees policy warning, must click Yes)
# - Everything else                             -> no decision (normal permission flow)
#
# Usage: db-write-guard.sh [--format claude|codex|gemini|agy]   (default: claude)
# Reads the tool call JSON on stdin. Needs only bash + grep (Git Bash on Windows).
# Codex and Gemini CLI cannot ask the user from a hook, so "ask" becomes "deny" there.

format=claude
[ "$1" = "--format" ] && format="$2"

input="$(cat)"

# Tool name: "tool_name" (Claude Code, Codex, Gemini CLI) or toolCall "name" (Antigravity).
tool="$(printf '%s' "$input" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')"
[ -z "$tool" ] && tool="$(printf '%s' "$input" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')"

decide() {
  # $1 = deny|ask, $2 = message shown to the user and the AI
  decision="$1"; reason="$2"
  case "$format" in
    codex|gemini)
      if [ "$decision" = ask ]; then
        reason="$reason This tool cannot ask for approval, so it is blocked. If the change is approved, run it yourself."
      fi
      ;;
  esac
  case "$format" in
    gemini) printf '{"decision":"deny","reason":"%s"}\n' "$reason" ;;
    agy)
      [ "$decision" = ask ] && decision=force_ask
      printf '{"decision":"%s","reason":"%s"}\n' "$decision" "$reason"
      ;;
    codex) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason" ;;
    *) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$decision" "$reason" ;;
  esac
  exit 0
}

has() { printf '%s' "$input" | grep -qiE "$1"; }
tool_is() { printf '%s' "$tool" | grep -qiE "^($1)$"; }

# File-reading tools across Claude Code, Gemini CLI and Antigravity.
read_tools='Read|Grep|read_file|read_many_files|search_file_content|grep_search|view_file|glob'

# Secret files: .env, .env.production, *.pem, *.key, credentials, ~/.aws, ~/.ssh, .pgpass.
# Templates such as .env.example / .env.sample / .env.template stay readable.
secret_path='(^|[\\/" =])\.env(\.[a-z0-9_-]+)?([^a-z0-9_.-]|$)|\.(pem|key|pfx|p12)\b|credentials(\.json)?\b|[\\/]\.aws[\\/]|[\\/]\.ssh[\\/]|\.pgpass|\.my\.cnf'
secret_template='\.env\.(example|sample|template|dist)'
secret_reader='\b(cat|type|less|more|head|tail|gc|get-content|source|grep|findstr|sed|awk|strings)\b'
if has "$secret_path" && ! has "$secret_template" && { tool_is "$read_tools" || has "$secret_reader"; }; then
  decide deny "COMPANY POLICY: AI tools must not read secret files (.env, keys, credentials). Use .env.example for structure, or ask a teammate for the value you need."
fi
if has '\b(printenv|get-childitem[[:space:]]+env:|gci[[:space:]]+env:)\b|"(command|CommandLine)"[[:space:]]*:[[:space:]]*"(env|set)"'; then
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

# HTTP writes against APIs (curl / Invoke-RestMethod).
if has '(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|--request[[:space:]]+(POST|PUT|PATCH|DELETE)|-Method[[:space:]]+(Post|Put|Patch|Delete))'; then
  decide ask "COMPANY POLICY: this looks like a WRITE to an external API or system. AI tools should be read-only. Click Yes only if this change is approved."
fi
# MCP tools named like create/update/delete (mcp__server__tool, or mcp_server_tool in Gemini CLI).
if tool_is 'mcp_.*(create|update|delete|insert|write|mutation|send|remove|upsert).*'; then
  decide ask "COMPANY POLICY: this looks like a WRITE to an external API or system. AI tools should be read-only. Click Yes only if this change is approved."
fi

exit 0
