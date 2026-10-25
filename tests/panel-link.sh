#!/usr/bin/env bash
# CLI-26: plak panel link binds a panel site to a local site over verified SSH.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect commands/connect commands/panel commands/panel-link shared/remote shared/ui shared/validate; do bash -n "$f"; done

tmpdir=$(mktemp -d)
server_pid=""
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmpdir"
}
trap cleanup EXIT

export PLAK_NO_PATH_PRELUDE=1
export HOME="$tmpdir/home"
mkdir -p "$HOME/.ssh" "$tmpdir/bin" "$HOME/Plak/Sites/myshop.localhost"
export PLAK_HOME="$HOME/.plak"
export PLAK_SSH_CONFIG="$HOME/.ssh/config"
export PATH="$tmpdir/bin:$PATH"
source ./plak.sh >/dev/null
# SITES_DIR derives from HOME/Plak (runtime default)

fail() { echo "panel-link test failed: $1" >&2; exit 1; }

# --- fake ssh: succeeds only for the verified path probe ---
cat > "$tmpdir/bin/ssh" <<'SSH'
#!/usr/bin/env bash
echo "$*" >> "$SSH_LOG"
[[ "$*" == *"/home/plak/shop.example/public"* && "$*" == *"wp-config.php"* ]] && exit 0
exit 1
SSH
chmod +x "$tmpdir/bin/ssh"
export SSH_LOG="$tmpdir/ssh.log"
: > "$SSH_LOG"

# --- stub panel: sites list, connection contract, authorize endpoint ---
cat > "$tmpdir/stub.py" <<'PY'
import http.server, json, urllib.parse
TOKEN = "link-test-token"
SITE = {"id": 21, "domain": "shop.example", "status": "active", "project": "wordpress"}
calls = []
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
        if url.path == "/api/v1/sites":
            self._json(200, {"current_page": 1, "per_page": 100, "total": 1, "last_page": 1, "data": [dict(SITE, server={"id": 9, "name": "web-9", "status": "active"})]})
        elif url.path == "/api/v1/sites/21/connection":
            self._json(200, {"data": {
                "site": SITE,
                "server": {"id": 9, "name": "web-9", "status": "active", "ip": "203.0.113.99", "ssh_port": 2222},
                "system_users": [{"name": "plak", "sudo": False}],
                "wordpress_path": None,
                "path_hint": "hint"}})
        else:
            self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
    def do_POST(self):
        if not self._auth():
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        calls.append(body)
        if url_path := urllib.parse.urlsplit(self.path).path == "/api/v1/servers/9/ssh-keys":
            if len(calls) > 1:
                self._json(200, {"data": {"installed": True, "duplicate": True, "name": body["name"],
                                          "fingerprint": "SHA256:x", "system_user": body.get("system_user"),
                                          "ploi_ssh_key_id": 55}})
            else:
                self._json(201, {"data": {"installed": True, "duplicate": False, "name": body["name"],
                                          "fingerprint": "SHA256:x", "system_user": body.get("system_user"),
                                          "ploi_ssh_key_id": 55,
                                          "remove_hint": "panel"}})
        else:
            self._json(404, {"code": "not_found", "message": "x", "hint": "y"})
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18995), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 http://127.0.0.1:18995/api/v1/sites >/dev/null 2>&1 && break; sleep 0.1; done

PANEL="http://127.0.0.1:18995"
mkdir -p "$PLAK_HOME" && chmod 700 "$PLAK_HOME"
python3 <<PY
import json
json.dump({"panel_url": "$PANEL", "token": "link-test-token",
           "user": {"id": 1, "name": "T", "email": "t@example.test"},
           "saved_at": "2026-01-01T00:00:00+00:00"},
          open("$PLAK_HOME/connection.json", "w"))
PY
chmod 600 "$PLAK_HOME/connection.json"

ssh-keygen -t ed25519 -f "$HOME/.ssh/id_test" -N '' -C "test" -q

# --- happy path: authorize, verify, remote, bind, record ---
./plak.sh panel link shop.example myshop --system-user plak --key "$HOME/.ssh/id_test" --yes || fail "link"
grep -q "panel-shop.example" "$PLAK_SSH_CONFIG" || fail "remote alias"
[ "$(cat "$HOME/Plak/Sites/myshop.localhost/.remote")" = "panel-shop.example" ] || fail "binding"
python3 - "$HOME/Plak/Sites/myshop.localhost/.panel-link" <<'PY' || fail "link record"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["site"] == {"id": 21, "domain": "shop.example"}, d
assert d["remote"] == "panel-shop.example" and d["local_site"] == "myshop", d
assert "token" not in json.dumps(d) and "link-test-token" not in open(sys.argv[1]).read()
PY
grep -q "test -f" "$SSH_LOG" || fail "no ssh verify"

# --- idempotent relink of the same pair ---
./plak.sh panel link shop.example myshop --system-user plak --key "$HOME/.ssh/id_test" --yes >/dev/null || fail "relink"

# --- wrong path is never bound ---
rm -f "$HOME/Plak/Sites/myshop.localhost/.panel-link" "$HOME/Plak/Sites/myshop.localhost/.remote"
./plak.sh panel link shop.example myshop --system-user plak --key "$HOME/.ssh/id_test" --path "/wrong/place" --yes 2>/dev/null && fail "bad path linked"
[ ! -f "$HOME/Plak/Sites/myshop.localhost/.panel-link" ] || fail "bad path record"

# --- foreign site stays unreachable ---
./plak.sh panel link nosuch.example myshop --system-user plak --key "$HOME/.ssh/id_test" --yes 2>/dev/null && fail "foreign linked"

# --- unlink keeps the remote, links lists current ---
./plak.sh panel link shop.example myshop --system-user plak --key "$HOME/.ssh/id_test" --yes >/dev/null || fail "relink2"
./plak.sh panel unlink myshop --yes >/dev/null || fail "unlink"
[ ! -f "$HOME/Plak/Sites/myshop.localhost/.panel-link" ] || fail "link remains"
grep -q "panel-shop.example" "$PLAK_SSH_CONFIG" || fail "remote removed by unlink"
./plak.sh panel links > "$tmpdir/fp1.out" || fail "links list"
grep -q "No panel links" "$tmpdir/fp1.out" || fail "links list output"

echo "panel-link tests passed"
