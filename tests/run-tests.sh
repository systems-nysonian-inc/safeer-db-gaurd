#!/usr/bin/env bash
# Runs the guard against sample tool calls and checks each decision.
# Usage: bash tests/run-tests.sh
cd "$(dirname "$0")/.."
guard="plugins/db-write-guard/scripts/db-write-guard.sh"
pass=0; fail=0

check() {
  # $1 = expected decision (deny|ask|none), $2 = tool call JSON
  out="$(printf '%s' "$2" | bash "$guard")"
  got="$(printf '%s' "$out" | grep -oE '"permissionDecision":"[a-z]+"' | cut -d'"' -f4)"
  got="${got:-none}"
  if [ "$got" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL expected=$1 got=$got :: $2"; fi
}

# Reads that must pass untouched
check none '{"tool_name":"Bash","tool_input":{"command":"psql $DB -c \"SELECT * FROM orders WHERE id=1\""}}'
check none '{"tool_name":"Bash","tool_input":{"command":"mongosh --eval \"db.orders.find({}).limit(5)\""}}'
check none '{"tool_name":"Bash","tool_input":{"command":"curl https://api.example.com/v1/items"}}'
check none '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
check none '{"tool_name":"Read","tool_input":{"file_path":"D:\\app\\src\\main.py"}}'
check none '{"tool_name":"Read","tool_input":{"file_path":"/app/.env.example"}}'
check none '{"tool_name":"Read","tool_input":{"file_path":"/app/src/environment.ts"}}'
check none '{"tool_name":"mcp__pg__pg_query","tool_input":{"sql":"select count(*) from users"}}'
check none '{"tool_name":"mcp__shopify__list_orders","tool_input":{}}'

# Secret reads: blocked
check deny '{"tool_name":"Read","tool_input":{"file_path":"/app/.env"}}'
check deny '{"tool_name":"Read","tool_input":{"file_path":"D:\\app\\.env.production"}}'
check deny '{"tool_name":"Read","tool_input":{"file_path":"/home/u/.ssh/id_rsa"}}'
check deny '{"tool_name":"Read","tool_input":{"file_path":"/certs/server.pem"}}'
check deny '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
check deny '{"tool_name":"Bash","tool_input":{"command":"cat ./config/.env.local | grep DB"}}'
check deny '{"tool_name":"PowerShell","tool_input":{"command":"Get-Content .env"}}'
check deny '{"tool_name":"Bash","tool_input":{"command":"printenv"}}'
check deny '{"tool_name":"Grep","tool_input":{"pattern":"PASSWORD","path":"/app/.env"}}'

# Destructive: blocked
check deny '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE users\""}}'
check deny '{"tool_name":"Bash","tool_input":{"command":"mysql -e \"truncate table orders\""}}'
check deny '{"tool_name":"Bash","tool_input":{"command":"mongosh --eval \"db.orders.deleteMany({})\""}}'
check deny '{"tool_name":"mcp__pg__pg_query","tool_input":{"sql":"drop schema public cascade"}}'

# Writes: ask with policy message
check ask '{"tool_name":"Bash","tool_input":{"command":"psql $DB -c \"UPDATE orders SET status=1 WHERE id=2\""}}'
check ask '{"tool_name":"Bash","tool_input":{"command":"psql -c \"INSERT INTO logs VALUES (1)\""}}'
check ask '{"tool_name":"Bash","tool_input":{"command":"psql -c \"delete from logs where id=3\""}}'
check ask '{"tool_name":"Bash","tool_input":{"command":"psql -c \"ALTER TABLE users ADD COLUMN x int\""}}'
check ask '{"tool_name":"Bash","tool_input":{"command":"mongosh --eval \"db.orders.updateOne({a:1},{$set:{b:2}})\""}}'
check ask '{"tool_name":"Bash","tool_input":{"command":"curl -X POST https://api.example.com/v1/items -d {}"}}'
check ask '{"tool_name":"PowerShell","tool_input":{"command":"Invoke-RestMethod -Uri https://api.x.com -Method Delete"}}'
check ask '{"tool_name":"mcp__shiphero__shiphero_mutation_execute","tool_input":{}}'
check ask '{"tool_name":"mcp__slack__slack_send_message","tool_input":{}}'
check ask '{"tool_name":"mcp__pg__pg_query","tool_input":{"sql":"update users set role=1"}}'

# Other agents: $1 = format, $2 = expected decision (as that format writes it, or none), $3 = tool call JSON
check_fmt() {
  out="$(printf '%s' "$3" | bash "$guard" --format "$1")"
  got="$(printf '%s' "$out" | grep -oE '"(permissionDecision|decision)":"[a-z_]+"' | cut -d'"' -f4)"
  got="${got:-none}"
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL [$1] expected=$2 got=$got :: $3"; fi
}

# Codex: same input shape as Claude Code; cannot ask, so writes are denied
check_fmt codex none '{"tool_name":"Bash","tool_input":{"command":"psql -c \"select 1\""}}'
check_fmt codex deny '{"tool_name":"Bash","tool_input":{"command":"psql -c \"UPDATE orders SET a=1\""}}'
check_fmt codex deny '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
check_fmt codex deny '{"tool_name":"mcp__shiphero__shiphero_mutation_execute","tool_input":{}}'

# Gemini CLI: run_shell_command / read_file, MCP tools named mcp_<server>_<tool>; cannot ask
check_fmt gemini none '{"tool_name":"run_shell_command","tool_input":{"command":"psql -c \"select * from t\""}}'
check_fmt gemini none '{"tool_name":"read_file","tool_input":{"file_path":"/app/.env.example"}}'
check_fmt gemini deny '{"tool_name":"read_file","tool_input":{"file_path":"/app/.env"}}'
check_fmt gemini deny '{"tool_name": "run_shell_command", "tool_input": {"command": "psql -c \"insert into t values (1)\""}}'
check_fmt gemini deny '{"tool_name":"run_shell_command","tool_input":{"command":"mysql -e \"DROP DATABASE prod\""}}'
check_fmt gemini deny '{"tool_name":"mcp_slack_send_message","tool_input":{}}'

# Antigravity (agy): toolCall.name / toolCall.args.CommandLine; real "ask" via force_ask
check_fmt agy none '{"toolCall":{"name":"run_command","args":{"CommandLine":"git status"}}}'
check_fmt agy none '{"toolCall":{"name":"view_file","args":{"AbsolutePath":"C:/app/src/main.py"}}}'
check_fmt agy deny '{"toolCall":{"name":"view_file","args":{"AbsolutePath":"C:/app/.env"}}}'
check_fmt agy deny '{"toolCall":{"name":"run_command","args":{"CommandLine":"psql -c \"TRUNCATE TABLE orders\""}}}'
check_fmt agy force_ask '{"toolCall": {"name": "run_command", "args": {"CommandLine": "psql -c \"UPDATE users SET role=1\""}}}'
check_fmt agy force_ask '{"toolCall":{"name":"run_command","args":{"CommandLine":"curl -X DELETE https://api.x.com/v1/items/3"}}}'
check_fmt agy deny '{"toolCall":{"name":"run_command","args":{"CommandLine":"set"}}}'

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
