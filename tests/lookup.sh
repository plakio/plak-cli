#!/usr/bin/env bash
# plakio/plak-cli#76/#77: plak lookup integration (public API, no real network).
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in main shared/service-http commands/lookup; do bash -n "$f"; done

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

fail() { echo "lookup test failed: $1" >&2; exit 1; }

cat > "$tmpdir/stub.py" <<'PY'
import http.server, json, time, urllib.parse

LOOKUP = {
    "domain": "example.com",
    "root_domain": "example.com",
    "sub_domain": "",
    "whois": [
        {"name": "Registrar", "value": "Example Registrar"},
        {"name": "Expiration Date", "value": "2030-01-01"},
        {"name": "DNSSEC", "value": "unsigned"},
    ],
    "whois_source": "RDAP",
    "dns_records": [
        {"type": "a", "name": "example.com", "value": "192.0.2.10", "ttl": 300},
        {"type": "mx", "name": "example.com", "value": "mail.example.com", "ttl": 300},
    ],
    "dns_status": "NOERROR",
    "dns_source": "authoritative",
    "ips": ["192.0.2.10"],
    "nameservers": ["ns1.example.com", "ns2.example.com"],
    "email_security": {"status": "warn", "summary": "1 warning.", "checks": [
        {"key": "spf", "label": "SPF", "status": "ok", "summary": "1 record."},
        {"key": "dmarc", "label": "DMARC", "status": "warn", "summary": "p=none.", "recommendation": "Move to reject."},
    ]},
    "http_status": 200,
    "http_url": "https://example.com/",
    "http_error": None,
    "http_tls": True,
    "zone": "; zone example.com\n$ORIGIN example.com.\n",
    "zone_meta": {"scope": "dns-probe", "record_count": 2},
    "partial": False,
    "cached": False,
    "request_id": "req-1",
    "warnings": [],
    "errors": [],
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

    def _text(self, code, body, content_type="text/plain"):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        if url.path in ("/api.php", "/"):
            domain = q.get("domain", "")
            if domain == "bad.example":
                self._json(422, {"errors": ["Enter a full domain name."]})
            elif domain == "rate.example":
                self._json(429, {"errors": ["Too many requests."]}, {"Retry-After": "7"})
            elif domain == "down.example":
                self._json(503, {"errors": ["Temporarily unavailable."]})
            elif domain == "slow.example":
                time.sleep(2)
                self._json(200, LOOKUP)
            else:
                self._json(200, LOOKUP)
        elif url.path == "/health":
            self._json(200, {"status": "ok", "checks": {"php": {"ok": True, "version": "8.3"}}})
        elif url.path == "/audit.php" and q.get("id"):
            if q.get("format") == "csv":
                self._text(200, "domain,status\nexample.com,ok\n", "text/csv")
            elif q.get("format") == "json":
                self._json(200, {"summary": {"total": 1, "ok": 1}, "rows": [{"domain": "example.com"}]})
            else:
                self._json(200, {"id": q["id"], "status": "done", "processed": 1, "total": 1,
                                 "succeeded": 1, "failed": 0, "percent": 100})
        else:
            self._json(404, {"errors": ["not found"]})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        path = urllib.parse.urlsplit(self.path).path
        if path == "/audit.php":
            if b"action=cancel" in body:
                self._json(200, {"job": {"id": "job-cancel", "status": "cancelled", "processed": 0, "total": 1,
                                         "succeeded": 0, "failed": 0}, "ignored": [], "worker_started": True})
            else:
                self._json(200, {"job": {"id": "job-1", "status": "running", "processed": 0, "total": 1,
                                         "succeeded": 0, "failed": 0}, "ignored": [], "worker_started": True})
        elif path == "/convert.php":
            if b"name=\"provider\"" not in body:
                self._json(422, {"errors": ["Missing provider."]})
            else:
                self._json(200, {"provider": "cloudflare", "format": "bind",
                                 "content": "example.com. 300 IN A 192.0.2.10\n",
                                 "records": 1, "warnings": ["SOA omitted"], "errors": [], "request_id": "conv-1"})
        elif path == "/diff.php":
            self._json(200, {"has_changes": True, "risk": "medium",
                             "summary": {"added": 1, "removed": 0, "changed": 0, "unchanged": 2},
                             "added": [{"type": "mx", "name": "", "value": "mail.example.com"}],
                             "removed": [], "changed": [],
                             "changes": [{"risk": "medium", "message": "Added MX mail.example.com."}],
                             "exports": {"json": "{\"risk\":\"medium\"}\n", "csv": "type,message\nmx,Added MX\n"},
                             "filename": "zone-diff-1", "request_id": "diff-1"})
        else:
            self._json(404, {"errors": ["not found"]})

    def log_message(self, *a):
        pass

http.server.HTTPServer(("127.0.0.1", 18996), H).serve_forever()
PY
python3 "$tmpdir/stub.py" &
server_pid=$!
for _ in $(seq 1 50); do curl -s -m 2 http://127.0.0.1:18996/health >/dev/null 2>&1 && break; sleep 0.1; done
export PLAK_LOOKUP_URL="http://127.0.0.1:18996"

# --- summary, JSON and filters ---
./plak.sh lookup example.com > "$tmpdir/summary.txt" || fail "summary"
grep -q "Domain: example.com" "$tmpdir/summary.txt" || fail "summary domain"
grep -q "Registrar" "$tmpdir/summary.txt" || fail "summary whois"
grep -q "NOERROR" "$tmpdir/summary.txt" || fail "summary dns"
grep -q "Email: warn" "$tmpdir/summary.txt" || fail "summary email"
./plak.sh lookup example.com --json > "$tmpdir/summary.json" || fail "summary json"
python3 - "$tmpdir/summary.json" <<'PY' || fail "summary json shape"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["domain"] == "example.com" and d["dns_status"] == "NOERROR", d
PY
./plak.sh lookup whois example.com > "$tmpdir/whois.txt" || fail "whois"
grep -q "Example Registrar" "$tmpdir/whois.txt" || fail "whois rows"
./plak.sh lookup dns example.com --type MX > "$tmpdir/dns.txt" || fail "dns"
grep -q "MX" "$tmpdir/dns.txt" || fail "dns mx"
if grep -q "192.0.2.10" "$tmpdir/dns.txt"; then fail "dns type filter failed"; fi
./plak.sh lookup email example.com > "$tmpdir/email.txt" || fail "email"
grep -q "DMARC" "$tmpdir/email.txt" || fail "email checks"
./plak.sh lookup zone example.com --deep --output "$tmpdir/zone.txt" > "$tmpdir/zone.out" || fail "zone"
grep -q '\$ORIGIN example.com' "$tmpdir/zone.txt" || fail "zone content"
./plak.sh lookup zone example.com --deep --output "$tmpdir/zone2.txt" --json > "$tmpdir/zone.json" || fail "zone json output"
python3 - "$tmpdir/zone.json" <<'PY' || fail "zone json clean"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["zone"].startswith("; zone"), d
PY
./plak.sh lookup health --json > "$tmpdir/health.json" || fail "health"
python3 - "$tmpdir/health.json" <<'PY' || fail "health json"
import json, sys
assert json.load(open(sys.argv[1]))["status"] == "ok"
PY

# --- errors and timeouts ---
./plak.sh lookup bad.example > /dev/null 2> "$tmpdir/bad.err" && fail "422 accepted"
grep -q "Enter a full domain name" "$tmpdir/bad.err" || fail "422 message"
./plak.sh lookup rate.example > /dev/null 2> "$tmpdir/rate.err" && fail "429 accepted"
grep -q "retry after 7s" "$tmpdir/rate.err" || fail "429 retry"
./plak.sh lookup down.example > /dev/null 2> "$tmpdir/down.err" && fail "503 accepted"
grep -q "temporarily unavailable" "$tmpdir/down.err" || fail "503 message"
./plak.sh lookup slow.example --timeout 1 > /dev/null 2> "$tmpdir/slow.err" && fail "timeout accepted"
grep -q "took too long" "$tmpdir/slow.err" || fail "timeout message"

# --- audit, convert and diff ---
./plak.sh lookup audit example.com --wait 5 --poll 1 --json > "$tmpdir/audit.json" || fail "audit"
python3 - "$tmpdir/audit.json" <<'PY' || fail "audit json"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "done" and d["id"] == "job-1", d
PY
./plak.sh lookup audit --id job-1 --json > "$tmpdir/audit-id.json" || fail "audit id"
python3 - "$tmpdir/audit-id.json" <<'PY' || fail "audit id json"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["id"] == "job-1", d
PY
./plak.sh lookup audit example.com --wait 5 --poll 1 --format csv --output "$tmpdir/audit.csv" > "$tmpdir/audit-csv.out" || fail "audit csv"
grep -q "domain,status" "$tmpdir/audit.csv" || fail "audit csv content"
./plak.sh lookup audit --cancel job-1 --json > "$tmpdir/cancel.json" || fail "audit cancel"
grep -q "job-cancel" "$tmpdir/cancel.json" || fail "audit cancel id"
printf 'example.com. 300 IN A 192.0.2.10\n' > "$tmpdir/in.zone"
./plak.sh lookup convert "$tmpdir/in.zone" --provider cloudflare --output "$tmpdir/out.zone" > "$tmpdir/convert.out" || fail "convert"
grep -q '192.0.2.10' "$tmpdir/out.zone" || fail "convert output"
./plak.sh lookup convert "$tmpdir/in.zone" --provider cloudflare --output "$tmpdir/out2.zone" --json > "$tmpdir/convert.json" || fail "convert json"
python3 - "$tmpdir/convert.json" <<'PY' || fail "convert json clean"
import json, sys
assert json.load(open(sys.argv[1]))["records"] == 1
PY
printf 'example.com. 300 IN A 192.0.2.10\n' > "$tmpdir/before.zone"
printf 'example.com. 300 IN A 192.0.2.10\nexample.com. 300 IN MX mail.example.com.\n' > "$tmpdir/after.zone"
./plak.sh lookup diff --before "$tmpdir/before.zone" --after "$tmpdir/after.zone" --csv > "$tmpdir/diff.csv" || fail "diff"
grep -q "Added MX" "$tmpdir/diff.csv" || fail "diff csv"
./plak.sh lookup diff --before "$tmpdir/before.zone" --after "$tmpdir/after.zone" --json --output "$tmpdir/diff.json.out" > "$tmpdir/diff.json" || fail "diff json"
python3 - "$tmpdir/diff.json" <<'PY' || fail "diff json clean"
import json, sys
assert json.load(open(sys.argv[1]))["risk"] == "medium"
PY

echo "lookup tests passed"
