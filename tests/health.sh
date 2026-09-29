#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"
mkdir -p "$HOME"
source ./plak.sh >/dev/null
plak_json_string $'quote" slash\\ ctrl\001 newline\n' > "$tmpdir/string.json"
python3 - "$tmpdir/string.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == 'quote" slash\\ ctrl\x01 newline\n'
PY
mkdir -p "$PLAK_SITE_DIR" "$LOGS_DIR" "$GUI_DIR"
printf 'memory_limit = 1G\nopcache.memory_consumption = 128\n' > "$PHP_INI_FILE"
printf 'opcacheXmemory_consumption = 999\n' >> "$PHP_INI_FILE"
[ "$(plak_site_ini_get opcache.memory_consumption 8)" = 128 ]
printf 'HTTP_PORT=80\n' > "$CONFIG_FILE"
is_caddy_running() { return 1; }
systemctl() { echo inactive; return 3; }
journalctl() { return 1; }
plak_health_web() { return 1; }
plak_health_report --json > "$tmpdir/report.json"
python3 - "$tmpdir/report.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['services']['frankenphp']=='stopped'
assert r['services']['mariadb']=='stopped'
assert r['web_php'] is None
PY
regenerate_caddyfile() { echo reload >> "$tmpdir/restarts"; }
start_caddy_service() { echo restart >> "$tmpdir/restarts"; }
plak_health_opcache set opcache.memory_consumption=256 --yes >/dev/null
grep -q 'opcache.memory_consumption = 256' "$PHP_INI_FILE"
[ ! -e "$tmpdir/restarts" ]
cp "$PHP_INI_FILE" "$tmpdir/before"
for setting in opcache.memory_consumption=0 opcache.memory_consumption=08 opcache.memory_consumption=99999999 opcache.enable_cli=1 invalid=42; do
    if plak_health_opcache set "$setting" 2>/dev/null; then exit 1; fi
    cmp "$tmpdir/before" "$PHP_INI_FILE"
done
plak_health_opcache set opcache.memory_consumption=512 --restart >/dev/null
grep -q restart "$tmpdir/restarts"
grep -q 'opcache.memory_consumption = 512' "$PHP_INI_FILE"
start_caddy_service() { return 1; }
if plak_health_opcache set opcache.memory_consumption=256 --restart >/dev/null; then exit 1; fi
if plak_health_opcache --json 2>/dev/null; then exit 1; fi
create_gui_file >/dev/null
php -l "$GUI_DIR/health.php" >/dev/null
php -r 'register_shutdown_function(function(){if(http_response_code()!==403) exit(1);}); $_SERVER["REMOTE_ADDR"]="192.168.1.2"; include $argv[1];' "$GUI_DIR/health.php" > "$tmpdir/denied"
[ ! -s "$tmpdir/denied" ]
php -r '$_SERVER["REMOTE_ADDR"]="127.0.0.1"; include $argv[1];' "$GUI_DIR/health.php" > "$tmpdir/probe.json"
python3 - "$tmpdir/probe.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))
assert r['source']=='cli' # Direct fixture invocation is not a web cache.
assert 'opcache_status' in r and 'opcache_configuration' in r
PY
source commands/health
curl() { printf '%s' '<html>dashboard fallback</html>'; }
if plak_health_web json >/dev/null; then exit 1; fi
curl() { printf '%s' '{"source":"cli","opcache_status":{}}'; }
if plak_health_web json >/dev/null; then exit 1; fi
curl() { printf '%s' '{"source":"web","opcache_status":{"cache_full":true,"memory_usage":{"free_memory":0},"opcache_statistics":{"hits":12,"misses":3}}}'; }
plak_health_opcache --json > "$tmpdir/full.json"
python3 - "$tmpdir/full.json" <<'PY'
import json, sys
r=json.load(open(sys.argv[1]))['opcache_status']
assert r['cache_full'] and r['memory_usage']['free_memory']==0
assert r['opcache_statistics']=={'hits':12,'misses':3}
PY
echo 'health tests passed'
