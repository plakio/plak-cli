#!/usr/bin/env bash
# CLI-41: panel Fase B WordPress operations.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect commands/connect commands/panel commands/panel-wp commands/panel-write shared/ui shared/validate; do bash -n "$f"; done

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

fail() { echo "panel-wp test failed: $1" >&2; exit 1; }

cat > "$tmpdir/stub.py" <<'PY'
import http.server, json, urllib.parse
WRITE = "wp-test-token"
SITE = "11"
STATE = {"php": "8.4"}
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
    def _site(self, parts):
        return len(parts) >= 4 and parts[2] == "sites" and parts[3] == SITE
    def do_GET(self):
        a = self._auth()
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        url = urllib.parse.urlsplit(self.path)
        parts, q = url.path.strip("/").split("/"), dict(urllib.parse.parse_qsl(url.query))
        if parts[:2] == ["api", "v1"] and parts[2] == "sites" and len(parts) == 3:
            self._json(200, {"current_page": 1, "per_page": 100, "total": 1, "last_page": 1,
                             "data": [{"id": 11, "domain": "wp.example", "status": "active"}]})
        elif self._site(parts) and parts[4:] == ["wordpress", "overview"]:
            if q.get("refresh") == "empty":
                self._json(200, {"data": None, "reason": "wp.setup_incomplete"})
            else:
                self._json(200, {"data": {"version": "6.7", "posts": 3, "theme": "T"}, "cached_at": "2026-01-01"})
        elif self._site(parts) and parts[4:] == ["wordpress", "themes"]:
            self._json(200, {"data": [{"name": "t1", "version": "1.0", "status": "active"}], "pending": False})
        elif self._site(parts) and parts[4:] == ["wordpress", "plugins"]:
            self._json(200, {"data": [], "pending": True})
        elif len(parts) == 4 and parts[2] == "sites":
            self._json(200, {"data": {"id": int(parts[3]), "php_version": STATE["php"]}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_POST(self):
        a = self._auth(write=True)
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        if a == "ro":
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        tail = urllib.parse.urlsplit(self.path).path
        if tail.endswith("/wordpress/complete-install"):
            if body.get("admin_password") == "short":
                self._json(422, {"code": "validation", "message": "Bad.", "hint": ""})
            else:
                self._json(200, {"data": {"wordpress_setup_completed": True}})
        elif tail.endswith("/wordpress/install-wp-cli"):
            self._json(200, {"data": {"wp_cli_installed": True}})
        elif tail.endswith("/wordpress/xml-rpc/toggle"):
            self._json(200, {"data": {"wordpress_xmlrpc_blocked": body.get("block"), "message": "ok"}})
        elif "/wordpress/themes/" in tail or "/wordpress/plugins/" in tail:
            op = tail.rsplit("/", 1)[1]
            if op in ("activate", "deactivate"):
                self._json(200, {"data": {op + "d": True}})
            elif op in ("update", "delete"):
                key = "themes" if "/themes/" in tail else "plugins"
                items = body.get(key, [])
                self._json(200, {"data": {"updated" if op == "update" else "deleted": [i for i in items if i != "bad"],
                                                "failed": [{"slug": "bad", "error": "nope"}] if "bad" in items else []}})
            elif op == "install":
                self._json(200, {"data": {"installed": True}})
        elif tail.endswith("/wordpress/search-replace"):
            self._json(200, {"data": {"ran": True, "dry_run": body.get("dry_run", False),
                                      "result": {"output": "3 replacements", "status": 0, "message": "ok"}}})
        elif tail.endswith("/wordpress/wp-cli"):
            if "db drop" in body.get("command", ""):
                self._json(422, {"code": "wpcli.forbidden_command", "message": "Denied.", "hint": ""})
            else:
                self._json(200, {"data": {"ran": True, "command": body["command"], "output": "out",
                                          "status": 0, "message": "ok"}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_PATCH(self):
        a = self._auth(write=True)
        if a == "ro":
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        tail = urllib.parse.urlsplit(self.path).path
        if tail.endswith("/wordpress/mark-installed"):
            self._json(200, {"data": {"wordpress_setup_completed": True}})
        elif tail.endswith("/settings/php-version"):
            length = int(self.headers.get("Content-Length", 0))
            STATE["php"] = json.loads(self.rfile.read(length) or b"{}").get("version", STATE["php"])
            self._json(202, {"data": {"php_version": STATE["php"], "status": "changing"}})
        elif tail.endswith("/settings/robot-access"):
            self._json(200, {"data": {"disable_robots": True, "status": "ok"}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_DELETE(self):
        self.do_POST()
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18998), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 http://127.0.0.1:18998/api/v1/sites >/dev/null 2>&1 && break; sleep 0.1; done

PANEL="http://127.0.0.1:18998"
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
seed_conn "wp-test-token"
chmod 600 "$PLAK_HOME/connection.json"

# --- reads ---
./plak.sh panel wp-overview wp.example > "$tmpdir/ov.txt" || fail "overview"
grep -q "6.7" "$tmpdir/ov.txt" || fail "overview version"
./plak.sh panel wp-themes 11 > "$tmpdir/th.txt" || fail "themes"
grep -q "t1" "$tmpdir/th.txt" || fail "themes rows"
./plak.sh panel wp-plugins wp.example > "$tmpdir/pl.txt" || fail "plugins"
grep -q "pending" "$tmpdir/pl.txt" || fail "plugins pending"

# --- install + toggles ---
./plak.sh panel wp-complete-install wp.example --title T --user a --email a@e.t --password longenough8 >/dev/null || fail "complete-install"
./plak.sh panel wp-mark-installed wp.example --json > "$tmpdir/fp1.out" || fail "mark-installed"
grep -q completed "$tmpdir/fp1.out" || fail "mark-installed output"
./plak.sh panel wp-install-wpcli wp.example --json > "$tmpdir/fp2.out" || fail "install-wpcli"
grep -q wp_cli_installed "$tmpdir/fp2.out" || fail "install-wpcli output"
./plak.sh panel wp-xmlrpc wp.example --block --json > "$tmpdir/fp3.out" || fail "xmlrpc"
grep -q '"wordpress_xmlrpc_blocked": true' "$tmpdir/fp3.out" || fail "xmlrpc output"

# --- theme/plugin ops incl. partial failures ---
./plak.sh panel wp-theme-activate wp.example t1 --json > "$tmpdir/fp4.out" || fail "activate"
grep -q activated "$tmpdir/fp4.out" || fail "activate output"
./plak.sh panel wp-plugin-deactivate wp.example p1 --json > "$tmpdir/fp5.out" || fail "deactivate"
grep -q deactivated "$tmpdir/fp5.out" || fail "deactivate output"
./plak.sh panel wp-theme-update wp.example good bad --json > "$tmpdir/up.json" || fail "update"
grep -q '"failed": \[{"slug": "bad"' "$tmpdir/up.json" || fail "partial failed shown"
./plak.sh panel wp-plugin-install wp.example newslug --activate --json > "$tmpdir/fp6.out" || fail "install"
grep -q installed "$tmpdir/fp6.out" || fail "install output"
./plak.sh panel wp-theme-delete wp.example old --yes --json > "$tmpdir/fp7.out" || fail "delete"
grep -q deleted "$tmpdir/fp7.out" || fail "delete output"
./plak.sh panel wp-theme-delete wp.example old 2>/dev/null && fail "delete without --yes"

# --- search-replace + wp-cli ---
./plak.sh panel wp-search-replace wp.example --search a --replace b --dry-run --json > "$tmpdir/fp8.out" || fail "sr dry"
grep -q replacements "$tmpdir/fp8.out" || fail "sr dry output"
./plak.sh panel wp-search-replace wp.example --search a --replace b --yes >/dev/null || fail "sr real"
./plak.sh panel wp-cli wp.example -- option get home --json > "$tmpdir/fp9.out" || fail "wp-cli"
grep -q '"ran": true' "$tmpdir/fp9.out" || fail "wp-cli output"
./plak.sh panel wp-cli wp.example -- db drop 2>/dev/null && fail "forbidden wp-cli accepted"

# --- settings async + read-only denied ---
./plak.sh panel wp-set-php wp.example --version 8.3 --poll 1 --wait 20 --json > "$tmpdir/php.json" || fail "php set"
grep -q '"php_version": "8.3"' "$tmpdir/php.json" || fail "php poll"
./plak.sh panel wp-set-robots wp.example --disable --json > "$tmpdir/fp10.out" || fail "robots"
grep -q disable_robots "$tmpdir/fp10.out" || fail "robots output"
seed_conn "ro-token"
./plak.sh panel wp-theme-activate wp.example t1 2>/dev/null && fail "ro-token accepted"

echo "panel-wp tests passed"
