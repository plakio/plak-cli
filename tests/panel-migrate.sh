#!/usr/bin/env bash
# CLI-27: panel revalidation gates push/pull on linked sites, manual flow untouched.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect shared/panel-migrate commands/panel-link shared/remote shared/ui shared/validate; do bash -n "$f"; done

tmpdir=$(mktemp -d)
server_pid=""
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmpdir"
}
trap cleanup EXIT

export PLAK_NO_PATH_PRELUDE=1
export HOME="$tmpdir/home"
mkdir -p "$HOME/.ssh" "$HOME/Plak/Sites/myshop.localhost"
export PLAK_HOME="$HOME/.plak"
export PLAK_SSH_CONFIG="$HOME/.ssh/config"
source ./plak.sh >/dev/null

fail() { echo "panel-migrate test failed: $1" >&2; exit 1; }

cat > "$tmpdir/stub.py" <<'PY'
import http.server, json
TOKEN = "migrate-test-token"
DOMAIN = {"value": "shop.example", "gone": False}
class H(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        if self.headers.get("Authorization", "") != "Bearer " + TOKEN:
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        if self.path == "/api/v1/sites/21":
            if DOMAIN["gone"]:
                self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
            else:
                self._json(200, {"data": {"id": 21, "domain": DOMAIN["value"]}})
        elif self.path == "/api/v1/sites/22":
            self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
        else:
            self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
    def do_POST(self):
        if self.path == "/api/v1/test/domain":
            DOMAIN["value"] = "renamed.example"
            self._json(200, {})
        elif self.path == "/api/v1/test/gone":
            DOMAIN["gone"] = True
            self._json(200, {})
        elif self.path == "/api/v1/test/reset":
            DOMAIN.update(value="shop.example", gone=False)
            self._json(200, {})
        else:
            self._json(404, {})
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18996), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 http://127.0.0.1:18996/api/v1/sites/21 >/dev/null 2>&1 && break; sleep 0.1; done

PANEL="http://127.0.0.1:18996"
mkdir -p "$PLAK_HOME" && chmod 700 "$PLAK_HOME"
python3 <<PY
import json
json.dump({"panel_url": "$PANEL", "token": "migrate-test-token",
           "user": {"id": 1, "name": "T", "email": "t@example.test"},
           "saved_at": "2026-01-01T00:00:00+00:00"},
          open("$PLAK_HOME/connection.json", "w"))
PY
chmod 600 "$PLAK_HOME/connection.json"

SITES_DIR="$HOME/Plak/Sites"
printf 'panel-shop\n' > "$SITES_DIR/myshop.localhost/.remote"
python3 - "$tmpdir" <<'PY'
import json, sys
tmpdir = sys.argv[1]
json.dump({"panel_url": "http://127.0.0.1:18996", "account": "t@example.test",
           "site": {"id": 21, "domain": "shop.example"},
           "server": {"id": 9, "name": "web-9"}, "remote": "panel-shop",
           "local_site": "myshop", "linked_at": "2026-01-01T00:00:00+00:00"},
          open(tmpdir + "/home/Plak/Sites/myshop.localhost/.panel-link", "w"))
PY

# --- 1. valid link revalidates and names the real destination ---
out=$(plak_panel_revalidate_link myshop) || fail "valid link stopped"
grep -q "shop.example" <<<"$out" || fail "destination not shown"

# --- 2. manual site (no link) proceeds silently ---
mkdir -p "$SITES_DIR/static.localhost"
[ -z "$(plak_panel_revalidate_link static)" ] || fail "manual flow noisy"

# --- 3. account change stops ---
python3 - "$tmpdir" <<'PY'
import json, sys
p = sys.argv[1] + "/home/Plak/Sites/myshop.localhost/.panel-link"
d = json.load(open(p)); d["account"] = "someone@else.test"; json.dump(d, open(p, "w"))
PY
plak_panel_revalidate_link myshop 2>/dev/null && fail "account change passed"
python3 - "$tmpdir" <<'PY'
import json, sys
p = sys.argv[1] + "/home/Plak/Sites/myshop.localhost/.panel-link"
d = json.load(open(p)); d["account"] = "t@example.test"; json.dump(d, open(p, "w"))
PY

# --- 4. remote alias swapped stops (no silent other destination) ---
printf 'other-remote\n' > "$SITES_DIR/myshop.localhost/.remote"
plak_panel_revalidate_link myshop 2>/dev/null && fail "remote swap passed"
printf 'panel-shop\n' > "$SITES_DIR/myshop.localhost/.remote"

# --- 5. withdrawn site (404) stops ---
curl -s -m 5 -X POST http://127.0.0.1:18996/api/v1/test/gone >/dev/null
plak_panel_revalidate_link myshop 2>/dev/null && fail "withdrawn passed"
curl -s -m 5 -X POST http://127.0.0.1:18996/api/v1/test/reset >/dev/null

# --- 6. renamed remotely stops instead of migrating the wrong site ---
curl -s -m 5 -X POST http://127.0.0.1:18996/api/v1/test/domain >/dev/null
plak_panel_revalidate_link myshop 2>/dev/null && fail "rename passed"
curl -s -m 5 -X POST http://127.0.0.1:18996/api/v1/test/reset >/dev/null

# --- 7. revoked token stops with reconnect hint ---
python3 - "$PLAK_HOME/connection.json" <<PY
import json
p = "$PLAK_HOME/connection.json"
d = json.load(open(p)); d["token"] = "revoked"; json.dump(d, open(p, "w"))
PY
plak_panel_revalidate_link myshop 2>"$tmpdir/revoked.txt" >/dev/null && fail "revoked passed"
grep -q "reconnect" "$tmpdir/revoked.txt" || fail "revoked hint"

echo "panel-migrate tests passed"
