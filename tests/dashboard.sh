#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
server_pid=""
mailpit_pid=""
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
    [ -n "$mailpit_pid" ] && kill "$mailpit_pid" 2>/dev/null || true
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

# Hermetic: keep the prelude from adding real Homebrew/Linuxbrew tools.
export PLAK_NO_PATH_PRELUDE=1
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
case " $* " in
    *" login "*)
        echo "https://demo.localhost/wp-login.php?user_id=7&plak_site_login_token=abc1234"
        ;;
esac
exit 0
STUB
chmod +x "$tmpdir/plak-stub"
sed -i "s|^\\\$plak_site_path = .*|\\\$plak_site_path = '$tmpdir/plak-stub';|" "$GUI_DIR/api.php"

# A servable site so list_sites has data.
mkdir -p "$SITES_DIR/demo.localhost/public"
touch "$SITES_DIR/demo.localhost/public/wp-config.php"

# Fixtures for the diagnostics panel (CLI-14): a shared PHP error log with
# entries from two sites, a per-site debug.log, and a Caddy access log.
mkdir -p "$SITES_DIR/demo.localhost/logs" "$SITES_DIR/demo.localhost/public/wp-content" "$HOME/Plak/Logs"
cat > "$HOME/Plak/Logs/errors.log" <<PHPERR
[29-Sep-2026 10:00:00 UTC] PHP Warning:  Undefined array key "x" in $SITES_DIR/demo.localhost/public/wp-content/themes/x/functions.php on line 12
[29-Sep-2026 10:00:00 UTC] PHP Warning:  Undefined array key "x" in $SITES_DIR/demo.localhost/public/wp-content/themes/x/functions.php on line 12
[29-Sep-2026 10:01:00 UTC] PHP Fatal error:  Uncaught Error: boom in $SITES_DIR/demo.localhost/public/wp-content/plugins/p/p.php on line 9
Stack trace:
#0 {main}
[29-Sep-2026 10:02:00 UTC] PHP Warning:  something unrelated in $SITES_DIR/other.localhost/public/x.php on line 1
PHPERR
cat > "$SITES_DIR/demo.localhost/public/wp-content/debug.log" <<'DEBUGLOG'
[29-Sep-2026 11:00:00 UTC] PHP Notice:  hello from debug
DEBUGLOG
now_ts=$(date +%s)
cat > "$SITES_DIR/demo.localhost/logs/caddy.log" <<ACCESS
{"level":"info","ts":$now_ts,"logger":"http.log.access","msg":"handled request","request":{"remote_ip":"127.0.0.1","method":"GET","host":"demo.localhost","uri":"/wp-admin/"},"size":100,"status":200,"duration":0.01}
{"level":"info","ts":$now_ts,"logger":"http.log.access","msg":"handled request","request":{"remote_ip":"127.0.0.1","method":"GET","host":"demo.localhost","uri":"/wp-admin/"},"size":100,"status":200,"duration":0.01}
{"level":"info","ts":$now_ts,"logger":"http.log.access","msg":"handled request","request":{"remote_ip":"127.0.0.1","method":"GET","host":"demo.localhost","uri":"/"},"size":200,"status":200,"duration":0.02}
{"level":"info","ts":$now_ts,"logger":"http.log.access","msg":"handled request","request":{"remote_ip":"127.0.0.1","method":"GET","host":"demo.localhost","uri":"/missing"},"size":0,"status":404,"duration":0.005}
{"level":"error","ts":$now_ts,"logger":"http.log.access","msg":"handled request","request":{"remote_ip":"127.0.0.1","method":"POST","host":"demo.localhost","uri":"/wp-admin/admin-ajax.php"},"size":0,"status":500,"duration":1.5}
{"level":"info","ts":$now_ts,"logger":"http.log.access","msg":"handled request","request":{"remote_ip":"127.0.0.1","method":"GET","host":"demo.localhost","uri":"/style.css"},"size":50,"status":200,"duration":0.003}
ACCESS

# The WP-CLI stub and its call log must exist (and be exported) before the PHP
# server starts, since the server process inherits its environment at launch.
cat > "$tmpdir/plak-wp-stub" <<'WPSTUB'
#!/usr/bin/env bash
echo "$*" >> "$WP_CALLS"
case "$*" in
    *"core version"*) echo "6.7.1" ;;
    *"plugin list"*)
        echo '[{"name":"akismet","title":"Akismet","status":"active","version":"5.3","update":"none","file":"akismet/akismet.php"},{"name":"plak-helper","title":"Plak","status":"must-use","version":"1.0","update":"none","file":"plak-cli-helper.php"}]'
        ;;
    *"theme list"*)
        echo '[{"name":"twentytwentyfour","title":"Twenty Twenty-Four","status":"active","version":"1.2","update":"available","update_version":"1.3"},{"name":"twentytwentythree","title":"Twenty Twenty-Three","status":"inactive","version":"1.1","update":"none"}]'
        ;;
    *"user list"*)
        echo '[{"ID":"1","user_login":"admin","display_name":"Admin","user_email":"admin@example.test","roles":"administrator"},{"ID":"7","user_login":"editor","display_name":"Ed","user_email":"ed@example.test","roles":"editor"}]'
        ;;
    *"cron event list"*)
        echo '[{"hook":"wp_version_check","next_run_gmt":"2026-09-29 18:00:00","recurrence":"twicedaily","interval":43200},{"hook":"my_single_task","next_run_gmt":"2026-09-29 19:00:00","recurrence":false,"interval":false}]'
        ;;
    *"cron event run"*)
        echo "Success: Ran 1 of 1 events."
        ;;
    *"login demo"*)
        echo "https://demo.localhost/wp-login.php?user_id=7&plak_site_login_token=abc1234"
        ;;
    *"plugin deactivate"*) echo "Success: Deactivated." ;;
esac
exit 0
WPSTUB
chmod +x "$tmpdir/plak-wp-stub"
sed -i "s|^\\\$plak_site_path = .*|\\\$plak_site_path = '$tmpdir/plak-wp-stub';|" "$GUI_DIR/api.php"
export WP_CALLS="$tmpdir/wp-calls.log"
: > "$WP_CALLS"

# A Mailpit API double for the mail panel (CLI-15). Serves canned messages,
# a HTML body (with a script and a cid: image), and records seen/delete calls.
cat > "$tmpdir/mailpit.php" <<'MAILPIT'
<?php
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];
if ($method === 'GET' && $path === '/api/v1/messages') {
    header('Content-Type: application/json');
    echo json_encode([
        'total' => 2, 'unread' => 1, 'count' => 2, 'start' => 0,
        'messages' => [
            ['ID' => 'm1', 'From' => ['Name' => 'WordPress', 'Address' => 'wordpress@demo.localhost'], 'To' => [['Name' => '', 'Address' => 'admin@example.test']], 'Subject' => 'Reset password', 'Created' => '2026-09-29T10:00:00Z', 'Read' => false, 'Size' => 1234, 'Attachments' => 0, 'Snippet' => 'Click to reset'],
            ['ID' => 'm2', 'From' => ['Name' => 'Other', 'Address' => 'noreply@other.test'], 'To' => [['Name' => '', 'Address' => 'x@y.test']], 'Subject' => 'Unattributed', 'Created' => '2026-09-29T11:00:00Z', 'Read' => true, 'Size' => 500, 'Attachments' => 1, 'Snippet' => 'hello'],
        ],
    ]);
    exit;
}
if ($method === 'GET' && preg_match('#^/api/v1/message/([^/]+)$#', $path, $m)) {
    header('Content-Type: application/json');
    echo json_encode([
        'ID' => $m[1],
        'From' => ['Name' => 'WordPress', 'Address' => 'wordpress@demo.localhost'],
        'To' => [['Name' => '', 'Address' => 'admin@example.test']],
        'Subject' => 'Reset password',
        'Date' => '2026-09-29T10:00:00Z',
        'HTML' => '<p>Hi there</p><script>alert(1)</script><a href="https://demo.localhost/wp-login.php?key=abc">Reset</a><img src="cid:img1">',
        'Text' => 'Reset: https://demo.localhost/wp-login.php?key=abc',
        'Headers' => ['Subject' => 'Reset password'],
        'Attachments' => [],
        'Inline' => [['PartID' => '2', 'ContentType' => 'image/png', 'ContentID' => 'img1']],
    ]);
    exit;
}
if ($method === 'GET' && preg_match('#^/api/v1/message/([^/]+)/part/(\d+)$#', $path, $m)) {
    header('Content-Type: image/png');
    echo base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    exit;
}
if ($method === 'PUT' && $path === '/api/v1/messages') {
    file_put_contents(getenv('MAILPIT_LOG'), 'PUT ' . file_get_contents('php://input') . "\n", FILE_APPEND);
    header('Content-Type: application/json'); echo '{}'; exit;
}
if ($method === 'DELETE' && $path === '/api/v1/messages') {
    file_put_contents(getenv('MAILPIT_LOG'), 'DELETE ' . file_get_contents('php://input') . "\n", FILE_APPEND);
    header('Content-Type: application/json'); echo '{}'; exit;
}
http_response_code(404);
echo '{}';
MAILPIT
export MAILPIT_LOG="$tmpdir/mailpit.log"
: > "$MAILPIT_LOG"
mailpit_port=$(( (RANDOM % 2000) + 22000 ))
php -S 127.0.0.1:"$mailpit_port" "$tmpdir/mailpit.php" >/dev/null 2>&1 &
mailpit_pid=$!
export PLAK_MAILPIT_URL="http://127.0.0.1:$mailpit_port"

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
info_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_info\",\"site_name\":\"demo\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"wp_version":"6.7.1"' <<<"$info_out" || fail "site_info did not report the WP version: $info_out"

# --- Plugin listing omits the remote update check by default ---
plugins_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_plugins\",\"site_name\":\"demo\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"must-use"' <<<"$plugins_out" || fail "plugin list did not expose the must-use state: $plugins_out"
grep -q -- '--skip-update-check' "$WP_CALLS" || fail "default plugin list did not skip the remote update check"

# --- Explicit update check drops the skip flag ---
check_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_plugins\",\"site_name\":\"demo\",\"check\":true,\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"checked":true' <<<"$check_out" || fail "explicit check was not acknowledged"

# --- Theme listing shows update availability ---
themes_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_themes\",\"site_name\":\"demo\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"update":"available"' <<<"$themes_out" || fail "theme list did not report an available update: $themes_out"

# --- Plugin op runs with validated slug and allowed op ---
: > "$WP_CALLS"
op_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_plugin_op\",\"site_name\":\"demo\",\"slug\":\"akismet\",\"op\":\"deactivate\",\"status\":\"active\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"success":true' <<<"$op_out" || fail "valid plugin op failed: $op_out"
grep -q 'plugin deactivate akismet' "$WP_CALLS" || fail "plugin op did not invoke the expected command"

# --- An arbitrary op is rejected ---
bad_out=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_plugin_op\",\"site_name\":\"demo\",\"slug\":\"akismet\",\"op\":\"eval\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Invalid operation' <<<"$bad_out" || fail "api.php accepted an arbitrary op"

# --- A shell-ish slug is rejected ---
bad_out=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_plugin_op\",\"site_name\":\"demo\",\"slug\":\"a;rm -rf\",\"op\":\"delete\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Invalid operation' <<<"$bad_out" || fail "api.php accepted an unsafe slug"

# --- Deactivating a must-use plugin is refused ---
mu_out=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_plugin_op\",\"site_name\":\"demo\",\"slug\":\"plak-helper\",\"op\":\"deactivate\",\"status\":\"must-use\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Must-use' <<<"$mu_out" || fail "api.php allowed deactivating a must-use plugin"

# --- CLI-13: users list keeps identity and roles ----------------------------
users_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_users\",\"site_name\":\"demo\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"user_login":"editor"' <<<"$users_out" || fail "site_users did not list the editor: $users_out"
grep -q '"roles":"editor"' <<<"$users_out" || fail "site_users dropped non-administrator roles: $users_out"

# --- CLI-13: one-time login link can target a non-administrator -------------
: > "$WP_CALLS"
login_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_user_login\",\"site_name\":\"demo\",\"user_login\":\"editor\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"success":true' <<<"$login_out" || fail "site_user_login failed for a non-admin: $login_out"
grep -q '/wp-login.php' <<<"$login_out" || fail "site_user_login did not return a login URL: $login_out"

# --- CLI-13: cron listing and controlled runs -------------------------------
cron_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_cron\",\"site_name\":\"demo\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"hook":"wp_version_check"' <<<"$cron_out" || fail "site_cron did not list events: $cron_out"

: > "$WP_CALLS"
cron_run=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_cron_run\",\"site_name\":\"demo\",\"hook\":\"wp_version_check\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"success":true' <<<"$cron_run" || fail "site_cron_run failed: $cron_run"
grep -q 'cron event run wp_version_check' "$WP_CALLS" || fail "site_cron_run did not run the requested hook"

curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_cron_run\",\"site_name\":\"demo\",\"hook\":\"--due-now\",\"csrf\":\"$token\"}" "$base/api.php" >/dev/null
grep -q 'cron event run --due-now' "$WP_CALLS" || fail "site_cron_run did not support --due-now"

bad_cron=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_cron_run\",\"site_name\":\"demo\",\"hook\":\"x; rm -rf /\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Invalid cron hook' <<<"$bad_cron" || fail "api.php accepted an unsafe cron hook"

# --- CLI-13: WP-CLI console passes arguments as data ------------------------
: > "$WP_CALLS"
console_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_wpcli\",\"site_name\":\"demo\",\"args\":[\"option\",\"get\",\"siteurl; rm -rf /\"],\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"exit_code":0' <<<"$console_out" || fail "site_wpcli did not report the exit code: $console_out"
grep -Fq "option get siteurl; rm -rf /" "$WP_CALLS" || fail "site_wpcli did not pass arguments as a single argv element"

empty_console=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_wpcli\",\"site_name\":\"demo\",\"args\":[],\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'No command provided' <<<"$empty_console" || fail "site_wpcli accepted an empty command"

# --- CLI-14: logs by source, site filtering and repeat grouping -------------
logs_php=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_logs\",\"site_name\":\"demo\",\"source\":\"php\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Undefined array key' <<<"$logs_php" || fail "site_logs did not read the PHP error log: $logs_php"
grep -q '"count":2' <<<"$logs_php" || fail "site_logs did not group consecutive repeats"
if grep -q 'something unrelated' <<<"$logs_php"; then fail "site_logs leaked another site's PHP errors"; fi
grep -q '"available":{"php":true,"debug":true,"access":true}' <<<"$logs_php" || fail "site_logs did not report source availability"

logs_debug=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_logs\",\"site_name\":\"demo\",\"source\":\"debug\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'hello from debug' <<<"$logs_debug" || fail "site_logs did not read debug.log"

logs_fatal=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_logs\",\"site_name\":\"demo\",\"source\":\"php\",\"level\":\"fatal error\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"level":"fatal error"' <<<"$logs_fatal" || fail "level filter dropped the fatal error: $logs_fatal"
if grep -q 'Undefined array key' <<<"$logs_fatal"; then fail "fatal-only filter let warnings through"; fi

logs_q=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_logs\",\"site_name\":\"demo\",\"source\":\"php\",\"q\":\"Uncaught\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Uncaught Error' <<<"$logs_q" || fail "log search did not match: $logs_q"

logs_access=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_logs\",\"site_name\":\"demo\",\"source\":\"access\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'admin-ajax.php' <<<"$logs_access" || fail "site_logs did not parse the access log: $logs_access"
grep -q '"count":2' <<<"$logs_access" || fail "access log repeats were not grouped"

logs_bad=$(curl -sS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_logs\",\"site_name\":\"demo\",\"source\":\"../../etc\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Unknown log source' <<<"$logs_bad" || fail "site_logs accepted an unknown source"

# --- CLI-14: traffic aggregation and explicit classification ----------------
traffic=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_traffic\",\"site_name\":\"demo\",\"period\":\"24h\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"requests":6' <<<"$traffic" || fail "traffic did not count every request: $traffic"
grep -q '"errors":2' <<<"$traffic" || fail "traffic did not count 4xx/5xx responses: $traffic"
grep -q '"server_errors":1' <<<"$traffic" || fail "traffic did not count 5xx responses"
grep -q '"admin":2' <<<"$traffic" || fail "traffic misclassified admin requests: $traffic"
grep -q '"pages":2' <<<"$traffic" || fail "traffic misclassified pages: $traffic"
grep -q '"ajax_rest":1' <<<"$traffic" || fail "traffic misclassified AJAX/REST: $traffic"
grep -q '"assets":1' <<<"$traffic" || fail "traffic misclassified assets: $traffic"
grep -q '"duration_ms":1500' <<<"$traffic" || fail "traffic slow list lost the slowest request"
grep -q 'analytics' <<<"$traffic" || fail "traffic did not disclaim production analytics"

traffic_1h=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"site_traffic\",\"site_name\":\"demo\",\"period\":\"1h\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"requests":6' <<<"$traffic_1h" || fail "traffic 1h window dropped recent requests"

# --- CLI-15: mail list, attribution and the global fallback -----------------
mail_all=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"mail_messages\",\"scope\":\"all\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Reset password' <<<"$mail_all" || fail "mail_messages did not list mail: $mail_all"
grep -q 'Unattributed' <<<"$mail_all" || fail "global mail view dropped unattributable mail"
grep -q '"site":"demo.localhost"' <<<"$mail_all" || fail "mail attribution did not match the site domain"
grep -q 'configured maximum' <<<"$mail_all" || fail "mail retention policy was not stated"

mail_site=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"mail_messages\",\"scope\":\"site\",\"site_name\":\"demo\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q 'Reset password' <<<"$mail_site" || fail "per-site mail view dropped the site's mail: $mail_site"
if grep -q 'Unattributed' <<<"$mail_site"; then fail "per-site mail view leaked unattributed mail"; fi

# --- CLI-15: detail sanitizes HTML, extracts links, resolves cid: images ----
: > "$MAILPIT_LOG"
detail=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"mail_message\",\"id\":\"m1\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"success":true' <<<"$detail" || fail "mail_message failed: $detail"
if grep -q 'alert(1)' <<<"$detail"; then fail "mail HTML was not sanitized"; fi
grep -q 'base64,' <<<"$detail" || fail "inline cid image was not resolved to a data URI: $detail"
grep -q 'wp-login.php?key=abc' <<<"$detail" || fail "message links were not extracted"
grep -q 'PUT' "$MAILPIT_LOG" || fail "opening a message did not mark it read"

# --- CLI-15: seen and delete go through Mailpit -----------------------------
: > "$MAILPIT_LOG"
curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"mail_seen\",\"ids\":[\"m2\"],\"read\":false,\"csrf\":\"$token\"}" "$base/api.php" >/dev/null
grep -q '"IDs":\["m2"\]' "$MAILPIT_LOG" || fail "mail_seen did not reach Mailpit"
grep -q '"Read":false' "$MAILPIT_LOG" || fail "mail_seen ignored the read flag"

curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"mail_delete\",\"ids\":[\"m1\"],\"csrf\":\"$token\"}" "$base/api.php" >/dev/null
grep -q 'DELETE' "$MAILPIT_LOG" || fail "mail_delete did not reach Mailpit"

# --- CLI-15: a stopped Mailpit is reported as offline, not as empty --------
kill "$mailpit_pid" 2>/dev/null || true
mailpit_pid=""
offline_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"mail_messages\",\"scope\":\"all\",\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"offline":true' <<<"$offline_out" || fail "a stopped Mailpit was not reported as offline: $offline_out"

# --- add_site passes --no-agent only when the box is unchecked (CLI-33) ------
: > "$WP_CALLS"
add_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"add_site\",\"site_name\":\"dashagent\",\"agent\":true,\"csrf\":\"$token\"}" "$base/api.php")
grep -q '"success":true' <<<"$add_out" || fail "add_site (agent on) failed: $add_out"
grep -q 'add dashagent' "$WP_CALLS" || fail "add_site did not run plak add"
if grep -q -- '--no-agent' "$WP_CALLS"; then
    fail "checked agent box still passed --no-agent"
fi

add_out=$(curl -fsS -X POST -H "$host_header" -H 'Origin: https://plak.localhost' \
    -H 'Content-Type: application/json' --data "{\"action\":\"add_site\",\"site_name\":\"dashplain\",\"agent\":false,\"csrf\":\"$token\"}" "$base/api.php")
grep -q -- '--no-agent' "$WP_CALLS" || fail "unchecked agent box did not pass --no-agent"

# --- listing exposes agent_ready; prepare_agent action exists ---------------
list_out=$(curl -fsS "$base/api.php?action=list_sites")
grep -q '"agent_ready":false' <<<"$list_out" || fail "list_sites did not expose agent_ready: $list_out"
grep -q "case 'prepare_agent'" "$GUI_DIR/api.php" || fail "api.php lacks the prepare_agent action"

# --- index.php carries the hash-routed detail view, components panel and token ---
grep -q '#/site/' "$GUI_DIR/index.php" || fail "index.php lacks the per-site hash route"
grep -q 'const CSRF_TOKEN' "$GUI_DIR/index.php" || fail "index.php did not expose the CSRF token"
grep -q 'loadSiteInfo' "$GUI_DIR/index.php" || fail "index.php lacks the on-demand site info loader"
grep -q 'componentOp' "$GUI_DIR/index.php" || fail "index.php lacks the component op handler"
grep -q 'canDelete' "$GUI_DIR/index.php" || fail "index.php lacks the invalid-action guard"
grep -q 'setToolTab' "$GUI_DIR/index.php" || fail "index.php lacks the site tools panel"
grep -q 'runConsole' "$GUI_DIR/index.php" || fail "index.php lacks the WP-CLI console"
grep -q "case 'site_users'" "$GUI_DIR/api.php" || fail "api.php lacks the site_users action"
grep -q 'loadTraffic' "$GUI_DIR/index.php" || fail "index.php lacks the traffic panel"
grep -q "case 'site_logs'" "$GUI_DIR/api.php" || fail "api.php lacks the site_logs action"
grep -q 'openMail' "$GUI_DIR/index.php" || fail "index.php lacks the mail inbox"
grep -q "case 'mail_messages'" "$GUI_DIR/api.php" || fail "api.php lacks the mail_messages action"

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
