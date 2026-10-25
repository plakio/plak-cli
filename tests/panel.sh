#!/usr/bin/env bash
# CLI-25: plak panel reads own sites/servers, never other accounts' data.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect commands/connect commands/panel; do bash -n "$f"; done

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

fail() { echo "panel test failed: $1" >&2; exit 1; }

# --- not connected ---
./plak.sh panel sites 2>/dev/null && fail "sites without connection"
./plak.sh panel servers 2>/dev/null && fail "servers without connection"

cat > "$tmpdir/stub.py" <<'PY'
import http.server, json, urllib.parse
TOKEN = "panel-test-token"
SITES = [
    {"id": 11, "domain": "a.example", "status": "active", "project": "wordpress",
     "php_version": "8.4", "server_id": 5,
     "server": {"id": 5, "name": "web-1", "status": "active"},
     "created_at": "2026-01-01T00:00:00.000000Z"},
    {"id": 12, "domain": "b.example", "status": "active", "project": "wordpress",
     "php_version": "8.4", "server_id": None, "server": None,
     "created_at": "2026-01-01T00:00:00.000000Z"},
    {"id": 13, "domain": "c.example", "status": "busy", "project": "wordpress",
     "php_version": "8.3", "server_id": 5,
     "server": {"id": 5, "name": "web-1", "status": "active"},
     "created_at": "2026-01-01T00:00:00.000000Z"},
]
SERVERS = [
    {"id": 5, "name": "web-1", "status": "active", "ip": "203.0.113.10",
     "os": "ubuntu-24-04-lts", "type": "server", "php_version": "8.4",
     "sites": [{"id": 11, "domain": "a.example"}, {"id": 13, "domain": "c.example"}],
     "created_at": "2026-01-01T00:00:00.000000Z"},
    {"id": 6, "name": "db-1", "status": "active", "ip": None,
     "os": "ubuntu-24-04-lts", "type": "database-server", "php_version": "8.4",
     "sites": [], "created_at": "2026-01-01T00:00:00.000000Z"},
]
class H(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def _auth(self):
        return self.headers.get("Authorization", "") == "Bearer " + TOKEN
    def do_GET(self):
        if not self._auth():
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        url = urllib.parse.urlsplit(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        parts = url.path.strip("/").split("/")
        # /api/v1/<kind>[/<id>]
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "v1":
            kind, items = parts[2], None
            items = SITES if kind == "sites" else SERVERS if kind == "servers" else None
            if items is None:
                self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
                return
            per = max(1, min(100, int(q.get("per_page", 25))))
            page = max(1, int(q.get("page", 1)))
            total, last = len(items), max(1, -(-len(items) // per))
            self._json(200, {"current_page": page, "per_page": per, "total": total,
                             "last_page": last, "data": items[(page - 1) * per:page * per]})
            return
        if len(parts) == 4 and parts[0] == "api" and parts[1] == "v1":
            kind, rid = parts[2], parts[3]
            items = SITES if kind == "sites" else SERVERS if kind == "servers" else None
            if items is None:
                self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
                return
            hit = next((i for i in items if str(i["id"]) == rid), None)
            if hit is None:
                self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
                return
            self._json(200, {"data": hit})
            return
        self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18994), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do
    curl -s -m 2 http://127.0.0.1:18994/api/v1/sites >/dev/null 2>&1 && break
    sleep 0.1
done

PANEL="http://127.0.0.1:18994"
mkdir -p "$PLAK_HOME"
chmod 700 "$PLAK_HOME"
python3 - "$PLAK_HOME/connection.json" <<PY
import json
json.dump({"panel_url": "$PANEL", "token": "panel-test-token",
           "user": {"id": 1, "name": "T", "email": "t@example.test"},
           "saved_at": "2026-01-01T00:00:00+00:00"},
          open("$PLAK_HOME/connection.json", "w"))
PY
chmod 600 "$PLAK_HOME/connection.json"

# --- list + pagination hint ---
./plak.sh panel sites --per-page 2 > "$tmpdir/sites.txt" || fail "sites list"
grep -q "a.example" "$tmpdir/sites.txt" || fail "sites rows"
grep -q -- "--all" "$tmpdir/sites.txt" || fail "pagination hint"

# --- --all walks every page, JSON carries no secret ---
./plak.sh panel sites --all --json > "$tmpdir/all.json" || fail "sites all"
python3 - "$tmpdir/all.json" <<'PY' || fail "all json"
import json, sys
d = json.load(open(sys.argv[1]))
assert [s["domain"] for s in d] == ["a.example", "b.example", "c.example"], d
assert "panel-test-token" not in open(sys.argv[1]).read()
PY

# --- selection by id, domain, and misses ---
./plak.sh panel site 12 > "$tmpdir/one.txt" || fail "site by id"
grep -q "b.example" "$tmpdir/one.txt" || fail "site id row"
./plak.sh panel site c.example --json > "$tmpdir/c.json" || fail "site by domain"
grep -q '"domain": "c.example"' "$tmpdir/c.json" || fail "domain json"
./plak.sh panel site 999 2>/dev/null && fail "foreign id accepted"
./plak.sh panel site nope.example 2>/dev/null && fail "foreign domain accepted"

# --- servers ---
./plak.sh panel servers --all > "$tmpdir/servers.txt" || fail "servers"
grep -q "web-1" "$tmpdir/servers.txt" || fail "servers rows"
grep -q "db-1" "$tmpdir/servers.txt" || fail "servers second page walked"
./plak.sh panel server web-1 --json > "$tmpdir/srv.json" || fail "server by name"
grep -q '"ip": "203.0.113.10"' "$tmpdir/srv.json" || fail "server json"

# --- saved token never goes to another origin ---
./plak.sh panel sites --panel http://127.0.0.1:9 2>/dev/null && fail "cross-origin allowed"

# --- revoked token hints reconnect, keeps local file for explicit disconnect ---
python3 - "$PLAK_HOME/connection.json" <<PY
import json
p = "$PLAK_HOME/connection.json"
d = json.load(open(p))
d["token"] = "revoked"
json.dump(d, open(p, "w"))
PY
./plak.sh panel sites 2>"$tmpdir/revoked.txt" >/dev/null && fail "revoked accepted"
grep -q "reconnect" "$tmpdir/revoked.txt" || fail "revoked hint"

echo "panel tests passed"
