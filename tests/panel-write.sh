#!/usr/bin/env bash
# CLI-40: panel Fase A writes (providers, servers/sites create/delete/restart).
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect commands/connect commands/panel commands/panel-write shared/ui shared/validate; do bash -n "$f"; done

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

fail() { echo "panel-write test failed: $1" >&2; exit 1; }

./plak.sh panel providers 2>/dev/null && fail "providers without connection"

cat > "$tmpdir/stub.py" <<'PY'
import http.server, json, urllib.parse
WRITE = "write-test-token"
state = {"server_polls": 0, "site_polls": 0}
class H(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def _auth(self):
        return self.headers.get("Authorization", "")
    def do_GET(self):
        auth = self._auth()
        if auth != "Bearer " + WRITE:
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        url = urllib.parse.urlsplit(self.path)
        if url.path == "/api/v1/providers":
            self._json(200, {"data": [{"id": 1, "name": "Hetzner",
                                       "regions": [{"id": 2, "label": "Falkenstein"}],
                                       "plans": [{"id": 3, "label": "CX22"}]}]})
        elif url.path == "/api/v1/servers/7":
            state["server_polls"] += 1
            status = "active" if state["server_polls"] >= 2 else "busy"
            self._json(200, {"data": {"id": 7, "name": "web-7", "status": status}})
        elif url.path == "/api/v1/servers/9":
            self._json(200, {"data": {"id": 9, "name": "web-9", "status": "active"}})
        elif url.path == "/api/v1/servers":
            self._json(200, {"current_page": 1, "per_page": 100, "total": 1, "last_page": 1,
                             "data": [{"id": 9, "name": "web-9", "status": "active"}]})
        elif url.path == "/api/v1/sites/12":
            state["site_polls"] += 1
            status = "active" if state["site_polls"] >= 2 else "busy"
            self._json(200, {"data": {"id": 12, "domain": "shop.example", "status": status}})
        elif url.path == "/api/v1/sites":
            self._json(200, {"current_page": 1, "per_page": 100, "total": 1, "last_page": 1,
                             "data": [{"id": 12, "domain": "shop.example", "status": "active"}]})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_POST(self):
        auth = self._auth()
        if auth == "Bearer ro-token":
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        if auth != "Bearer " + WRITE:
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        url = urllib.parse.urlsplit(self.path).path
        if url == "/api/v1/servers":
            if body.get("provider_id") == 99:
                self._json(404, {"code": "servers.provider_invalid", "message": "Bad provider.", "hint": ""})
            elif body.get("name") == "full":
                self._json(422, {"code": "servers.limit_reached", "message": "Limit.", "hint": ""})
            else:
                state["server_polls"] = 0
                self._json(202, {"data": {"id": 7, "status": "busy"}})
        elif url == "/api/v1/servers/9/restart":
            self._json(200, {"data": {"id": 9, "restarted": True}})
        elif url == "/api/v1/sites":
            if body.get("domain") == "taken.example":
                self._json(422, {"code": "site.domain_taken", "message": "Taken.", "hint": ""})
            elif body.get("server_id") == 8:
                self._json(422, {"code": "server.not_ready", "message": "Not ready.", "hint": ""})
            else:
                state["site_polls"] = 0
                self._json(201, {"data": {"id": 12, "domain": body["domain"], "status": "busy"}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_DELETE(self):
        if self._auth() != "Bearer " + WRITE:
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        url = urllib.parse.urlsplit(self.path).path
        if url in ("/api/v1/servers/9", "/api/v1/sites/12"):
            rid = url.rsplit("/", 1)[1]
            self._json(200, {"data": {"id": int(rid), "deleted": True}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18997), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 http://127.0.0.1:18997/api/v1/providers >/dev/null 2>&1 && break; sleep 0.1; done

PANEL="http://127.0.0.1:18997"
mkdir -p "$PLAK_HOME" && chmod 700 "$PLAK_HOME"
seed_conn() {
    python3 - "$1" <<PY
import json, sys
json.dump({"panel_url": "$PANEL", "token": sys.argv[1],
           "user": {"id": 1, "name": "T", "email": "t@example.test"},
           "saved_at": "2026-01-01T00:00:00+00:00"},
          open("$PLAK_HOME/connection.json", "w"))
PY
    chmod 600 "$PLAK_HOME/connection.json"
}
seed_conn "write-test-token"

# --- providers ---
./plak.sh panel providers > "$tmpdir/providers.txt" || fail "providers"
grep -q "Hetzner" "$tmpdir/providers.txt" || fail "providers rows"
grep -q "Falkenstein" "$tmpdir/providers.txt" || fail "providers regions"

# --- create-server async -> active, no secret in json ---
./plak.sh panel create-server --name web-7 --provider 1 --region 2 --plan 3 --poll 1 --wait 30 --json > "$tmpdir/created.json" || fail "create-server"
python3 - "$tmpdir/created.json" <<'PY' || fail "created json"
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {"created": True, "id": 7, "status": "active"}, d
assert "write-test-token" not in open(sys.argv[1]).read()
PY

# --- create-server error paths ---
./plak.sh panel create-server --name w --provider 99 --region 2 --plan 3 2>/dev/null && fail "bad provider accepted"
./plak.sh panel create-server --name full --provider 1 --region 2 --plan 3 2>/dev/null && fail "limit accepted"

# --- read-only token gets scope guidance, not a silent failure ---
seed_conn "ro-token"
./plak.sh panel create-server --name w --provider 1 --region 2 --plan 3 2>"$tmpdir/scope.txt" >/dev/null && fail "ro-token accepted"
grep -q "write scope" "$tmpdir/scope.txt" || fail "scope hint"
seed_conn "write-test-token"

# --- restart + delete need --yes without TTY, then work ---
./plak.sh panel restart-server 9 2>/dev/null && fail "restart without --yes"
./plak.sh panel restart-server web-9 --yes --json > "$tmpdir/restart.json" || fail "restart"
grep -q '"restarted":true' "$tmpdir/restart.json" || fail "restart json"
./plak.sh panel delete-server 404 2>/dev/null && fail "delete missing accepted"
./plak.sh panel delete-server web-9 --yes --json > "$tmpdir/del.json" || fail "delete-server"
grep -q '"deleted":true' "$tmpdir/del.json" || fail "delete json"

# --- create-site async + error paths + delete ---
./plak.sh panel create-site --domain shop.example --server 9 --poll 1 --wait 30 --json > "$tmpdir/site.json" || fail "create-site"
grep -q '"status":"active"' "$tmpdir/site.json" || fail "site active"
./plak.sh panel create-site --domain taken.example --server 9 2>/dev/null && fail "taken accepted"
./plak.sh panel create-site --domain x.example --server 8 2>/dev/null && fail "not-ready accepted"
./plak.sh panel delete-site shop.example --yes --json > "$tmpdir/delsite.json" || fail "delete-site"
grep -q '"deleted":true' "$tmpdir/delsite.json" || fail "delete-site json"

echo "panel-write tests passed"
