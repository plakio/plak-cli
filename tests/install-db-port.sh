#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "install db-port regression test failed: $1" >&2
    exit 1
}

source ./plak.sh >/dev/null

# --- db_port_is_mariadb uses a connection probe, not the process name ---
# Stub mysqladmin to answer only on the configured port.
bin="$tmpdir/bin"
mkdir -p "$bin"
cat > "$bin/mysqladmin" <<'MYSQLADMIN'
#!/usr/bin/env bash
port=""
prev=""
for arg in "$@"; do
    [ "$prev" = "-P" ] && port="$arg"
    prev="$arg"
done
[ "$port" = "3306" ] && exit 0
exit 1
MYSQLADMIN
chmod +x "$bin/mysqladmin"
export PATH="$bin:$PATH"

# Simulate the WSL2 case: 3306 is busy but its process is invisible (port name
# comes back empty), which used to be misread as a foreign conflict.
port_listening_app() { echo ""; }
port_is_free() { [ "$1" = "3306" ] && return 1; return 0; }

DB_PORT=3306
if db_port_has_conflict 3306; then
    fail "own MariaDB on the configured port was reported as a conflict"
fi

# A non-configured port busy with a foreign process is still a conflict: we only
# forgive the port Plak is actually configured to use.
port_is_free() { { [ "$1" = "3306" ] || [ "$1" = "3307" ]; } && return 1; return 0; }
port_listening_app() { [ "$1" = "3307" ] && { echo "someservice"; return; }; echo ""; }
DB_PORT=3306
if ! db_port_has_conflict 3307; then
    fail "a foreign process on a candidate port was wrongly forgiven"
fi
port_listening_app() { echo ""; }
port_is_free() { [ "$1" = "3306" ] && return 1; return 0; }

# A port with nobody listening is free.
if db_port_has_conflict 3399; then
    fail "a free port was reported as a conflict"
fi

# A foreign, non-MariaDB process on the configured port stays a real conflict.
port_is_free() { [ "$1" = "3310" ] && return 1; return 0; }
port_listening_app() { echo "redis"; }
DB_PORT=3310
if ! db_port_has_conflict 3310; then
    fail "a foreign process on the configured port was not flagged"
fi

# --- The readiness loop reports the real error, not the SSL warning ---
# Confirm the install command filters the SSL warning and mentions the port.
grep -q 'MariaDB did not become available on' commands/site/install || fail "timeout message lacks the host/port"
grep -q "ssl-verify-server-cert" commands/site/install || fail "timeout path does not filter the SSL warning"

# --- A real conflict never offers a free-but-empty alternative port ---
# The install flow must not hand out a port where no MariaDB answers (that was
# the CLI-29 failure); it aborts with actionable guidance instead.
grep -q "Plak does not reconfigure an existing MariaDB server" commands/site/install \
    || fail "conflict path does not explain that MariaDB is not moved"
if grep -q 'Use alternative port (3307)' commands/site/install; then
    fail "conflict path still offers an empty alternative port"
fi
if grep -q 'prompt_custom_db_port' plak.sh; then
    fail "dead custom-db-port prompt is still referenced"
fi

echo "Install db-port regression tests passed."
