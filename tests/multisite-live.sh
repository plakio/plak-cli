#!/usr/bin/env bash
# Real WordPress/MariaDB behavior; optionally validates official FrankenPHP
# TLS/routing, dashboard acceptance and web OPcache/HTTP2 under load.
set -euo pipefail
[ "${PLAK_LIVE_TESTS:-0}" = 1 ] || { echo 'multisite live test skipped (set PLAK_LIVE_TESTS=1; downloads WordPress)'; exit 0; }
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
for dependency in mariadbd mariadb-install-db mariadb php python3 wp; do
    command -v "$dependency" >/dev/null || { echo "multisite live test skipped: $dependency missing"; exit 0; }
done
./compile.sh >/dev/null
tmpdir=$(mktemp -d /tmp/opencode/plak-multisite-test.XXXXXX)
server_pid=""
web_pid=""
mailpit_pid=""
cleanup_live_fixture() {
    local artifact pid
    if [ -n "${PLAK_TEST_DIAGNOSTICS:-}" ]; then
        mkdir -p "$PLAK_TEST_DIAGNOSTICS"
        for artifact in web-health web.log dashboard-create live-users live-ready live-mail live-mail-detail live-editor-login core-up; do
            [ ! -f "$tmpdir/$artifact" ] || cp "$tmpdir/$artifact" "$PLAK_TEST_DIAGNOSTICS/"
        done
    fi
    for pid in "$mailpit_pid" "$web_pid" "$server_pid"; do
        [ -z "$pid" ] || { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
    done
    rm -rf "$tmpdir"
}
trap cleanup_live_fixture EXIT
isolate_live_caddyfile() {
    python3 - "$CADDYFILE_PATH" "$http_port" "$https_port" "$admin_port" <<'PY'
import sys
p=sys.argv[1]; text=open(p).read()
text=text.replace('{\n','{\n    admin 127.0.0.1:'+sys.argv[4]+'\n    skip_install_trust\n    default_bind 127.0.0.1\n    http_port '+sys.argv[2]+'\n    https_port '+sys.argv[3]+'\n',1)
text=text.replace('frankenphp {','frankenphp {\n        num_threads 2\n        max_threads 4',1)
open(p,'w').write(text)
PY
}
export HOME="$tmpdir/home" PLAK_NO_PATH_PRELUDE=1 PLAK_TERMINAL_LINKS=0
mkdir -p "$HOME/.local/bin" "$HOME/Plak/Logs" "$tmpdir/data"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
mariadb-install-db --no-defaults --datadir="$tmpdir/data" --auth-root-authentication-method=normal > "$tmpdir/init.log" 2>&1
mariadbd --no-defaults --datadir="$tmpdir/data" --socket="$tmpdir/mysql.sock" --port="$port" --bind-address=127.0.0.1 --pid-file="$tmpdir/mysql.pid" > "$tmpdir/server.log" 2>&1 &
server_pid=$!
for _ in {1..50}; do
    if mariadb --no-defaults --socket="$tmpdir/mysql.sock" -u root -e 'SELECT 1' >/dev/null 2>&1; then break; fi
    sleep 0.1
done
mariadb --no-defaults --socket="$tmpdir/mysql.sock" -u root -e "CREATE USER 'plak_test'@'127.0.0.1' IDENTIFIED BY 'testpass'; GRANT ALL ON *.* TO 'plak_test'@'127.0.0.1';"
cat > "$HOME/.local/bin/frankenphp" <<'FRANK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    php-cli) shift; exec php "$@" ;;
    reload) exit 0 ;;
    *) exit 1 ;;
esac
FRANK
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.local/bin/mailpit"
chmod +x "$HOME/.local/bin/"*
export PATH="$HOME/.local/bin:$PATH"
printf "DB_USER='plak_test'\nDB_PASSWORD='testpass'\nDB_HOST='127.0.0.1'\nDB_PORT='%s'\n" "$port" > "$HOME/Plak/config"
printf 'memory_limit=1G\nerror_reporting=6143\nsendmail_path=/bin/true\n' > "$HOME/Plak/php.ini"
source ./plak.sh >/dev/null
export PLAK_SITE_CMD="$ROOT_DIR/plak.sh"
gum() { :; }
is_caddy_running() { return 0; }
for mode in subdirectories subdomains; do
    name="ms-$mode"
    plak_site_add "$name" --wp-version 6.8.1 --multisite "$mode" --no-agent --no-reload > "$tmpdir/add.log" 2>&1 || { cat "$tmpdir/add.log"; exit 1; }
    plak_network create "$name" team --title Team > "$tmpdir/network.log" 2>&1 || { cat "$tmpdir/network.log"; exit 1; }
    plak_network "$name" --json > "$tmpdir/network.json"
    python3 - "$tmpdir/network.json" "$mode" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['multisite'] and r['mode']==sys.argv[2]
assert len(r['sites'])==2 and r['sites'][1]['id']==2
assert all(site['url'].startswith('https://') for site in r['sites'])
PY
    plak_site_login "$name" admin --subsite 2 --raw > "$tmpdir/login"
    grep -q wp-login.php "$tmpdir/login"
    if plak_site_login "$name" admin --subsite 'https://evil.example/' --raw >/dev/null 2>&1; then exit 1; fi
    if plak_site_login "$name" admin --subsite 999 --raw >/dev/null 2>&1; then exit 1; fi
    public="$SITES_DIR/$name.localhost/public"
    plak_multisite_wp "$public" user create outsider outsider@example.test --role=subscriber >/dev/null
    if plak_site_login "$name" outsider --subsite 2 --raw >/dev/null 2>&1; then exit 1; fi
    plak_multisite_wp "$public" site list --format=json > "$tmpdir/source-before"
    plak_multisite_wp "$public" option add serialized_test '{"url":"https://example.'"$name"'.localhost/"}' --format=json >/dev/null
    (plak_site_clone "$name" "$name-copy" --yes --no-reload) > "$tmpdir/clone.log" 2>&1 || { cat "$tmpdir/clone.log"; exit 1; }
    plak_multisite_wp "$public" site list --format=json > "$tmpdir/source-after"
    cmp "$tmpdir/source-before" "$tmpdir/source-after"
    plak_multisite_wp "$public" option get serialized_test --format=json > "$tmpdir/source-option"
    grep -q "$name.localhost" "$tmpdir/source-option"
    copied="$SITES_DIR/$name-copy.localhost/public"
    plak_multisite_validate_local "$copied" "$name-copy"
    plak_multisite_wp "$copied" option get serialized_test --format=json > "$tmpdir/option.json"
    grep -q "$name-copy.localhost" "$tmpdir/option.json"
    [ "$(cat "$SITES_DIR/$name-copy.localhost/.multisite-mode")" = "$mode" ]
    (plak_site_rename "$name-copy" "$name-renamed") > "$tmpdir/rename.log" 2>&1 || { cat "$tmpdir/rename.log"; exit 1; }
    [ ! -d "$SITES_DIR/$name-copy.localhost" ]
    plak_multisite_validate_local "$SITES_DIR/$name-renamed.localhost/public" "$name-renamed"
    if plak_site_lan_enable "$name" > /dev/null 2>&1; then exit 1; fi
    [ ! -f "$SITES_DIR/$name.localhost/lan_config" ]
    # Real WordPress component metadata, including a MU-plugin file rollback.
    printf '<?php // History version 1\n' > "$public/wp-content/mu-plugins/history-demo.php"
    plak_history "$name" save --note 'Live history test' > "$tmpdir/history-first"
    history_first=$(php -r '$r=json_decode(file_get_contents($argv[1]),true); echo $r["id"];' "$tmpdir/history-first")
    plak_history "$name" save > "$tmpdir/history-noop"
    grep -q '"changed": false' "$tmpdir/history-noop"
    printf '<?php // History version 2\n' > "$public/wp-content/mu-plugins/history-demo.php"
    plak_history "$name" restore "$history_first" mu-plugins/history-demo.php --yes > "$tmpdir/history-restore"
    grep -q 'History version 1' "$public/wp-content/mu-plugins/history-demo.php"
done
regenerate_caddyfile > "$tmpdir/caddy.log"
grep -q 'ms-subdomains.localhost, \*.ms-subdomains.localhost' "$CADDYFILE_PATH"
grep -q 'tls internal' "$CADDYFILE_PATH"
grep -q 'rewrite @ms_assets' "$CADDYFILE_PATH"
if [ -n "${PLAK_TEST_FRANKENPHP:-}" ]; then
    [ -x "$PLAK_TEST_FRANKENPHP" ] || { echo 'PLAK_TEST_FRANKENPHP must point to an executable binary.' >&2; exit 1; }
    history_root_flag=""
    [ "$(id -u)" -ne 0 ] || history_root_flag=--allow-root
    PLAK_HISTORY_SITE="$SITES_DIR/ms-subdirectories.localhost" PLAK_HISTORY_WP="$(plak_wp_resolve_phar)" PLAK_HISTORY_FRANK="$PLAK_TEST_FRANKENPHP" PLAK_HISTORY_ROOT_FLAG="$history_root_flag" PLAK_HISTORY_ARGS='["save","--note","Official FrankenPHP history test"]' \
        "$PLAK_TEST_FRANKENPHP" php-cli -r "$(plak_history_program)" > "$tmpdir/history-frank"
    grep -q '"changed"' "$tmpdir/history-frank"
    export XDG_DATA_HOME="$tmpdir/xdg-data" XDG_CONFIG_HOME="$tmpdir/xdg-config"
    read -r http_port https_port admin_port < <(python3 - <<'PY'
import socket
sockets=[socket.socket() for _ in range(3)]
for s in sockets: s.bind(('127.0.0.1',0))
print(*(s.getsockname()[1] for s in sockets))
PY
)
    python3 - "$CADDYFILE_PATH" "$http_port" "$https_port" "$admin_port" <<'PY'
import sys
p=sys.argv[1]; text=open(p).read()
text=text.replace('{\n','{\n    admin 127.0.0.1:'+sys.argv[4]+'\n    skip_install_trust\n    default_bind 127.0.0.1\n    http_port '+sys.argv[2]+'\n    https_port '+sys.argv[3]+'\n',1)
text=text.replace('frankenphp {','frankenphp {\n        num_threads 2\n        max_threads 4',1)
open(p,'w').write(text)
PY
    mkdir -p "$APP_DIR"
    echo '<?php' > "$APP_DIR/whoops_bootstrap.php"
    create_gui_file >/dev/null
    for mode in subdomains subdirectories; do
        public="$SITES_DIR/ms-$mode.localhost/public"
        printf '<?php require dirname(__DIR__) . "/wp-load.php"; header("Content-Type: application/json"); echo json_encode(["blog"=>get_current_blog_id(),"uri"=>$_SERVER["REQUEST_URI"]]);' > "$public/wp-admin/plak-probe.php"
    done
    "$PLAK_TEST_FRANKENPHP" validate --config "$CADDYFILE_PATH" > "$tmpdir/validate.log" 2>&1 || { cat "$tmpdir/validate.log"; exit 1; }
    "$PLAK_TEST_FRANKENPHP" run --config "$CADDYFILE_PATH" > "$tmpdir/web.log" 2>&1 &
    web_pid=$!
    for _ in {1..100}; do
        if curl --noproxy '*' -ksf --connect-to "plak.localhost:443:127.0.0.1:$https_port" https://plak.localhost/health.php > "$tmpdir/web-health" 2>/dev/null; then break; fi
        sleep 0.1
    done
    python3 - "$tmpdir/web-health" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['source']=='web'
assert r['opcache_status'] is not None, r
assert 'cache_full' in r['opcache_status']
assert 'free_memory' in r['opcache_status']['memory_usage']
PY
    ca="$XDG_DATA_HOME/caddy/pki/authorities/local/root.crt"
    # Provision through the actual dashboard API, not a mocked plak executable.
    curl --noproxy '*' --cacert "$ca" -fsS \
        --connect-to "plak.localhost:443:127.0.0.1:$https_port" \
        https://plak.localhost/ > "$tmpdir/dashboard-index"
    dashboard_token=$(cat "$HOME/Plak/cache/dashboard-token")
    curl --noproxy '*' --cacert "$ca" -fsS --max-time 120 \
        --connect-to "plak.localhost:443:127.0.0.1:$https_port" \
        -H 'Origin: https://plak.localhost' -H 'Content-Type: application/json' \
        --data "{\"action\":\"add_site\",\"site_name\":\"dash-manual\",\"agent\":false,\"csrf\":\"$dashboard_token\"}" \
        https://plak.localhost/api.php > "$tmpdir/dashboard-create"
    python3 - "$tmpdir/dashboard-create" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r.get('success'), r
PY
    [ -f "$SITES_DIR/dash-manual.localhost/public/wp-config.php" ]
    [ ! -f "$SITES_DIR/dash-manual.localhost/agent-ready" ]
    plak_multisite_wp "$SITES_DIR/dash-manual.localhost/public" core is-installed --skip-plugins --skip-themes
    echo 'Real dashboard manual WordPress creation passed'
    for entry in 'ms-subdirectories.localhost /team/wp-admin/plak-probe.php' 'team.ms-subdomains.localhost /wp-admin/plak-probe.php'; do
        read -r host path <<< "$entry"
        curl --noproxy '*' --cacert "$ca" -fsS --connect-to "$host:443:127.0.0.1:$https_port" "https://$host$path" > "$tmpdir/web-probe"
        python3 - "$tmpdir/web-probe" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['blog']==2, r
PY
    done
    curl --noproxy '*' --cacert "$ca" -fsS --connect-to "ms-subdirectories.localhost:443:127.0.0.1:$https_port" https://ms-subdirectories.localhost/team/wp-includes/css/dashicons.min.css > "$tmpdir/css"
    grep -q dashicons "$tmpdir/css"
    for mode in subdomains subdirectories; do
        name="ms-$mode"
        login=$(plak_site_login "$name" admin --subsite 2 --raw)
        if [ "$mode" = subdomains ]; then host="team.$name.localhost"; expected="https://$host/wp-admin/";
        else host="$name.localhost"; expected="https://$host/team/wp-admin/"; fi
        if ! final=$(curl --noproxy '*' --cacert "$ca" -fsSL --max-redirs 5 --connect-to "$host:443:127.0.0.1:$https_port" -c "$tmpdir/cookies-$mode" -b "$tmpdir/cookies-$mode" -o "$tmpdir/admin-$mode" -w '%{url_effective}' "$login"); then
            echo "Subsite login HTTP flow failed ($mode): $final" >&2; tail -30 "$tmpdir/web.log" >&2; exit 1
        fi
        [[ "$final" = "$expected"* ]] || { echo "Login did not land on subsite admin: $final" >&2; exit 1; }
        grep -q 'wp-admin-bar' "$tmpdir/admin-$mode"
    done
    echo 'Real FrankenPHP TLS/wildcard/subdirectory routing tests passed'
    if [ "${PLAK_TEST_ACCEPTANCE:-0}" = 1 ]; then
        source "$ROOT_DIR/tests/helpers/dashboard-acceptance.sh"
    fi
    if [ "${PLAK_TEST_HEALTH:-0}" = 1 ]; then
        source "$ROOT_DIR/tests/helpers/health-live.sh"
    fi
fi
echo 'Real WordPress multisite creation/subsites/login/clone/rename tests passed'
