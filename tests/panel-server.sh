#!/usr/bin/env bash
# CLI-42: panel Fase C server operations.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect commands/connect commands/panel commands/panel-server commands/panel-write shared/ui shared/validate; do bash -n "$f"; done

tmpdir=$(mktemp -d)
server_pid=""
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmpdir"
}
trap cleanup EXIT

export PLAK_NO_PATH_PRELUDE=1
export HOME="$tmpdir/home"
mkdir -p "$HOME"
export PLAK_HOME="$HOME/.plak"
source ./plak.sh >/dev/null

fail() { echo "panel-server test failed: $1" >&2; exit 1; }

cat > "$tmpdir/stub.py" <<'PY'
import http.server, json, urllib.parse
WRITE = "srv-test-token"
SRV = "9"
STATE = {"wpcli": False}
class H(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def _auth(self, write=False):
        auth = self.headers.get("Authorization", "")
        if auth != "Bearer " + WRITE and auth != "Bearer ro-token":
            return "bad"
        if write and auth != "Bearer " + WRITE:
            return "ro"
        return "ok"
    def do_GET(self):
        a = self._auth()
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        tail = urllib.parse.urlsplit(self.path).path
        if tail == "/api/v1/servers":
            self._json(200, {"current_page": 1, "per_page": 100, "total": 1, "last_page": 1,
                             "data": [{"id": 9, "name": "web-9", "status": "active"}]})
        elif tail == "/api/v1/servers/9":
            self._json(200, {"data": {"id": 9, "name": "web-9", "wp_cli_installed": STATE["wpcli"]}})
        elif tail == "/api/v1/servers/9/services":
            self._json(200, {"data": [{"name": "nginx", "status": "running", "can_restart": True, "can_reload": True}]})
        elif tail == "/api/v1/servers/9/php":
            self._json(200, {"data": {"server_id": 9, "current_php_version": "8.2", "opcache_enabled": True}})
        elif tail == "/api/v1/servers/9/firewall":
            self._json(200, {"data": [{"id": 5, "name": "ssh", "port": 22}]})
        elif tail == "/api/v1/servers/9/system-users":
            self._json(200, {"data": [{"id": 1, "ploi_id": 50, "name": "plak", "root": False, "sudo": False, "sites_count": 0}]})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def _tail(self):
        return urllib.parse.urlsplit(self.path).path
    def do_POST(self):
        a = self._auth(write=True)
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        if a == "ro":
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        tail = self._tail()
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}") if length else {}
        if "/services/" in tail and tail.endswith("/restart"):
            svc = tail.split("/services/")[1].split("/restart")[0]
            if svc == "dead":
                self._json(422, {"code": "service.not_running", "message": "Not running.", "hint": ""})
            else:
                self._json(200, {"data": {"service": svc, "restarted": True}})
        elif "/services/" in tail and tail.endswith("/reload"):
            svc = tail.split("/services/")[1].split("/reload")[0]
            self._json(200, {"data": {"service": svc, "reloaded": True}})
        elif tail.endswith("/wp-cli/install"):
            STATE["wpcli"] = True
            self._json(200, {"data": {"wp_cli_installed": True}})
        elif tail.endswith("/php/install"):
            self._json(200, {"data": {"version": body.get("version"), "status": "installing"}})
        elif tail.endswith("/php/cli-version"):
            self._json(200, {"data": {"php_cli_version": body.get("version"), "switched": True}})
        elif tail.endswith("/php/opcache/enable"):
            self._json(200, {"data": {"opcache": "enabled"}})
        elif tail.endswith("/php/opcache/refresh"):
            self._json(422, {"code": "opcache.rejected", "message": "Disabled.", "hint": ""})
        elif tail.endswith("/firewall"):
            self._json(201, {"data": {"id": 6, "name": body.get("name"), "port": body.get("port")}})
        elif tail.endswith("/system-users"):
            self._json(201, {"data": {"id": 2, "ploi_id": 51, "name": body.get("name"), "password": "once-secret"}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_DELETE(self):
        a = self._auth(write=True)
        if a == "ro":
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        tail = self._tail()
        if tail.endswith("/wp-cli/uninstall"):
            STATE["wpcli"] = False
            self._json(200, {"data": {"wp_cli_installed": False}})
        elif tail.endswith("/php/opcache/disable"):
            self._json(200, {"data": {"opcache": "disabled"}})
        elif "/firewall/" in tail:
            rid = tail.rsplit("/", 1)[1]
            if rid == "99":
                self._json(404, {"code": "firewall.not_found", "message": "Not found.", "hint": ""})
            else:
                self._json(200, {"data": {"deleted": True}})
        elif "/system-users/" in tail:
            rid = tail.rsplit("/", 1)[1]
            if rid == "ploi":
                self._json(422, {"code": "system_user.protected", "message": "Protected.", "hint": ""})
            else:
                self._json(200, {"data": {"deleted": True}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18999), H).serve_forever()
PY
PORT=$(( (RANDOM % 2000) + 21000 ))
sed -i "s/18999/$PORT/" "$tmpdir/stub.py"
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 "http://127.0.0.1:$PORT/api/v1/servers" >/dev/null 2>&1 && break; sleep 0.1; done

PANEL="http://127.0.0.1:$PORT"
seed_conn() {
    python3 - "$1" <<PY
import json, sys
json.dump({"panel_url": "$PANEL", "token": sys.argv[1],
           "user": {"id": 1, "name": "T", "email": "t@example.test"},
           "saved_at": "2026-01-01T00:00:00+00:00"},
          open("$PLAK_HOME/connection.json", "w"))
PY
}
mkdir -p "$PLAK_HOME" && chmod 700 "$PLAK_HOME"
seed_conn "srv-test-token"
chmod 600 "$PLAK_HOME/connection.json"

# --- services ---
./plak.sh panel service-list web-9 > "$tmpdir/svc.txt" || fail "service-list"
grep -q nginx "$tmpdir/svc.txt" || fail "services rows"
./plak.sh panel service-restart web-9 nginx --yes --json > "$tmpdir/fp1.out" || fail "service-restart"
grep -q restarted "$tmpdir/fp1.out" || fail "service-restart output"
./plak.sh panel service-reload web-9 mysql --yes --json > "$tmpdir/fp2.out" || fail "service-reload"
grep -q reloaded "$tmpdir/fp2.out" || fail "service-reload output"
./plak.sh panel service-restart web-9 dead --yes 2>/dev/null && fail "not-running accepted"
./plak.sh panel service-restart web-9 nginx 2>/dev/null && fail "restart without --yes"

# --- wpcli ---
./plak.sh panel wpcli-install web-9 --poll 1 --wait 15 --json > "$tmpdir/wpi.json" || fail "wpcli-install"
grep -q '"wp_cli_installed": true' "$tmpdir/wpi.json" || fail "wpcli-install json"
./plak.sh panel wpcli-uninstall web-9 --yes --json > "$tmpdir/wpu.json" || fail "wpcli-uninstall"
grep -q '"wp_cli_installed": false' "$tmpdir/wpu.json" || fail "wpcli-uninstall json"

# --- php/opcache ---
./plak.sh panel php-info web-9 > "$tmpdir/php.txt" || fail "php-info"
grep -q 8.2 "$tmpdir/php.txt" || fail "php rows"
./plak.sh panel php-install web-9 --version 8.5 --yes --json > "$tmpdir/fp3.out" || fail "php-install"
grep -q installing "$tmpdir/fp3.out" || fail "php-install output"
./plak.sh panel php-cli-set web-9 --version 8.4 --json > "$tmpdir/fp4.out" || fail "php-cli-set"
grep -q switched "$tmpdir/fp4.out" || fail "php-cli-set output"
./plak.sh panel opcache-enable web-9 --yes --json > "$tmpdir/fp5.out" || fail "opcache-enable"
grep -q enabled "$tmpdir/fp5.out" || fail "opcache-enable output"
./plak.sh panel opcache-disable web-9 --yes --json > "$tmpdir/fp6.out" || fail "opcache-disable"
grep -q disabled "$tmpdir/fp6.out" || fail "opcache-disable output"
./plak.sh panel opcache-refresh web-9 --yes 2>/dev/null && fail "opcache-refresh accepted"

# --- firewall ---
./plak.sh panel firewall-list web-9 > "$tmpdir/fw.txt" || fail "firewall-list"
grep -q ssh "$tmpdir/fw.txt" || fail "firewall rows"
./plak.sh panel firewall-add web-9 --name http --port 80 --type tcp --rule allow --yes --json > "$tmpdir/fp7.out" || fail "firewall-add"
grep -q http "$tmpdir/fp7.out" || fail "firewall-add output"
./plak.sh panel firewall-del web-9 5 --yes --json > "$tmpdir/fp8.out" || fail "firewall-del"
grep -q deleted "$tmpdir/fp8.out" || fail "firewall-del output"
./plak.sh panel firewall-del web-9 99 --yes 2>/dev/null && fail "firewall not-found accepted"

# --- system users ---
./plak.sh panel users-list web-9 > "$tmpdir/us.txt" || fail "users-list"
grep -q plak "$tmpdir/us.txt" || fail "users rows"
./plak.sh panel users-add web-9 --name deploy --sudo --json > "$tmpdir/uadd.json" || fail "users-add"
grep -q once-secret "$tmpdir/uadd.json" || fail "users-add shows secret once"
./plak.sh panel users-del web-9 2 --yes --json > "$tmpdir/udel.json" || fail "users-del"
grep -q deleted "$tmpdir/udel.json" || fail "users-del json"
./plak.sh panel users-del web-9 ploi --yes 2>/dev/null && fail "ploi delete accepted"

# --- read-only denied ---
seed_conn "ro-token"
./plak.sh panel service-restart web-9 nginx --yes 2>/dev/null && fail "ro-token accepted"

echo "panel-server tests passed"
