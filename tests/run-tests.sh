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

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
