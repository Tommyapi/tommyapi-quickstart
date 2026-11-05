#!/usr/bin/env bash
# Pure-bash tests for install.sh. Runs everything against a fake HOME.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/install.sh"
PASS=0; FAIL=0
PY=""; for c in python3 python; do command -v $c >/dev/null 2>&1 && $c -c 'import json' 2>/dev/null && { PY=$c; break; }; done
[ -n "$PY" ] || { echo "tests need python3/python for JSON assertions"; exit 2; }

ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() { # desc cmd...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
jget() { # file expr(python, d = parsed json)
  "$PY" -c 'import sys,json; d=json.load(open(sys.argv[1],encoding="utf-8")); print(eval(sys.argv[2]))' "$1" "$2"
}
newhome() { H="$(mktemp -d)"; export HOME="$H" SHELL=/bin/bash; }
run() { bash "$SCRIPT" --no-check "$@" 2>&1; }
count_bak() { ls "$1".bak-tommyapi-* 2>/dev/null | wc -l | tr -d ' '; }
FAKE=sk-test-0123456789abcdef

echo "== 1. fresh install"
newhome
out="$(run --key $FAKE)"; rc=$?
check "exit code 0" test $rc -eq 0
check "settings.json base url (no /v1)" test "$(jget $H/.claude/settings.json 'd["env"]["ANTHROPIC_BASE_URL"]')" = "https://tommyapi.com"
check "settings.json token" test "$(jget $H/.claude/settings.json 'd["env"]["ANTHROPIC_AUTH_TOKEN"]')" = "$FAKE"
check "codex model_provider" grep -qx 'model_provider = "tommyapi"' $H/.codex/config.toml
check "codex provider table" grep -qx '\[model_providers.tommyapi\]' $H/.codex/config.toml
check "codex base_url has /v1" grep -qx 'base_url = "https://tommyapi.com/v1"' $H/.codex/config.toml
check "codex wire_api responses" grep -qx 'wire_api = "responses"' $H/.codex/config.toml
check "codex env_key" grep -qx 'env_key = "TOMMYAPI_KEY"' $H/.codex/config.toml
check "bashrc exports TOMMYAPI_KEY" grep -q "export TOMMYAPI_KEY='$FAKE'" $H/.bashrc
check "model_provider precedes first table" test "$(grep -n 'model_provider = ' $H/.codex/config.toml | head -1 | cut -d: -f1)" -lt "$(grep -n '^\[' $H/.codex/config.toml | head -1 | cut -d: -f1)"
check "no backup when files were new" test "$(count_bak $H/.claude/settings.json)" = 0

echo "== 2. idempotent"
before="$(cat $H/.claude/settings.json $H/.codex/config.toml $H/.bashrc | cksum)"
run --key $FAKE >/dev/null; run --key $FAKE >/dev/null
after="$(cat $H/.claude/settings.json $H/.codex/config.toml $H/.bashrc | cksum)"
check "content identical after 2 more runs" test "$before" = "$after"
check "no new backups when nothing changed" test "$(count_bak $H/.claude/settings.json)$(count_bak $H/.codex/config.toml)$(count_bak $H/.bashrc)" = "000"
check "single provider table" test "$(grep -c '^\[model_providers.tommyapi\]' $H/.codex/config.toml)" = 1
check "single export block" test "$(grep -c 'export TOMMYAPI_KEY' $H/.bashrc)" = 1

echo "== 3. preserves existing config, backs up, re-key, endpoint"
newhome
mkdir -p $H/.claude $H/.codex
cat > $H/.claude/settings.json <<'J'
{
  "theme": "dark",
  "permissions": {"allow": ["Bash(ls:*)"]},
  "env": {"FOO": "bar"}
}
J
cat > $H/.codex/config.toml <<'T'
model = "gpt-5"
model_provider = "openai"

[mcp_servers.demo]
command = "demo"
args = ["a", "b"]
T
printf 'alias ll="ls -l"\n' > $H/.bashrc
ORIG_S="$(cat $H/.claude/settings.json)"; ORIG_T="$(cat $H/.codex/config.toml)"; ORIG_R="$(cat $H/.bashrc)"
run --key $FAKE --endpoint cn --model claude-sonnet-4-5 >/dev/null
check "keeps theme" test "$(jget $H/.claude/settings.json 'd["theme"]')" = dark
check "keeps permissions" test "$(jget $H/.claude/settings.json 'd["permissions"]["allow"][0]')" = "Bash(ls:*)"
check "keeps env.FOO" test "$(jget $H/.claude/settings.json 'd["env"]["FOO"]')" = bar
check "cn endpoint" test "$(jget $H/.claude/settings.json 'd["env"]["ANTHROPIC_BASE_URL"]')" = "https://cn.tommyapi.com"
check "model written" test "$(jget $H/.claude/settings.json 'd["env"]["ANTHROPIC_MODEL"]')" = claude-sonnet-4-5
check "toml keeps model" grep -qx 'model = "gpt-5"' $H/.codex/config.toml
check "toml keeps mcp table" grep -qx '\[mcp_servers.demo\]' $H/.codex/config.toml
check "toml keeps args" grep -qx 'args = \["a", "b"\]' $H/.codex/config.toml
check "toml old provider disabled not duplicated" test "$(grep -c '^model_provider' $H/.codex/config.toml)" = 1
check "toml cn base_url" grep -qx 'base_url = "https://cn.tommyapi.com/v1"' $H/.codex/config.toml
check "bashrc keeps alias" grep -q 'alias ll=' $H/.bashrc
check "settings backup exists" test "$(count_bak $H/.claude/settings.json)" = 1
check "toml backup exists" test "$(count_bak $H/.codex/config.toml)" = 1
check "rc backup exists" test "$(count_bak $H/.bashrc)" = 1
check "backup holds original settings" test "$(cat $H/.claude/settings.json.bak-tommyapi-*)" = "$ORIG_S"
sleep 1
run --key sk-test-NEWKEY --endpoint sg >/dev/null
check "re-key updates token" test "$(jget $H/.claude/settings.json 'd["env"]["ANTHROPIC_AUTH_TOKEN"]')" = sk-test-NEWKEY
check "re-key still one table" test "$(grep -c '^\[model_providers.tommyapi\]' $H/.codex/config.toml)" = 1
check "re-key still one export" test "$(grep -c 'export TOMMYAPI_KEY' $H/.bashrc)" = 1
check "sg base url" grep -qx 'base_url = "https://sg.tommyapi.com/v1"' $H/.codex/config.toml

echo "== 4. --uninstall restores"
run --uninstall >/dev/null
check "settings.json back to original (semantically)" test "$(jget $H/.claude/settings.json 'json.dumps(d,sort_keys=True)')" = "$(echo "$ORIG_S" | $PY -c 'import sys,json;print(json.dumps(json.load(sys.stdin),sort_keys=True))')"
check "config.toml byte-identical to original" test "$(cat $H/.codex/config.toml)" = "$ORIG_T"
check "bashrc byte-identical to original" test "$(cat $H/.bashrc)" = "$ORIG_R"
check "backups kept" test "$(count_bak $H/.codex/config.toml)" -ge 1

echo "== 5. uninstall on files we created removes them"
newhome
run --key $FAKE >/dev/null
run --uninstall >/dev/null
check "settings.json removed" test ! -e $H/.claude/settings.json
check "config.toml removed" test ! -e $H/.codex/config.toml
check "bashrc removed" test ! -e $H/.bashrc

echo "== 6. --dry-run writes nothing"
newhome
out="$(run --key $FAKE --dry-run)"
check "no files created" test ! -e $H/.claude -a ! -e $H/.codex -a ! -e $H/.bashrc
check "dry-run says would write" bash -c "echo '$out' | grep -q 'would write'"

echo "== 7. --tools filtering"
newhome
run --key $FAKE --tools claude >/dev/null
check "claude only: settings exists" test -f $H/.claude/settings.json
check "claude only: no codex file" test ! -e $H/.codex/config.toml
newhome
run --key $FAKE --tools codex >/dev/null
check "codex only: config exists" test -f $H/.codex/config.toml
check "codex only: no claude file" test ! -e $H/.claude/settings.json

echo "== 8. input validation"
newhome
check "rejects bad key chars" bash -c "! bash '$SCRIPT' --no-check --key 'sk-a\"b' >/dev/null 2>&1"
check "rejects unknown tool" bash -c "! bash '$SCRIPT' --no-check --key $FAKE --tools foo >/dev/null 2>&1"
check "rejects bad endpoint" bash -c "! bash '$SCRIPT' --no-check --key $FAKE --endpoint mars >/dev/null 2>&1"
echo '{ not json' > /dev/null; mkdir -p $H/.claude; echo '{ not json' > $H/.claude/settings.json
check "refuses to clobber invalid settings.json" bash -c "! bash '$SCRIPT' --no-check --key $FAKE --tools claude >/dev/null 2>&1"
check "invalid settings.json untouched" test "$(cat $H/.claude/settings.json)" = '{ not json'

echo "== 9. real connectivity self-check (free, 401 expected with a fake key)"
newhome
out="$(bash "$SCRIPT" --key $FAKE --tools claude 2>&1)"
echo "$out" | grep 'Self-check'
check "self-check reports a verdict" bash -c "echo '$out' | grep -q 'Self-check'"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
