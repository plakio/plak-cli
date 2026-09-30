#!/usr/bin/env bash
# Real mysqli query with PDO disabled, against an isolated temporary MariaDB.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
for dependency in mariadbd mariadb-install-db mariadb php python3; do
    command -v "$dependency" >/dev/null || { echo "db-linux live test skipped: $dependency missing"; exit 0; }
done
php -n -d extension=mysqlnd -d extension=mysqli -d extension=ctype -r 'exit(class_exists("mysqli") && !class_exists("PDO") ? 0 : 1);' 2>/dev/null || { echo 'db-linux live test skipped: PHP mysqli-only runtime unavailable'; exit 0; }
./compile.sh >/dev/null
tmpdir=$(mktemp -d /tmp/opencode/plak-db-test.XXXXXX)
server_pid=""
trap '[ -z "$server_pid" ] || { kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; }; rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"
mkdir -p "$HOME/.local/bin" "$tmpdir/data"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
mariadb-install-db --no-defaults --datadir="$tmpdir/data" --auth-root-authentication-method=normal > "$tmpdir/init.log" 2>&1
mariadbd --no-defaults --datadir="$tmpdir/data" --socket="$tmpdir/mysql.sock" --port="$port" --bind-address=127.0.0.1 --pid-file="$tmpdir/mysql.pid" > "$tmpdir/server.log" 2>&1 &
server_pid=$!
for _ in {1..50}; do
    if mariadb --no-defaults --socket="$tmpdir/mysql.sock" -u root -e 'SELECT 1' >/dev/null 2>&1; then break; fi
    sleep 0.1
done
mariadb --no-defaults --socket="$tmpdir/mysql.sock" -u root -e "CREATE DATABASE actual_site; CREATE TABLE actual_site.t (n INT); INSERT INTO actual_site.t VALUES (1); CREATE USER 'plak_test'@'127.0.0.1' IDENTIFIED BY 'testpass'; GRANT ALL ON actual_site.* TO 'plak_test'@'127.0.0.1';"
export TEST_DB_PORT="$port"
cat > "$HOME/.local/bin/frankenphp" <<'FRANK'
#!/usr/bin/env bash
set -euo pipefail
shift
if [ "$1" = -r ]; then
    exec php -n -d extension=mysqlnd -d extension=mysqli -d extension=ctype "$@"
fi
shift # Fake WP entry point, retaining real mysqli for the listing itself.
[ "${1:-}" != --allow-root ] || shift
case "$3" in
    DB_NAME) echo actual_site ;;
    DB_USER) echo plak_test ;;
    DB_PASSWORD) echo "${TEST_DB_PASSWORD:-testpass}" ;;
    DB_HOST) echo "127.0.0.1:$TEST_DB_PORT" ;;
    *) exit 1 ;;
esac
FRANK
printf '#!/usr/bin/env php\n<?php\n' > "$HOME/.local/bin/wp"
chmod +x "$HOME/.local/bin/"*
export PATH="$HOME/.local/bin:$PATH" PLAK_NO_PATH_PRELUDE=1
source ./plak.sh >/dev/null
mkdir -p "$SITES_DIR/demo.localhost/public"
touch "$SITES_DIR/demo.localhost/public/wp-config.php"
printf "DB_USER='unused'\nDB_PASSWORD='unused'\nDB_HOST='unreachable.invalid'\nDB_PORT='1'\n" > "$CONFIG_FILE"
plak_site_db_list --json > "$tmpdir/result"
python3 - "$tmpdir/result" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert len(r)==1
assert r[0]['name']=='demo' and r[0]['db_name']=='actual_site'
assert r[0]['db_user']=='plak_test' and r[0]['size']!='N/A'
PY
export TEST_DB_PASSWORD=incorrect
if plak_site_db_list --json > "$tmpdir/result" 2> "$tmpdir/error"; then exit 1; fi
grep -q 'connection/query failed' "$tmpdir/error"
[ ! -s "$tmpdir/result" ]
echo 'mysqli without PDO live database tests passed'
