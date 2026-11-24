#!/usr/bin/env bash
# plakio/plak-cli#78: plak sandbox create/list/show/import against a local stub.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/service-http commands/sandbox; do bash -n "$f"; done

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

fail() { echo "sandbox test failed: $1" >&2; exit 1; }

cat > "$tmpdir/stub.py" <<'PY'
import datetime, http.server, json, urllib.parse

state = {"attempts": {}, "keys": [], "requests": []}
def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()
def expires():
    return (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=24)).isoformat()
def site_for(sub, uuid):
    return {
        "uuid": uuid,
        "subdomain": sub,
        "domain": sub + ".sandbox.test",
        "url": "https://" + sub + ".sandbox.test",
        "public_url": "https://sandbox.test/s/" + uuid,
        "status": "active",
        "expires_at": expires(),
        "created_at": now(),
        "plugins": [],
    }
def credentials():
    return {
        "wordpress": {"username": "admin-test", "password": "wp-secret"},
        "database": {"host": "db.test", "name": "dbname", "username": "dbuser", "password": "db-secret"},
    }

class H(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj, headers=None):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        if url.path == "/__stats":
            self._json(200, {"attempts": state["attempts"], "keys": state["keys"], "requests": state["requests"]})
            return
        if url.path.startswith("/api/v1/public/sites/"):
            uuid = url.path.rsplit("/", 1)[1]
            if uuid == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb":
                self._json(200, {"site": site_for("imported", uuid), "credentials": credentials()})
            elif uuid == "cccccccccccccccccccccccccccccccc":
                self._json(404, {"success": False, "code": "not_found", "error": "Not found."})
            else:
                self._json(200, {"site": site_for("demo", uuid), "credentials": credentials()})
        else:
            self._json(404, {"success": False, "code": "not_found", "error": "Not found."})

    def do_POST(self):
        if urllib.parse.urlsplit(self.path).path != "/api/v1/public/sites":
            self._json(404, {"success": False, "code": "not_found", "error": "Not found."})
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        sub = body.get("subdomain", "")
        key = self.headers.get("Idempotency-Key", "")
        state["attempts"][sub] = state["attempts"].get(sub, 0) + 1
        state["keys"].append(key)
        state["requests"].append({"subdomain": sub, "key": key, "body": body})
        attempt = state["attempts"][sub]
        if sub == "retry-demo" and attempt == 1:
            self.close_connection = True
            return
        if sub == "pending-demo" and attempt <= 2:
            self.close_connection = True
            return
        if sub == "disabled":
            self._json(503, {"success": False, "code": "creation_disabled", "error": "Creation disabled."})
            return
        if sub == "duplicate":
            self._json(422, {"success": False, "code": "site.exists", "error": "The subdomain is already in use."})
            return
        if sub == "rate-demo":
            self._json(429, {"success": False, "code": "rate_limited", "error": "Too many requests."}, {"Retry-After": "7"})
            return
        uuid = {
            "demo": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "retry-demo": "dddddddddddddddddddddddddddddddd",
            "pending-demo": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        }.get(sub, "ffffffffffffffffffffffffffffffff")
        self._json(201, {"site": site_for(sub, uuid), "credentials": credentials(), "request_id": "req-" + sub})

    def log_message(self, *a):
        pass

http.server.HTTPServer(("127.0.0.1", 18994), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 http://127.0.0.1:18994/__stats >/dev/null 2>&1 && break; sleep 0.1; done
export PLAK_SANDBOX_URL="http://127.0.0.1:18994"

# --- create + local state ---
./plak.sh sandbox create demo --email me@example.test --plugin devkit --json > "$tmpdir/create.json" || fail "create"
python3 - "$tmpdir/create.json" <<'PY' || fail "create json"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["site"]["uuid"] == "a" * 32, d
assert d["site"]["url"].startswith("https://demo.sandbox.test"), d
assert d["credentials"]["wordpress"]["password"] == "wp-secret", d
PY
python3 - "$PLAK_HOME/sandbox-sites.json" <<'PY' || fail "sandbox state"
import json, os, stat, sys
raw = open(sys.argv[1]).read()
assert "wp-secret" not in raw and "db-secret" not in raw, raw
mode = stat.S_IMODE(os.stat(sys.argv[1]).st_mode)
assert mode == 0o600, oct(mode)
d = json.loads(raw)
assert "demo" in d["sites"]["a" * 32]["subdomain"], d
assert not d.get("pending"), d
PY
./plak.sh sandbox list --json > "$tmpdir/list.json" || fail "list"
grep -q '"subdomain": "demo"' "$tmpdir/list.json" || fail "list row"
./plak.sh sandbox list > "$tmpdir/list.txt" || fail "list human"
grep -q "demo.sandbox.test" "$tmpdir/list.txt" || fail "list human row"

# --- show: credentials only with --secrets ---
./plak.sh sandbox show demo --json > "$tmpdir/show.json" || fail "show"
python3 - "$tmpdir/show.json" <<'PY' || fail "show hides credentials"
import json, sys
d = json.load(open(sys.argv[1]))
assert "credentials" not in d, d
assert d["site"]["status"] == "active", d
PY
./plak.sh sandbox show demo --secrets --json > "$tmpdir/show-secrets.json" || fail "show secrets"
grep -q "wp-secret" "$tmpdir/show-secrets.json" || fail "show secrets content"

# --- import an existing /s/<uuid> ---
./plak.sh sandbox import "https://sandbox.test/s/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" > "$tmpdir/import.out" || fail "import"
grep -q "Imported sandbox imported.sandbox.test" "$tmpdir/import.out" || fail "import message"
./plak.sh sandbox import "https://sandbox.test/s/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" --json > "$tmpdir/import.json" || fail "import json"
python3 - "$tmpdir/import.json" <<'PY' || fail "import json safe"
import json, sys
raw = open(sys.argv[1]).read()
d = json.loads(raw)
assert d["imported"] is True, d
assert "wp-secret" not in raw and "db-secret" not in raw, raw
PY
./plak.sh sandbox list --json > "$tmpdir/list2.json" || fail "list after import"
grep -q "imported.sandbox.test" "$tmpdir/list2.json" || fail "imported not listed"

# --- one interrupted create is retried with the same key ---
./plak.sh sandbox create retry-demo --json > "$tmpdir/retry.json" || fail "retry create"
python3 - "$tmpdir/retry.json" <<'PY' || fail "retry json"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["site"]["subdomain"] == "retry-demo", d
PY
python3 - "$(curl -fsS http://127.0.0.1:18994/__stats)" <<'PY' || fail "retry key"
import json, sys
s = json.loads(sys.argv[1])
keys = [item["key"] for item in s["requests"] if item["subdomain"] == "retry-demo"]
assert len(keys) == 2 and len(set(keys)) == 1, (keys, s)
PY

# --- pending retry after both attempts fail, then reuse the key ---
set +e
./plak.sh sandbox create pending-demo --json > "$tmpdir/pending-fail.json" 2> "$tmpdir/pending-fail.err"
pending_rc=$?
set -e
[ "$pending_rc" -ne 0 ] || fail "pending creation unexpectedly succeeded"
python3 - "$PLAK_HOME/sandbox-sites.json" <<'PY' || fail "pending state"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["pending"]["pending-demo"]["idempotency_key"], d
PY
./plak.sh sandbox create pending-demo --json > "$tmpdir/pending-ok.json" || fail "pending resume"
python3 - "$(curl -fsS http://127.0.0.1:18994/__stats)" <<'PY' || fail "pending key reuse"
import json, sys
s = json.loads(sys.argv[1])
keys = [item["key"] for item in s["requests"] if item["subdomain"] == "pending-demo"]
assert len(keys) == 3 and len(set(keys)) == 1, (keys, s)
PY

# --- error mapping ---
./plak.sh sandbox create disabled > /dev/null 2> "$tmpdir/disabled.err" && fail "503 accepted"
grep -q "temporarily disabled" "$tmpdir/disabled.err" || fail "503 message"
./plak.sh sandbox create duplicate > /dev/null 2> "$tmpdir/duplicate.err" && fail "duplicate accepted"
grep -q "already in use" "$tmpdir/duplicate.err" || fail "duplicate message"
./plak.sh sandbox create rate-demo > /dev/null 2> "$tmpdir/rate.err" && fail "429 accepted"
grep -q "retry after 7s" "$tmpdir/rate.err" || fail "429 message"

echo "sandbox tests passed"
