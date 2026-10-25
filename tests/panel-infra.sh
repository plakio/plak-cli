#!/usr/bin/env bash
# CLI-43: panel Fase D site infra operations.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/connect commands/connect commands/panel commands/panel-infra commands/panel-write shared/ui shared/validate; do bash -n "$f"; done

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

fail() { echo "panel-infra test failed: $1" >&2; exit 1; }

cat > "$tmpdir/stub.py" <<'PY'
import http.server, json, urllib.parse
WRITE = "infra-test-token"
APP = {"project": "wordpress"}
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
    def _body(self):
        raw = getattr(self, "_raw_body", None)
        if raw is None:
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b"{}"
        try:
            return json.loads(raw)
        except Exception:
            return {}
    def do_GET(self):
        a = self._auth()
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        tail = urllib.parse.urlsplit(self.path).path
        if tail == "/api/v1/sites":
            self._json(200, {"current_page": 1, "per_page": 100, "total": 1, "last_page": 1,
                             "data": [{"id": 31, "domain": "infra.example", "status": "active"}]})
        elif tail.endswith("/databases"):
            self._json(200, {"current_page": 1, "total": 1, "last_page": 1, "data": [{"id": 7, "name": "infra_db", "status": "active"}]})
        elif tail.endswith("/cronjobs"):
            self._json(200, {"current_page": 1, "total": 1, "last_page": 1, "data": [{"id": 8, "command": "* * * * * php artisan schedule:run"}]})
        elif tail.endswith("/certificates"):
            self._json(200, {"current_page": 1, "total": 1, "last_page": 1, "data": [{"id": 9, "type": "letsencrypt", "domain": "infra.example"}]})
        elif tail.endswith("/redirects"):
            self._json(200, {"current_page": 1, "total": 1, "last_page": 1, "data": [{"id": 10, "redirect_from": "/old", "redirect_to": "/new"}]})
        elif tail.endswith("/aliases"):
            self._json(200, {"data": ["alias.example"]})
        elif tail.endswith("/dns/records"):
            self._json(200, {"data": [{"id": "cf1", "type": "A", "name": "infra.example", "content": "1.2.3.4"}]})
        elif tail.endswith("/auth-users"):
            self._json(200, {"data": [{"id": 11, "name": "plak"}]})
        elif tail.endswith("/cache"):
            self._json(200, {"data": {"fastcgi_cache_enabled": True, "opcache_enabled": True}})
        elif tail.endswith("/apps"):
            self._json(200, {"project": APP["project"], "wordpress_setup_completed": True})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        self._raw_body = raw
        a = self._auth(write=True)
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        if a == "ro":
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        tail = urllib.parse.urlsplit(self.path).path
        body = self._body()
        if tail.endswith("/databases"):
            self._json(201, {"id": 7, "name": "infra_" + body["name"], "user_name": body["user_name"], "status": "active"})
        elif tail.endswith("/cronjobs"):
            self._json(201, {"id": 8, "command": body["command"]})
        elif tail.endswith("/certificates"):
            if body.get("type") == "bogus":
                self._json(422, {"code": "certificate.invalid_type", "message": "Bad type.", "hint": ""})
            else:
                self._json(201, {"id": 9, "type": body["type"], "domain": body.get("domain", "infra.example")})
        elif tail.endswith("/redirects"):
            self._json(201, {"id": 10, "redirect_from": body["redirect_from"], "redirect_to": body["redirect_to"], "type": body["type"]})
        elif tail.endswith("/aliases"):
            self._json(201, {"data": ["alias.example", body["domain"]]})
        elif tail.endswith("/dns"):
            self._json(201, {"id": "cf2", "type": body["type"], "name": body["name"], "content": body["content"]})
        elif tail.endswith("/auth-users"):
            self._json(201, {"id": 12, "name": body["name"]})
        elif tail.endswith("/cache/enable"):
            self._json(200, {"data": {"message": "Enabled."}})
        elif tail.endswith("/cache/flush"):
            self._json(200, {"data": {"message": "Flushed."}})
        elif tail.endswith("/cache/opcache/refresh"):
            self._json(200, {"opcache": "refreshed"})
        elif tail.endswith("/apps"):
            APP["project"] = body["type"]
            self._json(202, {"project": body["type"], "status": "installing"})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def do_PUT(self):
        a = self._auth(write=True)
        if a == "ro":
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        if a == "bad":
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        tail = urllib.parse.urlsplit(self.path).path
        body = self._body()
        if "/dns/" in tail:
            self._json(200, {"id": tail.rsplit("/", 1)[1], "type": body["type"], "name": body["name"], "content": body["content"]})
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
        tail = urllib.parse.urlsplit(self.path).path
        if tail.endswith("/cache/disable"):
            self._json(200, {"data": {"message": "Disabled."}})
        elif tail.endswith("/apps"):
            APP["project"] = None
            self._json(202, {"project": None, "status": "uninstalling"})
        elif "/dns/" in tail or "/aliases/" in tail or "/auth-users/" in tail:
            self._json(200, {"data": {"deleted": True}})
        elif any(tail.endswith("/" + r + "/" + str(i)) for r, i in [("databases", 7), ("cronjobs", 8), ("certificates", 9), ("redirects", 10)]):
            self._json(200, {"data": {"deleted": True}})
        else:
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", 18948), H).serve_forever()
PY
PORT=$(( (RANDOM % 2000) + 21000 ))
sed -i "s/18948/$PORT/" "$tmpdir/stub.py"
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 "http://127.0.0.1:$PORT/api/v1/sites" >/dev/null 2>&1 && break; sleep 0.1; done

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
seed_conn "infra-test-token"
chmod 600 "$PLAK_HOME/connection.json"

# --- databases ---
./plak.sh panel db-list infra.example > "$tmpdir/db.txt" || fail "db-list"
grep -q infra_db "$tmpdir/db.txt" || fail "db rows"
./plak.sh panel db-add infra.example --name app --user appu --password secretpw --json > "$tmpdir/dbadd.json" || fail "db-add"
grep -q infra_app "$tmpdir/dbadd.json" || fail "db-add json"
./plak.sh panel db-del infra.example 7 --yes --json > "$tmpdir/pipe1.out" || fail "db-del"
grep -q deleted "$tmpdir/pipe1.out" || fail "db-del output"

# --- cronjobs ---
./plak.sh panel cron-list infra.example > "$tmpdir/cron.txt" || fail "cron-list"
grep -q schedule:run "$tmpdir/cron.txt" || fail "cron rows"
./plak.sh panel cron-add infra.example --command "php artisan queue:work" --json > "$tmpdir/pipe2.out" || fail "cron-add"
grep -q queue:work "$tmpdir/pipe2.out" || fail "cron-add output"
./plak.sh panel cron-del infra.example 8 --yes --json > "$tmpdir/pipe3.out" || fail "cron-del"
grep -q deleted "$tmpdir/pipe3.out" || fail "cron-del output"

# --- certificates ---
./plak.sh panel cert-list infra.example > "$tmpdir/cert.txt" || fail "cert-list"
grep -q letsencrypt "$tmpdir/cert.txt" || fail "cert rows"
./plak.sh panel cert-add infra.example --type letsencrypt --domain infra.example --json > "$tmpdir/pipe4.out" || fail "cert-add"
grep -q letsencrypt "$tmpdir/pipe4.out" || fail "cert-add output"
./plak.sh panel cert-add infra.example --type bogus 2>/dev/null && fail "bad cert type accepted"
./plak.sh panel cert-del infra.example 9 --yes --json > "$tmpdir/pipe5.out" || fail "cert-del"
grep -q deleted "$tmpdir/pipe5.out" || fail "cert-del output"

# --- redirects ---
./plak.sh panel redirect-list infra.example > "$tmpdir/redir.txt" || fail "redirect-list"
grep -q /old "$tmpdir/redir.txt" || fail "redirect rows"
./plak.sh panel redirect-add infra.example --from /a --to /b --type permanent --json > "$tmpdir/pipe6.out" || fail "redirect-add"
grep -q /a "$tmpdir/pipe6.out" || fail "redirect-add output"
./plak.sh panel redirect-del infra.example 10 --yes --json > "$tmpdir/pipe7.out" || fail "redirect-del"
grep -q deleted "$tmpdir/pipe7.out" || fail "redirect-del output"

# --- aliases ---
./plak.sh panel alias-list infra.example > "$tmpdir/al.txt" || fail "alias-list"
grep -q alias.example "$tmpdir/al.txt" || fail "alias rows"
./plak.sh panel alias-add infra.example --domain new.example --json > "$tmpdir/pipe8.out" || fail "alias-add"
grep -q new.example "$tmpdir/pipe8.out" || fail "alias-add output"
./plak.sh panel alias-del infra.example alias.example --yes --json > "$tmpdir/pipe9.out" || fail "alias-del"
grep -q deleted "$tmpdir/pipe9.out" || fail "alias-del output"

# --- dns ---
./plak.sh panel dns-list infra.example > "$tmpdir/dns.txt" || fail "dns-list"
grep -q 1.2.3.4 "$tmpdir/dns.txt" || fail "dns rows"
./plak.sh panel dns-add infra.example --type A --name sub --content 5.6.7.8 --json > "$tmpdir/pipe10.out" || fail "dns-add"
grep -q sub "$tmpdir/pipe10.out" || fail "dns-add output"
./plak.sh panel dns-update infra.example cf1 --type A --name infra.example --content 9.9.9.9 --json > "$tmpdir/pipe11.out" || fail "dns-update"
grep -q 9.9.9.9 "$tmpdir/pipe11.out" || fail "dns-update output"
./plak.sh panel dns-del infra.example cf1 --yes --json > "$tmpdir/pipe12.out" || fail "dns-del"
grep -q deleted "$tmpdir/pipe12.out" || fail "dns-del output"

# --- auth users ---
./plak.sh panel authuser-list infra.example > "$tmpdir/auth.txt" || fail "authuser-list"
grep -q plak "$tmpdir/auth.txt" || fail "auth rows"
./plak.sh panel authuser-add infra.example --name deploy --password pw --json > "$tmpdir/pipe13.out" || fail "authuser-add"
grep -q deploy "$tmpdir/pipe13.out" || fail "authuser-add output"
./plak.sh panel authuser-del infra.example 11 --yes --json > "$tmpdir/pipe14.out" || fail "authuser-del"
grep -q deleted "$tmpdir/pipe14.out" || fail "authuser-del output"

# --- cache ---
./plak.sh panel cache-info infra.example > "$tmpdir/cache.txt" || fail "cache-info"
grep -q fastcgi_cache_enabled "$tmpdir/cache.txt" || fail "cache rows"
./plak.sh panel cache-enable infra.example --yes --json > "$tmpdir/pipe15.out" || fail "cache-enable"
grep -q Enabled "$tmpdir/pipe15.out" || fail "cache-enable output"
./plak.sh panel cache-disable infra.example --yes --json > "$tmpdir/pipe16.out" || fail "cache-disable"
grep -q Disabled "$tmpdir/pipe16.out" || fail "cache-disable output"
./plak.sh panel cache-flush infra.example --yes --json > "$tmpdir/pipe17.out" || fail "cache-flush"
grep -q Flushed "$tmpdir/pipe17.out" || fail "cache-flush output"
./plak.sh panel cache-opcache-refresh infra.example --yes --json > "$tmpdir/pipe18.out" || fail "opcache-refresh"
grep -q refreshed "$tmpdir/pipe18.out" || fail "opcache-refresh output"

# --- apps ---
./plak.sh panel app-info infra.example > "$tmpdir/app.txt" || fail "app-info"
grep -q wordpress "$tmpdir/app.txt" || fail "app rows"
./plak.sh panel app-install infra.example --type wordpress --poll 1 --wait 10 --json > "$tmpdir/appinstall.json" || fail "app-install"
grep -q installed "$tmpdir/appinstall.json" || fail "app-install poll"
./plak.sh panel app-uninstall infra.example --yes --json > "$tmpdir/appun.json" || fail "app-uninstall"
grep -q uninstalled "$tmpdir/appun.json" || fail "app-uninstall poll"

# --- read-only denied ---
seed_conn "ro-token"
./plak.sh panel db-add infra.example --name x --user y --password z 2>/dev/null && fail "ro-token accepted"

echo "panel-infra tests passed"
