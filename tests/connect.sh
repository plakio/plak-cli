#!/usr/bin/env bash
# CLI-24: plak connect device flow + manual fallback + storage safety.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect commands/connect; do bash -n "$f"; done

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

fail() { echo "connect test failed: $1" >&2; exit 1; }

# --- URL handling ---
[ "$(plak_connect_normalize_url 'https://panel.plak.work/')" = "https://panel.plak.work" ] || fail "trailing slash"
plak_connect_normalize_url 'ftp://x' 2>/dev/null && fail "non-http accepted"
[ "$(plak_connect_resolve_panel)" = "https://panel.plak.work" ] || fail "prod default"
[ "$(plak_connect_resolve_panel --panel 'https://staging.example/')" = "https://staging.example" ] || fail "explicit panel"
PLAK_PANEL_DEV_URL="http://127.0.0.1:9" plak_connect_resolve_panel --dev >/dev/null || fail "dev resolve"

# --- secret never via argv ---
./plak.sh connect --manual --panel https://panel.plak.work --token abc 2>/dev/null && fail "--token accepted"

# --- stub panel: pair -> pending x1 -> approved; user 401 until approved ---
cat > "$tmpdir/stub.py" <<'PY'
import http.server, json
state = {"polls": 0, "approved": False}
class H(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        if self.path == "/api/v1/cli/pair":
            length = int(self.headers.get("Content-Length", 0))
            self.rfile.read(length)
            self._json(201, {"pending_token": "test-pending-token",
                             "pairing_code": "TESTCODE1",
                             "approve_url": "http://127.0.0.1:18993/cli/approve/TESTCODE1",
                             "expires_at": "2030-01-01T00:00:00.000000Z"})
        else:
            self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        if self.path == "/api/v1/cli/pair/status":
            if auth != "Bearer test-pending-token":
                self._json(401, {"code": "pairing_token.invalid", "message": "x", "hint": "y"})
                return
            state["polls"] += 1
            if state["polls"] >= 2:
                state["approved"] = True
            self._json(200, {"status": "approved" if state["approved"] else "pending",
                             "scopes": ["user:read"] if state["approved"] else [],
                             "expires_at": "2030-01-01T00:00:00.000000Z"})
        elif self.path == "/api/v1/user":
            if auth == "Bearer test-pending-token" and state["approved"]:
                self._json(200, {"data": {"id": 7, "name": "Stub", "email": "stub@example.test",
                                          "capabilities": ["user:read"]}})
            else:
                self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
        elif self.path == "/access-page":
            body = b"<html>Cloudflare Access login</html>"
            self.send_response(403)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18993), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do
    curl -fsS http://127.0.0.1:18993/access-page >/dev/null 2>&1 || true
    curl -s -m 2 http://127.0.0.1:18993/access-page >/dev/null 2>&1 && break
    sleep 0.1
done

PANEL="http://127.0.0.1:18993"

# --- device flow approves after polls, saves with strict perms ---
./plak.sh connect --panel "$PANEL" --no-open --poll 1 --wait 30 >/dev/null || fail "device flow"
[ "$(stat -c %a "$PLAK_HOME")" = "700" ] || fail "dir perms"
[ "$(stat -c %a "$PLAK_HOME/connection.json")" = "600" ] || fail "file perms"
python3 - "$PLAK_HOME/connection.json" <<'PY' || fail "stored doc"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["panel_url"].startswith("http://127.0.0.1"), d
assert d["token"] == "test-pending-token"
assert d["user"]["email"] == "stub@example.test"
PY

# --- status JSON carries no secret ---
./plak.sh connect status --json > "$tmpdir/status.json" || fail "status"
python3 - "$tmpdir/status.json" <<'PY' || fail "status json"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["connected"] is True and r["user"]["email"] == "stub@example.test"
assert "test-pending-token" not in open(sys.argv[1]).read()
PY
./plak.sh connect status > "$tmpdir/status.txt" || fail "status text"
grep -q "test-pending-token" "$tmpdir/status.txt" && fail "secret in status text"

# --- invalid manual key keeps the working connection ---
printf 'bogus|token' | ./plak.sh connect --manual --panel "$PANEL" --token-stdin 2>/dev/null && fail "bogus accepted"
./plak.sh connect status >/dev/null || fail "good connection lost after bogus"

# --- HTML access page is detected, not treated as API ---
source ./plak.sh >/dev/null
plak_connect_http GET "$PANEL/access-page" "" "" "" || fail "http helper"
[ "$PLAK_HTTP_STATUS" = "403" ] || fail "stub status"
plak_connect_is_access_block "$PLAK_HTTP_STATUS" "$PLAK_HTTP_BODY" || fail "access not detected"

# --- disconnect needs --yes without TTY, then forgets locally ---
printf '' | ./plak.sh disconnect 2>/dev/null && fail "disconnect without --yes"
./plak.sh disconnect --yes >/dev/null || fail "disconnect"
[ ! -f "$PLAK_HOME/connection.json" ] || fail "credential remains"
./plak.sh connect status 2>/dev/null && fail "status after disconnect"

echo "connect tests passed"
