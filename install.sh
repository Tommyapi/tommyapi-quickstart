#!/usr/bin/env bash
# tommyapi-quickstart: point Claude Code / Codex CLI at TommyAPI with one command.
# https://github.com/Tommyapi/tommyapi-quickstart  (MIT)
# Plain text, auditable. Collects nothing. The only network call is one free
# GET /v1/models self-check at the end (skip with --no-check).
set -euo pipefail

VERSION="0.1.0"
KEY="${TOMMYAPI_KEY:-}"
ENDPOINT="${TOMMYAPI_ENDPOINT:-us}"
TOOLS="${TOMMYAPI_TOOLS:-all}"
MODEL="${TOMMYAPI_MODEL:-}"
DRY=0; UNINSTALL=0; CHECK=1

usage() {
cat <<USAGE
tommyapi-quickstart $VERSION

Usage: install.sh [--key sk-xxx] [--endpoint us|cn|sg] [--tools claude,codex,all]
                  [--model NAME] [--dry-run] [--uninstall] [--no-check]

  --key        TommyAPI key (or env TOMMYAPI_KEY, or you get prompted)
  --endpoint   us = tommyapi.com (default), cn = cn.tommyapi.com, sg = sg.tommyapi.com
  --tools      comma list of: claude, codex, all (default all)
  --model      optional ANTHROPIC_MODEL for Claude Code
  --dry-run    show what would change, write nothing
  --uninstall  remove only the TommyAPI entries (a backup is made first)
  --no-check   skip the final connectivity self-check
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY="${2:-}"; shift 2;;
    --key=*) KEY="${1#*=}"; shift;;
    --endpoint) ENDPOINT="${2:-}"; shift 2;;
    --endpoint=*) ENDPOINT="${1#*=}"; shift;;
    --tools) TOOLS="${2:-}"; shift 2;;
    --tools=*) TOOLS="${1#*=}"; shift;;
    --model) MODEL="${2:-}"; shift 2;;
    --model=*) MODEL="${1#*=}"; shift;;
    --dry-run) DRY=1; shift;;
    --uninstall) UNINSTALL=1; shift;;
    --no-check) CHECK=0; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 64;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "$ENDPOINT" in
  us) HOST="https://tommyapi.com";;
  cn) HOST="https://cn.tommyapi.com";;
  sg) HOST="https://sg.tommyapi.com";;
  http://*|https://*) HOST="${ENDPOINT%/}";;
  *) die "--endpoint must be us, cn or sg";;
esac

WANT_CLAUDE=0; WANT_CODEX=0
IFS=',' read -r -a _t <<< "$TOOLS"
for t in "${_t[@]}"; do
  case "$t" in
    all) WANT_CLAUDE=1; WANT_CODEX=1;;
    claude|claude-code) WANT_CLAUDE=1;;
    codex) WANT_CODEX=1;;
    *) die "unknown tool '$t' (supported: claude, codex, all; GUI clients are configured by hand, see README)";;
  esac
done

TS="$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLAUDE_FILE="$HOME/.claude/settings.json"
CODEX_FILE="$HOME/.codex/config.toml"

# ---- key ----
if [ "$UNINSTALL" = 0 ]; then
  if [ -z "$KEY" ]; then
    if [ "$DRY" = 1 ]; then KEY="sk-xxxxxxxx"
    elif [ -t 0 ]; then printf 'TommyAPI key (sk-...): '; read -rs KEY; echo
    elif [ -r /dev/tty ]; then printf 'TommyAPI key (sk-...): ' >/dev/tty; read -rs KEY </dev/tty; echo >/dev/tty
    else die "no key: pass --key sk-xxx or set TOMMYAPI_KEY (get one at https://tommyapi.com/console)"; fi
  fi
  [[ "$KEY" =~ ^[A-Za-z0-9._~+/=-]+$ ]] || die "key is empty or contains unexpected characters"
  case "$KEY" in sk-*) :;; *) say "warning: key does not start with sk-";; esac
fi

# ---- helpers ----
apply_file() { # target newfile
  local f="$1" new="$2" fresh=0
  [ -f "$f" ] || fresh=1
  if [ "$fresh" = 0 ] && cmp -s "$f" "$new"; then say "  = $f (unchanged)"; return; fi
  if [ "$DRY" = 1 ]; then say "  [dry-run] would write $f"; return; fi
  mkdir -p "$(dirname "$f")"
  if [ "$fresh" = 0 ]; then cp -p "$f" "$f.bak-tommyapi-$TS"; say "  backup: $f.bak-tommyapi-$TS"; fi
  cat "$new" > "$f"
  if [ "$fresh" = 1 ]; then chmod 600 "$f" 2>/dev/null || true; fi
  say "  + $f"
}
remove_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  if [ "$DRY" = 1 ]; then say "  [dry-run] would remove $f (empty after uninstall)"; return; fi
  cp -p "$f" "$f.bak-tommyapi-$TS"; rm -f "$f"
  say "  - $f (empty after uninstall; backup: $f.bak-tommyapi-$TS)"
}

JSON_TOOL=""
find_json_tool() {
  local c
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import json' >/dev/null 2>&1; then JSON_TOOL="$c"; return; fi
  done
  if command -v jq >/dev/null 2>&1; then JSON_TOOL="jq"; return; fi
  JSON_TOOL=""
}

PY_SRC='
import sys,json
mode,base,tok,model=sys.argv[1:5]
raw=sys.stdin.buffer.read().decode("utf-8")
try:
    d=json.loads(raw) if raw.strip() else {}
    assert isinstance(d,dict)
except Exception as e:
    sys.stderr.write("settings.json is not a valid JSON object: %s\n"%e); sys.exit(3)
env=d.get("env")
if mode=="set":
    if not isinstance(env,dict): env={}
    env["ANTHROPIC_BASE_URL"]=base; env["ANTHROPIC_AUTH_TOKEN"]=tok
    if model: env["ANTHROPIC_MODEL"]=model
    d["env"]=env
elif isinstance(env,dict) and "tommyapi" in str(env.get("ANTHROPIC_BASE_URL","")):
    for k in ("ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_MODEL"): env.pop(k,None)
    if not env: d.pop("env")
sys.stdout.buffer.write((json.dumps(d,indent=2,ensure_ascii=False)+"\n").encode("utf-8"))
'
JQ_SRC='
if type != "object" then error("settings.json is not a JSON object") else . end
| if $mode == "set" then
    .env = ((if (.env|type)=="object" then .env else {} end)
      + {ANTHROPIC_BASE_URL:$base, ANTHROPIC_AUTH_TOKEN:$tok}
      + (if $model != "" then {ANTHROPIC_MODEL:$model} else {} end))
  elif ((.env|type)=="object") and ((.env.ANTHROPIC_BASE_URL // "")|contains("tommyapi")) then
    .env |= del(.ANTHROPIC_BASE_URL, .ANTHROPIC_AUTH_TOKEN, .ANTHROPIC_MODEL)
    | if (.env|length)==0 then del(.env) else . end
  else . end
'
json_edit() { # mode ; stdin=json ; stdout=new json
  if [ "$JSON_TOOL" = jq ]; then
    jq --arg mode "$1" --arg base "$HOST" --arg tok "$KEY" --arg model "$MODEL" "$JQ_SRC"
  else
    "$JSON_TOOL" -c "$PY_SRC" "$1" "$HOST" "$KEY" "$MODEL"
  fi
}

# Drop our managed blocks, any [model_providers.tommyapi] table and the top-level
# model_provider line (uninstall: only when it is ours). Trims outer blank lines.
toml_strip() { # $1 = 1 -> only drop model_provider if it mentions tommyapi
  awk -v only="$1" '
    /^# >>> tommyapi/ {skipm=1; next}
    skipm { if ($0 ~ /^# <<< tommyapi/) skipm=0; next }
    /^[ \t]*\[\[?[A-Za-z0-9_."\047 -]+\]\]?[ \t]*(#.*)?$/ { hdr=1; skipt = ($0 ~ /^[ \t]*\[model_providers\.tommyapi\][ \t]*(#.*)?$/); if (skipt) next }
    skipt { next }
    only == 1 && /^# tommyapi-disabled: / { sub(/^# tommyapi-disabled: /, ""); keep = 1 }
    !keep && !hdr && /^[ \t]*model_provider[ \t]*=/ { if ($0 ~ /tommyapi/ || only == 1) next; $0 = "# tommyapi-disabled: " $0 }
    { keep = 0
      if ($0 ~ /^[ \t]*$/) { if (started) blank++; next }
      for (i = 0; i < blank; i++) print ""
      blank = 0; started = 1; print }'
}
rc_strip() {
  awk '/^# >>> tommyapi/{s=1;next} s&&/^# <<< tommyapi/{s=0;next} !s{print}'
}

pick_rc() {
  case "${SHELL:-}" in
    */zsh) echo "$HOME/.zshrc";;
    */fish) echo "";;
    *) if [ "$(uname -s)" = Darwin ] && [ ! -f "$HOME/.bashrc" ]; then echo "$HOME/.bash_profile"; else echo "$HOME/.bashrc"; fi;;
  esac
}

# ---- tasks ----
do_claude() {
  say "[claude] $CLAUDE_FILE"
  find_json_tool
  if [ -z "$JSON_TOOL" ]; then
    say "  python/jq not found; add this to $CLAUDE_FILE by hand:"
    say "  { \"env\": { \"ANTHROPIC_BASE_URL\": \"$HOST\", \"ANTHROPIC_AUTH_TOKEN\": \"<your key>\" } }"
    return
  fi
  local cur="$TMP/claude.cur" new="$TMP/claude.new"
  if [ -f "$CLAUDE_FILE" ]; then cp "$CLAUDE_FILE" "$cur"; else echo '{}' > "$cur"; fi
  if [ "$UNINSTALL" = 1 ]; then
    [ -f "$CLAUDE_FILE" ] || { say "  (not present)"; return; }
    json_edit strip < "$cur" > "$new" || die "could not edit $CLAUDE_FILE"
    if [ "$(tr -d ' \n\r' < "$new")" = "{}" ]; then remove_file "$CLAUDE_FILE"; else apply_file "$CLAUDE_FILE" "$new"; fi
  else
    json_edit set < "$cur" > "$new" || die "could not edit $CLAUDE_FILE"
    apply_file "$CLAUDE_FILE" "$new"
  fi
}

do_codex() {
  say "[codex] $CODEX_FILE"
  local cur="$TMP/codex.cur" new="$TMP/codex.new" rest
  if [ -f "$CODEX_FILE" ]; then cp "$CODEX_FILE" "$cur"; else : > "$cur"; fi
  if [ "$UNINSTALL" = 1 ]; then
    [ -f "$CODEX_FILE" ] || say "  (not present)"
    if [ -f "$CODEX_FILE" ]; then
      rest="$(toml_strip 1 < "$cur")"
      if [ -z "$rest" ]; then remove_file "$CODEX_FILE"; else printf '%s\n' "$rest" > "$new"; apply_file "$CODEX_FILE" "$new"; fi
    fi
  else
    rest="$(toml_strip 0 < "$cur")"
    {
      printf '# >>> tommyapi >>>\nmodel_provider = "tommyapi"\n# <<< tommyapi <<<\n'
      if [ -n "$rest" ]; then printf '\n%s\n' "$rest"; fi
      printf '\n# >>> tommyapi >>>\n[model_providers.tommyapi]\nname = "TommyAPI"\nbase_url = "%s/v1"\nenv_key = "TOMMYAPI_KEY"\nwire_api = "responses"\n# <<< tommyapi <<<\n' "$HOST"
    } > "$new"
    apply_file "$CODEX_FILE" "$new"
  fi
  # TOMMYAPI_KEY environment variable lives in the shell rc file
  local rc; rc="$(pick_rc)"
  if [ -z "$rc" ]; then
    say "  fish shell: run  set -Ux TOMMYAPI_KEY <your key>  yourself."; return
  fi
  say "[codex env] $rc"
  local rcnew="$TMP/rc.new" rcrest=""
  if [ -f "$rc" ]; then rcrest="$(rc_strip < "$rc")"; fi
  if [ "$UNINSTALL" = 1 ]; then
    if [ ! -f "$rc" ]; then say "  (not present)"; return; fi
    if [ -z "$rcrest" ]; then remove_file "$rc"; else printf '%s\n' "$rcrest" > "$rcnew"; apply_file "$rc" "$rcnew"; fi
  else
    {
      if [ -n "$rcrest" ]; then printf '%s\n\n' "$rcrest"; fi
      printf "# >>> tommyapi >>>\nexport TOMMYAPI_KEY='%s'\n# <<< tommyapi <<<\n" "$KEY"
    } > "$rcnew"
    apply_file "$rc" "$rcnew"
  fi
}

check_conn() {
  command -v curl >/dev/null 2>&1 || { say "(curl not found, skipping self-check)"; return; }
  local code
  code="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$HOST/v1/models" 2>/dev/null)" || code="000"
  case "$code" in
    200) say "Self-check: OK, $HOST/v1/models returned 200. Your key works.";;
    401|403) say "Self-check: HTTP $code, the key was rejected. Check it at https://tommyapi.com/console (Tokens page).";;
    000) say "Self-check: timed out / unreachable. Try --endpoint cn (China) or --endpoint sg (Singapore).";;
    *) say "Self-check: unexpected HTTP $code from $HOST/v1/models.";;
  esac
}

# ---- run ----
if [ "$UNINSTALL" = 1 ]; then say "Uninstalling TommyAPI entries (backups are kept)"; else say "Configuring TommyAPI ($HOST)"; fi
if [ "$DRY" = 1 ]; then say "(dry-run: nothing will be written)"; fi
if [ "$WANT_CLAUDE" = 1 ]; then do_claude; fi
if [ "$WANT_CODEX" = 1 ]; then do_codex; fi

if [ "$UNINSTALL" = 0 ]; then
  say ""
  say "GUI clients (Cursor / Cline / Roo Code / Cherry Studio / Open WebUI): set"
  say "  Base URL = $HOST/v1   API Key = your key   (see README)"
  if [ "$CHECK" = 1 ] && [ "$DRY" = 0 ]; then check_conn; fi
  say ""
  say "Done. Open a NEW terminal, then run: claude   or   codex"
else
  say "Done."
fi
