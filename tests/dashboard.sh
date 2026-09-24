#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
server_pid=""
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmpdir"
}
trap cleanup EXIT

fail() {
    echo "dashboard regression test failed: $1" >&2
    exit 1
}

if ! command -v php >/dev/null 2>&1; then
    echo "dashboard regression test skipped: php not available."
    exit 0
fi

source ./plak.sh >/dev/null

# Generate the real dashboard files into a temp HOME so create_gui_file runs
# against an isolated tree.
export HOME="$tmpdir/home"
mkdir -p "$HOME/Plak"
GUI_DIR="$HOME/Plak/App/gui"
ADMINER_DIR="$HOME/Plak/App/adminer"
CUSTOM_CADDY_DIR="$HOME/Plak/App/directives"
SITES_DIR="$HOME/Plak/Sites"
LOGS_DIR="$HOME/Plak/Logs"
CADDYFILE_PATH="$HOME/Plak/Caddyfile"
APP_DIR="$HOME/Plak/App"
mkdir -p "$SITES_DIR" "$GUI_DIR" "$CUSTOM_CADDY_DIR"

cp plak.sh "$tmpdir/plak.sh"
chmod +x "$tmpdir/plak.sh"
cat > "$tmpdir/gen.sh" <<GEN
set -euo pipefail
source "$tmpdir/plak.sh" >/dev/null
HOME="$HOME"
GUI_DIR="$GUI_DIR"
ADMINER_DIR="$ADMINER_DIR"
CUSTOM_CADDY_DIR="$CUSTOM_CADDY_DIR"
SITES_DIR="$SITES_DIR"
APP_DIR="$APP_DIR"
create_gui_file
GEN
bash "$tmpdir/gen.sh" >/dev/null

[ -f "$GUI_DIR/api.php" ] || fail "api.php was not generated"
[ -f "$GUI_DIR/index.php" ] || fail "index.php was not generated"
if grep -q 'PLACEHOLDER' "$GUI_DIR/api.php"; then
    fail "api.php placeholders were not substituted"
fi
grep -q "IS_WSL_PLACEHOLDER" "$GUI_DIR/api.php" && fail "IS_WSL placeholder was not substituted"

# Point the executable at a no-op stub so actions never touch the real stack.
cat > "$tmpdir/plak-stub" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$tmpdir/plak-stub"
sed -i "s|^\\\$plak_site_path = .*|\\\$plak_site_path = '$tmpdir/plak-stub';|" "$GUI_DIR/api.php"

# A servable site so list_sites has data.
mkdir -p "$SITES_DIR/demo.localhost/public"
touch "$SITES_DIR/demo.localhost/public/wp-config.php"

# Serve the generated dashboard with PHP's built-in server so $_GET, $_SERVER
# and php://input behave as they do under FrankenPHP.
port=$(( (RANDOM % 2000) + 20000 ))
php -S 127.0.0.1:"$port" -t "$GUI_DIR" >/dev/null 2>&1 &
server_pid=$!
base="http://127.0.0.1:$port"

for _ in $(seq 1 50); do
    curl -fsS "$base/api.php?action=list_sites" >/dev/null 2>&1 && break
    sleep 0.1
done

# --- GET list_sites works (read-only) ---
list_out=$(curl -fsS "$base/api.php?action=list_sites")
grep -q '"name":"demo"' <<<"$list_out" || fail "list_sites did not return the demo site"

# api.php creates the shared CSRF token on first use.
[ -f "$HOME/Plak/cache/dashboard-token" ] || fail "dashboard token was not created"
token=$(cat "$HOME/Plak/cache/dashboard-token")
[ "${#token}" -ge 32 ] || fail "dashboard token is too short"

host_header="Host: plak.localhost"

# --- POST without Origin/Referer is rejected ---
post_out=$(curl -sS -X POST -H "$host_header" -H 'Content-Type: application/json' \
    --data '{"action":"reload_server"}' "$base/api.php" 2>/dev/null || true)
grep -q 'Cross-origin request blocked' <<<"$post_out" || fail "api.php did not block a POST without Origin"

# --- POST with a bad Origin is rejected ---
post_out=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://evil.example' \
    -H 'Content-Type: application/json' --data '{"action":"reload_server"}' "$base/api.php" 2>/dev/null || true)
grep -q 'Cross-origin request blocked' <<<"$post_out" || fail "api.php did not block a cross-origin POST"

# --- POST with a matching Origin but no CSRF token is rejected ---
post_out=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data '{"action":"reload_server"}' "$base/api.php" 2>/dev/null || true)
grep -q 'CSRF' <<<"$post_out" || fail "api.php did not require a CSRF token"

# --- POST with matching Origin and a wrong CSRF token is rejected ---
post_out=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data '{"action":"reload_server","csrf":"nope"}' "$base/api.php" 2>/dev/null || true)
grep -q 'CSRF' <<<"$post_out" || fail "api.php accepted a wrong CSRF token"

# --- POST with matching Origin and a valid token reaches the action ---
post_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"reload_server\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"success":true' <<<"$post_out" || fail "api.php rejected a valid same-origin POST with the right token: $post_out"

# --- site_info runs on demand and reports WordPress details ---
cat > "$tmpdir/plak-wp-stub" <<'WPSTUB'
#!/usr/bin/env bash
# Args: HOME=... plak-sh wp <site> <command...>
case "$*" in
    *"core version"*) echo "6.7.1" ;;
    *"plugin list"*) printf 'akismet\nhello\n' ;;
esac
exit 0
WPSTUB
chmod +x "$tmpdir/plak-wp-stub"
sed -i "s|^\\\$plak_site_path = .*|\\\$plak_site_path = '$tmpdir/plak-wp-stub';|" "$GUI_DIR/api.php"
info_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_info\",\"site_name\":\"demo\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"wp_version":"6.7.1"' <<<"$info_out" || fail "site_info did not report the WP version: $info_out"
grep -q '"plugins":2' <<<"$info_out" || fail "site_info did not count plugins: $info_out"

# --- index.php carries the hash-routed detail view and CSRF token ---
grep -q '#/site/' "$GUI_DIR/index.php" || fail "index.php lacks the per-site hash route"
grep -q 'const CSRF_TOKEN' "$GUI_DIR/index.php" || fail "index.php did not expose the CSRF token"
grep -q 'loadSiteInfo' "$GUI_DIR/index.php" || fail "index.php lacks the on-demand site info loader"

# --- A public source address is rejected by the PHP guard ---
API_FILE="$GUI_DIR/api.php" HOME="$HOME" php -r '
$_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REMOTE_ADDR"]="203.0.113.5";
$_GET["action"]="list_sites";
include getenv("API_FILE");
' > "$tmpdir/guard.out" 2>/dev/null || true
grep -q 'only on the machine running Plak' "$tmpdir/guard.out" || fail "api.php did not block a public source address"

# --- A Tailscale CGNAT address is allowed by the PHP guard ---
API_FILE="$GUI_DIR/api.php" HOME="$HOME" php -r '
$_SERVER["REQUEST_METHOD"]="GET"; $_SERVER["REMOTE_ADDR"]="100.101.102.103";
$_GET["action"]="list_sites";
include getenv("API_FILE");
' > "$tmpdir/tailnet.out" 2>/dev/null || true
grep -q '"success"' "$tmpdir/tailnet.out" && fail "tailnet address should not be treated as local"
grep -q 'only on the machine running Plak' "$tmpdir/tailnet.out" && fail "tailnet address was incorrectly blocked"

# --- Caddyfile generator restricts admin hosts to the local machine ---
grep -q 'remote_ip 127.0.0.1 ::1' plak.sh || fail "Caddyfile generator lacks the local-only matcher"
grep -q 'This answers only on the machine running Plak' plak.sh || fail "admin hosts lack the 403 response"
grep -q 'remote_ip private_ranges' plak.sh || fail "WSL private-range handling is missing"
grep -q "remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48 127.0.0.1 ::1" plak.sh || fail "Tailscale admin guard is missing"

echo "Dashboard regression tests passed."
