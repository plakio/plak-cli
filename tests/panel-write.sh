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
import http.server, json, urllib.parse, datetime

WRITE = "write-test-token"
NO_BILLING = "no-billing-token"
BILLING = "billing-token"
RO = "ro-token"
RATE = "rate-token"
BAD = "bad-token"
CF = "cf-token"
state = {
    "server_polls": 0,
    "site_polls": 0,
    "purchase_posts": 0,
    "purchase_attempts": 0,
    "purchase_polls": 0,
    "large_catalog": False,
    "purchases": {},
    "rejected_once": [],
    "poll_failures": {},
    "next_purchase_id": 41,
}
abilities = {
    WRITE: {"user:read", "ssh:authorize", "servers:write", "sites:write", "billing:request"},
    NO_BILLING: {"user:read", "servers:write", "sites:write"},
    BILLING: {"billing:request"},
    RATE: {"user:read", "billing:request"},
    RO: {"user:read"},
}
VALID_PAIRS = {(12, 13), (12, 14), (20, 13), (30, 40), (31, 41),
               (40, 50), (40, 51), (41, 60), (42, 70)}

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def present(rec):
    return {
        "id": rec["id"],
        "status": rec["status"],
        "approval_url": rec["approval_url"],
        "expires_at": rec["expires_at"],
        "created_at": rec["created_at"],
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
        self.wfile.write(body)

    def _html(self, code, body):
        body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        return self.headers.get("Authorization", "")

    def _token(self):
        auth = self._auth()
        return auth[7:] if auth.startswith("Bearer ") else ""

    def _can(self, ability):
        return ability in abilities.get(self._token(), set())

    def _purchase(self, req_id):
        for rec in state["purchases"].values():
            if rec["id"] == req_id:
                return rec
        return None

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        if url.path == "/__stats":
            self._json(200, {
                "purchase_posts": state["purchase_posts"],
                "purchase_attempts": state["purchase_attempts"],
                "purchase_polls": state["purchase_polls"],
                "purchase_requests": len(state["purchases"]),
                "purchase_ids": sorted(rec["id"] for rec in state["purchases"].values()),
            })
            return
        if url.path == "/__large/1":
            state["large_catalog"] = True
            self._json(200, {"large": True})
            return
        if url.path == "/__large/0":
            state["large_catalog"] = False
            self._json(200, {"large": False})
            return
        if self._token() == CF and url.path == "/api/v1/billing/offers":
            self._html(403, "<html><title>Cloudflare Access</title><body>Just a moment</body></html>")
            return
        if self._token() == RATE and url.path.startswith("/api/v1/billing/purchase-requests"):
            self._json(429, {"code": "rate_limited", "message": "Too many requests."}, {"Retry-After": "7"})
            return
        if not self._can("user:read"):
            if self._token() == BILLING:
                self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            else:
                self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        if url.path == "/api/v1/providers":
            # The panel retired this legacy contract; the CLI must fall back
            # to the offers catalog instead of reporting an account error.
            self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
        elif url.path == "/api/v1/billing/offers":
            self._json(200, {"data": [
                {"offer_id": 12, "code": "HE-ARM-4GB", "display_name": "HE-ARM-4GB",
                 "family": "arm", "family_label": "ARM",
                 "specs": {"ram_gb": 4, "vcpu": 2, "disk_gb": 40, "bandwidth_tb": 20},
                 "provider": "Hetzner Cloud",
                 "plan": "(cax11) 4GB RAM - CPU 2 cores - Disk: 40GB",
                 "price": {"amount_cents": 4000, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 13, "label": "Falkenstein DC Park 1"}},
                {"offer_id": 12, "code": "HE-ARM-4GB", "display_name": "HE-ARM-4GB",
                 "family": "arm", "family_label": "ARM",
                 "specs": {"ram_gb": 4, "vcpu": 2, "disk_gb": 40, "bandwidth_tb": 20},
                 "provider": "Hetzner Cloud",
                 "plan": "(cax11) 4GB RAM - CPU 2 cores - Disk: 40GB",
                 "price": {"amount_cents": 4000, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 14, "label": "Nuremberg DC Park 1"}},
                {"offer_id": 20, "code": "HE-AMD-8GB", "display_name": "HE-AMD-8GB",
                 "family": "amd", "family_label": "AMD",
                 "specs": {"ram_gb": 8, "vcpu": 4, "disk_gb": 80, "bandwidth_tb": 20},
                 "provider": "Hetzner Cloud",
                 "plan": "(cpx31) 8GB RAM - CPU 4 cores - Disk: 80GB",
                 "price": {"amount_cents": 7000, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 13, "label": "Falkenstein DC Park 1"}},
                {"offer_id": 30, "code": "AWS-STD-4GB", "display_name": "AWS-STD-4GB",
                 "family": "standard", "family_label": "Standard",
                 "specs": {"ram_gb": 4, "vcpu": 2, "disk_gb": 30, "bandwidth_tb": 5},
                 "provider": "Amazon Web Services", "plan": "t3.medium",
                 "price": {"amount_cents": 5000, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 40, "label": "us-east-1"}},
                {"offer_id": 31, "code": "AWS-COMP-4GB", "display_name": "AWS-COMP-4GB",
                 "family": "compute_optimized", "family_label": "Compute optimized",
                 "specs": {"ram_gb": 4, "vcpu": 2, "disk_gb": 30, "bandwidth_tb": 5},
                 "provider": "Amazon Web Services", "plan": "c5.large",
                 "price": {"amount_cents": 6000, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 41, "label": "us-east-2"}},
                {"offer_id": 40, "code": "DO-BASIC-2GB", "display_name": "DO-BASIC-2GB",
                 "family": None, "family_label": None,
                 "specs": {"ram_gb": 2, "vcpu": 1, "disk_gb": 50, "bandwidth_tb": 2},
                 "provider": "DigitalOcean", "plan": "s-1vcpu-2gb",
                 "price": {"amount_cents": 1200, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 50, "label": "nyc3"}},
                {"offer_id": 40, "code": "DO-BASIC-2GB", "display_name": "DO-BASIC-2GB",
                 "family": None, "family_label": None,
                 "specs": {"ram_gb": 2, "vcpu": 1, "disk_gb": 50, "bandwidth_tb": 2},
                 "provider": "DigitalOcean", "plan": "s-1vcpu-2gb",
                 "price": {"amount_cents": 1200, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 51, "label": "sfo3"}},
                {"offer_id": 41, "code": "VU-VPS-2GB", "display_name": "VU-VPS-2GB",
                 "family": None, "family_label": None,
                 "specs": {"ram_gb": 2, "vcpu": 1, "disk_gb": 55, "bandwidth_tb": 2},
                 "provider": "Vultr", "plan": "vhp-1c-2gb-amd",
                 "price": {"amount_cents": 1200, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 60, "label": "Frankfurt"}},
                {"offer_id": 42, "code": "UP-2XCPU-4GB", "display_name": "UP-2XCPU-4GB",
                 "family": None, "family_label": None,
                 "specs": {"ram_gb": 4, "vcpu": 2, "disk_gb": 80, "bandwidth_tb": 4},
                 "provider": "UpCloud", "plan": "2xCPU-4GB",
                 "price": {"amount_cents": 2400, "currency": "usd", "interval": "month", "interval_count": 1},
                 "region": {"id": 70, "label": "Helsinki"}},
            ] + ([{
                "offer_id": 1000 + i, "code": "BIG-%04d" % i, "display_name": "BIG-%04d" % i,
                "family": "standard", "family_label": "Standard",
                "specs": {"ram_gb": 4, "vcpu": 2, "disk_gb": 40, "bandwidth_tb": 20},
                "provider": "Provider with a deliberately long name for execve regression %04d" % i,
                "plan": "plan-%04d-with-a-long-technical-label-to-inflate-the-catalog-payload" % i,
                "price": {"amount_cents": 4000, "currency": "usd", "interval": "month", "interval_count": 1},
                "region": {"id": 1000 + i, "label": "Region %04d" % i},
            } for i in range(600)] if state["large_catalog"] else [])})
        elif url.path.startswith("/api/v1/billing/purchase-requests/"):
            if not self._can("billing:request"):
                self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
                return
            try:
                req_id = int(url.path.rsplit("/", 1)[1])
            except ValueError:
                self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
                return
            rec = self._purchase(req_id)
            if not rec:
                self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
                return
            state["purchase_polls"] += 1
            name = rec.get("name")
            if name in ("web-flaky-poll", "web-flaky-dead"):
                state["poll_failures"][name] = state["poll_failures"].get(name, 0) + 1
                if name == "web-flaky-dead" or state["poll_failures"][name] == 1:
                    self._json(503, {"code": "upstream.unavailable",
                                     "message": "The panel is temporarily unavailable."})
                    return
                # The retry succeeds and keeps advancing to a terminal state.
                rec["polls"] = rec.get("polls", 0) + 1
                rec["status"] = "fulfilled" if rec["polls"] >= 2 else "pending_approval"
            elif name == "web-poll":
                rec["polls"] = rec.get("polls", 0) + 1
                if rec["polls"] >= 4:
                    rec["status"] = "fulfilled"
                elif rec["polls"] >= 3:
                    rec["status"] = "provisioning"
                elif rec["polls"] >= 2:
                    rec["status"] = "paid"
                else:
                    rec["status"] = "pending_approval"
            elif name == "web-unknown":
                rec["status"] = "provisioning_unknown"
            elif name == "web-manual":
                rec["status"] = "manual_review"
            elif name == "web-cancelled":
                rec["status"] = "cancelled"
            elif name == "web-failed":
                rec["status"] = "failed"
            elif name == "web-approved":
                rec["status"] = "approved"
            elif name == "web-checkout":
                rec["status"] = "checkout_open"
            elif name == "web-paid":
                rec["status"] = "paid"
                rec["expires_at"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).isoformat()
            elif name == "web-provisioning":
                rec["status"] = "provisioning"
            elif name == "web-fulfilled":
                rec["status"] = "fulfilled"
                rec["expires_at"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).isoformat()
            elif name == "web-paused":
                rec["status"] = "paused"
            elif name == "web-expired":
                rec["status"] = "pending_approval"
                rec["expires_at"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).isoformat()
            self._json(200, {"data": present(rec)})
        elif url.path == "/api/v1/servers/7":
            state["server_polls"] += 1
            status = "active" if state["server_polls"] >= 2 else "busy"
            self._json(200, {"data": {"id": 7, "name": "web-7", "status": status}})
        elif url.path == "/api/v1/servers/9":
            self._json(200, {"data": {"id": 9, "name": "web-9", "status": "active"}})
        elif url.path == "/api/v1/servers/10":
            self._json(200, {"data": {"id": 10, "name": "paid-10", "status": "active"}})
        elif url.path == "/api/v1/servers":
            self._json(200, {"current_page": 1, "per_page": 100, "total": 2, "last_page": 1,
                             "data": [{"id": 9, "name": "web-9", "status": "active"},
                                      {"id": 10, "name": "paid-10", "status": "active"}]})
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
        if self._auth() == "Bearer " + RO:
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        if not abilities.get(self._token()):
            self._json(401, {"code": "personal_token.invalid", "message": "x", "hint": "y"})
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        url = urllib.parse.urlsplit(self.path).path
        if self._token() == RATE and url == "/api/v1/billing/purchase-requests":
            self._json(429, {"code": "rate_limited", "message": "Too many requests."}, {"Retry-After": "7"})
            return
        if url == "/api/v1/servers":
            if body.get("provider_id") == 99:
                self._json(404, {"code": "servers.provider_invalid", "message": "Bad provider.", "hint": ""})
            elif body.get("name") == "full":
                self._json(422, {"code": "servers.limit_reached", "message": "Limit.", "hint": ""})
            elif body.get("name") == "purchase":
                self._json(402, {"code": "servers.purchase_required",
                                 "message": "A paid server purchase is required before creating a server.",
                                 "hint": "Choose an offer and complete the approved checkout first."})
            elif body.get("name") == "retired":
                self._json(404, {"code": "not_found", "message": "Not found.", "hint": ""})
            else:
                state["server_polls"] = 0
                self._json(202, {"data": {"id": 7, "status": "busy"}})
        elif url == "/api/v1/billing/purchase-requests":
            if not self._can("billing:request"):
                self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
                return
            offer = body.get("offer_id")
            region = body.get("provider_region_id")
            name = body.get("name")
            key = body.get("idempotency_key")
            if not isinstance(offer, int) or not isinstance(region, int) or not name or not key:
                self._json(422, {"code": "validation.failed", "message": "Invalid purchase request.", "hint": ""})
                return
            state["purchase_attempts"] += 1
            if (offer, region) not in VALID_PAIRS:
                self._json(422, {"code": "billing.offer_unavailable",
                                 "message": "That offer or region is not available for checkout."})
                return
            if name == "web-422-once" and name not in state["rejected_once"]:
                state["rejected_once"].append(name)
                self._json(422, {"code": "billing.offer_unavailable",
                                 "message": "That offer or region is not available for checkout."})
                return
            existing = state["purchases"].get(key)
            if existing:
                if existing["offer_id"] != offer or existing["region_id"] != region or existing["name"] != name:
                    self._json(409, {"code": "billing.idempotency_conflict",
                                     "message": "That idempotency key was already used with a different request.",
                                     "hint": ""})
                    return
                self._json(200, {"data": present(existing)})
                return
            if name == "web-422":
                self._json(422, {"code": "billing.offer_unavailable",
                                 "message": "That offer or region is not available for checkout."})
                return
            req_id = state["next_purchase_id"]
            state["next_purchase_id"] += 1
            created = now()
            expires = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).isoformat()
            rec = {
                "id": req_id,
                "offer_id": offer,
                "region_id": region,
                "name": name,
                "status": "pending_approval",
                "approval_url": "http://127.0.0.1:18997/billing/purchase-requests/%d" % req_id,
                "expires_at": expires,
                "created_at": created,
                "polls": 0,
            }
            state["purchases"][key] = rec
            state["purchase_posts"] += 1
            if name == "web-timeout":
                # Create the purchase, then drop the connection before the
                # response. The retry must reuse the same key/request.
                self.close_connection = True
                return
            if name == "web-503":
                # Ambiguous outcome: the request exists but the response is 503.
                self._json(503, {"code": "upstream.unavailable",
                                 "message": "The purchase could not be confirmed."})
                return
            self._json(201, {"data": present(rec)})
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
        if not self._can("servers:write"):
            self._json(403, {"code": "personal_token.forbidden", "message": "Forbidden.", "hint": ""})
            return
        url = urllib.parse.urlsplit(self.path).path
        if url == "/api/v1/servers/9":
            self._json(200, {"data": {"id": 9, "deleted": True, "scheduled": False,
                                      "task_id": None, "message": "Server deleted."}})
        elif url == "/api/v1/servers/10":
            self._json(202, {"data": {"id": 10, "deleted": False, "scheduled": True,
                                      "task_id": 5,
                                      "message": "Deletion is scheduled for the end of the paid period. Cancel the subscription in the Polar portal."}})
        elif url == "/api/v1/sites/12":
            self._json(200, {"data": {"id": 12, "deleted": True}})
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

# --- providers: legacy endpoint retired, derived from offers ---
./plak.sh panel providers > "$tmpdir/providers.txt" 2> "$tmpdir/providers.err" || fail "providers fallback"
grep -q "Hetzner" "$tmpdir/providers.txt" || fail "providers rows"
grep -q "Falkenstein" "$tmpdir/providers.txt" || fail "providers regions"
grep -q "legacy /api/v1/providers endpoint is retired" "$tmpdir/providers.err" || fail "providers retired hint"
grep -q "plak panel offers" "$tmpdir/providers.err" || fail "providers offers hint"
if grep -q "Not found on this account" "$tmpdir/providers.txt" "$tmpdir/providers.err"; then
    fail "providers reported an account error"
fi
./plak.sh panel providers --json > "$tmpdir/providers.json" 2> "$tmpdir/providers-json.err" || fail "providers json"
python3 - "$tmpdir/providers.json" <<'PY' || fail "providers json shape"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["source"] == "billing/offers", data
by_name = {item["name"]: item for item in data["data"]}
assert "Hetzner Cloud" in by_name, by_name
hetzner = by_name["Hetzner Cloud"]
assert {region["id"] for region in hetzner["regions"]} == {13, 14}, hetzner
assert {plan["offer_id"] for plan in hetzner["plans"]} == {12, 20}, hetzner
PY
# The 404 mapping itself stays actionable even if a future panel moves the
# legacy route again (the command above already falls back).
plak_connect_load >/dev/null 2>&1 || fail "providers connection load"
PLAK_PANEL_URL_OUT="$PANEL"
set +e
plak_panel_get "$PANEL/api/v1/providers" 2> "$tmpdir/providers-404.err"
providers_404_rc=$?
set -e
[ "$providers_404_rc" -ne 0 ] || fail "providers 404 was not reported"
grep -q "legacy providers endpoint is not available" "$tmpdir/providers-404.err" || fail "providers 404 message"
grep -q "plak panel offers" "$tmpdir/providers-404.err" || fail "providers 404 guidance"

# --- transport failures are distinguished (timeout vs refused) ---
( PLAK_HTTP_CURL_EXIT=28; plak_panel_network_error ) 2> "$tmpdir/curl-timeout.err"
grep -q "took too long to respond" "$tmpdir/curl-timeout.err" || fail "curl 28 message"
( PLAK_HTTP_CURL_EXIT=7; plak_panel_network_error ) 2> "$tmpdir/curl-refused.err"
grep -q "Could not connect to the panel" "$tmpdir/curl-refused.err" || fail "curl 7 message"
if grep -q "Panel unreachable" "$tmpdir/curl-timeout.err" "$tmpdir/curl-refused.err"; then
    fail "transport failures collapsed into a generic unreachable message"
fi

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

# --- catalog: free account, reference prices, no Polar/checkout secrets ---
./plak.sh panel offers --json > "$tmpdir/offers.json" || fail "offers"
python3 - "$tmpdir/offers.json" <<'PY' || fail "offers json"
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
items = data["data"]
assert len(items) == 9, data
first = items[0]
assert first["offer_id"] == 12
assert first["region"]["id"] == 13
assert first["price"]["amount_cents"] == 4000
assert first["family"] == "arm"
assert {item["provider"] for item in items} == {
    "Hetzner Cloud", "Amazon Web Services", "DigitalOcean", "Vultr", "UpCloud"
}
families = {item["family"] for item in items}
assert {"arm", "amd", "standard", "compute_optimized"} <= families
assert None in families
arm_regions = {item["region"]["id"] for item in items if item["offer_id"] == 12}
assert arm_regions == {13, 14}, arm_regions
do_regions = {item["region"]["id"] for item in items if item["offer_id"] == 40}
assert do_regions == {50, 51}, do_regions
for needle in ("write-test-token", "checkout", "polar", "customer_portal", "client_secret"):
    assert needle.lower() not in raw.lower(), needle
PY
./plak.sh panel offers > "$tmpdir/offers.txt" || fail "offers human"
grep -q "Offer 12 · HE-ARM-4GB \\[ARM\\]" "$tmpdir/offers.txt" || fail "offers group arm"
[ "$(grep -c '^Offer 12 ' "$tmpdir/offers.txt")" -eq 1 ] || fail "offers did not group regions"
grep -q "Offer 20 · HE-AMD-8GB \\[AMD\\]" "$tmpdir/offers.txt" || fail "offers group amd"
grep -q "Offer 30 · AWS-STD-4GB \\[Standard\\]" "$tmpdir/offers.txt" || fail "offers group standard"
grep -q "Offer 31 · AWS-COMP-4GB \\[Compute optimized\\]" "$tmpdir/offers.txt" || fail "offers group compute"
grep -q "^Offer 40 · DO-BASIC-2GB$" "$tmpdir/offers.txt" || fail "offers null family header"
[ "$(grep -c '^Offer 40 ' "$tmpdir/offers.txt")" -eq 1 ] || fail "offers did not group null-family regions"
grep -q "^Offer 41 · VU-VPS-2GB$" "$tmpdir/offers.txt" || fail "offers null family vultr"
grep -q "^Offer 42 · UP-2XCPU-4GB$" "$tmpdir/offers.txt" || fail "offers null family upcloud"
if grep -q "\\[None\\]\\|\\[-\\]" "$tmpdir/offers.txt"; then fail "offers rendered an empty family"; fi
grep -q "Regions: nyc3 (50), sfo3 (51)" "$tmpdir/offers.txt" || fail "offers null family regions"
grep -q "Provider plan: Hetzner Cloud" "$tmpdir/offers.txt" || fail "offers provider plan"
grep -q "Specs: 4 GB RAM · 2 vCPU · 40 GB disk · 20 TB bandwidth" "$tmpdir/offers.txt" || fail "offers specs"
grep -q "Regions: Falkenstein DC Park 1 (13), Nuremberg DC Park 1 (14)" "$tmpdir/offers.txt" || fail "offers regions"
grep -q "40.00 USD/mo" "$tmpdir/offers.txt" || fail "offers price"
grep -q "Prices are references" "$tmpdir/offers.txt" || fail "offers price note"

./plak.sh panel offers --json --provider AWS > "$tmpdir/offers-aws.json" || fail "offers provider filter"
python3 - "$tmpdir/offers-aws.json" <<'PY' || fail "offers provider filter json"
import json, sys
items = json.load(open(sys.argv[1]))["data"]
assert len(items) == 2, items
assert {item["provider"] for item in items} == {"Amazon Web Services"}
PY
./plak.sh panel offers --json --family arm > "$tmpdir/offers-arm.json" || fail "offers family filter"
python3 - "$tmpdir/offers-arm.json" <<'PY' || fail "offers family filter json"
import json, sys
items = json.load(open(sys.argv[1]))["data"]
assert len(items) == 2, items
assert {item["family"] for item in items} == {"arm"}
PY
./plak.sh panel offers --json --region 13 > "$tmpdir/offers-region.json" || fail "offers region filter"
python3 - "$tmpdir/offers-region.json" <<'PY' || fail "offers region filter json"
import json, sys
items = json.load(open(sys.argv[1]))["data"]
assert len(items) == 2, items
assert {item["region"]["id"] for item in items} == {13}
PY
./plak.sh panel offers --json --region Nuremberg > "$tmpdir/offers-region-name.json" || fail "offers region name filter"
python3 - "$tmpdir/offers-region-name.json" <<'PY' || fail "offers region name filter json"
import json, sys
items = json.load(open(sys.argv[1]))["data"]
assert len(items) == 1, items
assert items[0]["region"]["id"] == 14
PY
./plak.sh panel offers --provider Nope > "$tmpdir/offers-empty.txt" || fail "offers empty filter"
grep -q "No offers match these filters" "$tmpdir/offers-empty.txt" || fail "offers empty message"

# --- large catalog is piped, not passed through the environment (E2BIG) ---
curl -fsS http://127.0.0.1:18997/__large/1 >/dev/null || fail "large catalog flag"
./plak.sh panel offers --json > "$tmpdir/offers-large.json" || fail "large catalog"
python3 - "$tmpdir/offers-large.json" <<'PY' || fail "large catalog json"
import json, sys
raw = open(sys.argv[1]).read()
assert len(raw) > 150000, len(raw)
items = json.loads(raw)["data"]
assert len(items) == 609, len(items)
PY
curl -fsS http://127.0.0.1:18997/__large/0 >/dev/null || fail "large catalog reset"

# --- buy-server: request + internal approval URL only ---
./plak.sh panel buy-server --offer 12 --region 13 --name web-41 --json > "$tmpdir/buy.json" || fail "buy-server"
python3 - "$tmpdir/buy.json" <<'PY' || fail "buy json"
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
assert data["request_id"] == 41, data
assert data["status"] == "pending_approval", data
assert data["approval_url"].endswith("/billing/purchase-requests/41"), data
assert data["approval_required"] is True
assert data["resumed"] is False
for needle in ("write-test-token", "checkout", "polar", "customer_portal", "client_secret", "idempotency"):
    assert needle.lower() not in raw.lower(), needle
PY
python3 - "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "purchase state"
import json, os, stat, sys
path = sys.argv[1]
raw = open(path).read()
assert "write-test-token" not in raw
assert "idempotency_key" in raw
mode = stat.S_IMODE(os.stat(path).st_mode)
assert mode == 0o600, oct(mode)
data = json.loads(raw)
assert any(rec.get("request_id") == 41 for rec in data["requests"].values())
PY
./plak.sh panel buy-server --offer 12 --region 13 --name web-41 > "$tmpdir/buy-human.txt" || fail "buy resumed"
grep -q "Existing purchase request #41 resumed" "$tmpdir/buy-human.txt" || fail "resume message"
grep -q "The CLI cannot approve or pay" "$tmpdir/buy-human.txt" || fail "approval warning"

stats_before=$(curl -fsS http://127.0.0.1:18997/__stats)
./plak.sh panel buy-server --offer 12 --region 13 --name web-41 --json > "$tmpdir/buy2.json" || fail "buy repeat"
stats_after=$(curl -fsS http://127.0.0.1:18997/__stats)
python3 - "$tmpdir/buy2.json" "$stats_before" "$stats_after" <<'PY' || fail "idempotent repeat"
import json, sys
data = json.load(open(sys.argv[1]))
before = json.loads(sys.argv[2])
after = json.loads(sys.argv[3])
assert data["request_id"] == 41 and data["resumed"] is True, data
assert before["purchase_attempts"] == after["purchase_attempts"], (before, after)
assert before["purchase_requests"] == after["purchase_requests"], (before, after)
PY

# --yes never approves or pays: the request stays pending.
./plak.sh panel buy-server --offer 12 --region 13 --name web-41 --yes --json > "$tmpdir/buy-yes.json" || fail "buy --yes"
python3 - "$tmpdir/buy-yes.json" <<'PY' || fail "--yes approval"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "pending_approval", data
assert data["approval_url"], data
PY
set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-41 --new --json > "$tmpdir/buy-new-open.json" 2>"$tmpdir/buy-new-open.err"
open_new_rc=$?
set -e
[ "$open_new_rc" -ne 0 ] || fail "--new accepted an open request"
grep -q "still 'pending_approval'" "$tmpdir/buy-new-open.err" || fail "--new open guidance"

# --- status query and bounded polling ---
./plak.sh panel purchase-request 41 --json > "$tmpdir/pr.json" || fail "purchase-request"
python3 - "$tmpdir/pr.json" <<'PY' || fail "purchase-request json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"] == 41
assert data["status"] == "pending_approval"
assert data["approval_url"]
PY
set +e
./plak.sh panel purchase-request 41 --wait 1 --poll 1 --json > "$tmpdir/pr-timeout.json" 2>/dev/null
pr_rc=$?
set -e
[ "$pr_rc" -eq 3 ] || fail "purchase-request timeout rc=$pr_rc"
python3 - "$tmpdir/pr-timeout.json" <<'PY' || fail "purchase timeout json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["timed_out"] is True, data
assert data["status"] == "pending_approval"
PY

./plak.sh panel buy-server --offer 12 --region 13 --name web-poll --wait 10 --poll 1 --json > "$tmpdir/poll.json" || fail "purchase poll"
python3 - "$tmpdir/poll.json" <<'PY' || fail "purchase poll json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "fulfilled", data
PY

# --- one transient 503 during a long poll is retried and does not abort ---
./plak.sh panel buy-server --offer 12 --region 13 --name web-flaky-poll --wait 10 --poll 1 --json \
    > "$tmpdir/flaky-poll.json" 2> "$tmpdir/flaky-poll.err" || fail "flaky poll aborted"
python3 - "$tmpdir/flaky-poll.json" <<'PY' || fail "flaky poll json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "fulfilled", data
assert not data.get("interrupted"), data
PY
grep -q "Transient panel error; retrying" "$tmpdir/flaky-poll.err" || fail "flaky poll retry hint"
grep -q "temporary" "$tmpdir/flaky-poll.err" || fail "flaky poll transient error message"

# --- persistent failures exhaust retries but never lose the request id ---
set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-flaky-dead --wait 10 --poll 1 --json \
    > "$tmpdir/flaky-dead.json" 2> "$tmpdir/flaky-dead.err"
flaky_dead_rc=$?
set -e
[ "$flaky_dead_rc" -ne 0 ] || fail "persistent poll failure reported success"
dead_id=$(python3 - "$tmpdir/flaky-dead.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"], data
assert data.get("interrupted") is True, data
assert data["status"] == "pending_approval", data
assert "purchase-request %s --wait 10 --poll 1" % data["request_id"] in data["resume_command"], data
print(data["request_id"])
PY
) || fail "interrupted poll json"

# Human output keeps the id and the exact resume command too.
set +e
./plak.sh panel purchase-request "$dead_id" --wait 10 --poll 1 \
    > "$tmpdir/flaky-dead-human.txt" 2> "$tmpdir/flaky-dead-human.err"
flaky_dead_human_rc=$?
set -e
[ "$flaky_dead_human_rc" -ne 0 ] || fail "persistent human poll reported success"
grep -q "Purchase request #$dead_id" "$tmpdir/flaky-dead-human.txt" || fail "interrupted poll lost the id"
grep -q "Status: pending approval" "$tmpdir/flaky-dead-human.txt" || fail "interrupted poll lost the known status"
grep -q "Polling stopped after repeated panel errors" "$tmpdir/flaky-dead-human.txt" || fail "interrupted poll message"
grep -q "Resume with 'plak panel purchase-request $dead_id --wait 10 --poll 1'" "$tmpdir/flaky-dead-human.txt" || fail "interrupted poll resume command"

set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-expired --wait 2 --poll 1 --json > "$tmpdir/expired.json" 2>/dev/null
expired_rc=$?
set -e
[ "$expired_rc" -ne 0 ] || fail "expired request accepted"
python3 - "$tmpdir/expired.json" <<'PY' || fail "expired json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["expired"] is True, data
assert data["status"] == "pending_approval"
PY
expired_id=$(python3 - "$tmpdir/expired.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["request_id"])
PY
)
./plak.sh panel buy-server --offer 12 --region 13 --name web-expired --new --json > "$tmpdir/expired-new.json" || fail "new after expired"
python3 - "$tmpdir/expired-new.json" "$expired_id" <<'PY' || fail "new after expired json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"] != int(sys.argv[2]), data
assert data["status"] == "pending_approval", data
PY

set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-unknown --wait 2 --poll 1 --json > "$tmpdir/unknown.json" 2>/dev/null
unknown_rc=$?
set -e
[ "$unknown_rc" -eq 3 ] || fail "unknown rc=$unknown_rc"
python3 - "$tmpdir/unknown.json" <<'PY' || fail "unknown json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "provisioning_unknown", data
assert data["ambiguous"] is True
PY

set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-failed --wait 2 --poll 1 --json > "$tmpdir/failed.json" 2>/dev/null
failed_rc=$?
set -e
[ "$failed_rc" -ne 0 ] || fail "failed request reported success"
failed_id=$(python3 - "$tmpdir/failed.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["request_id"])
PY
)
./plak.sh panel buy-server --offer 12 --region 13 --name web-failed --new --json > "$tmpdir/failed-new.json" || fail "new after failed"
python3 - "$tmpdir/failed-new.json" "$failed_id" <<'PY' || fail "new request id"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"] != int(sys.argv[2]), data
assert data["status"] == "pending_approval"
PY

# --- lost response is retried with the same key and never duplicates ---
set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-timeout --json > "$tmpdir/timeout1.json" 2>"$tmpdir/timeout1.err"
timeout_rc=$?
set -e
[ "$timeout_rc" -ne 0 ] || fail "lost purchase response accepted"
python3 - "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "timeout state"
import json, sys
data = json.load(open(sys.argv[1]))
rec = next(rec for rec in data["requests"].values() if rec.get("name") == "web-timeout")
assert rec.get("request_id") is None, rec
assert rec.get("idempotency_key"), rec
PY
timeout_stats_before=$(curl -fsS http://127.0.0.1:18997/__stats)
set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-timeout --new --json > "$tmpdir/timeout-new.json" 2>"$tmpdir/timeout-new.err"
timeout_new_rc=$?
set -e
[ "$timeout_new_rc" -ne 0 ] || fail "--new accepted an unresolved timeout"
grep -q "unresolved" "$tmpdir/timeout-new.err" || fail "unresolved --new guidance"
timeout_stats_after=$(curl -fsS http://127.0.0.1:18997/__stats)
python3 - "$timeout_stats_before" "$timeout_stats_after" <<'PY' || fail "unresolved --new created a purchase"
import json, sys
before = json.loads(sys.argv[1])
after = json.loads(sys.argv[2])
assert before["purchase_attempts"] == after["purchase_attempts"], (before, after)
assert before["purchase_requests"] == after["purchase_requests"], (before, after)
PY
timeout_retry_before=$(curl -fsS http://127.0.0.1:18997/__stats)
./plak.sh panel buy-server --offer 12 --region 13 --name web-timeout --json > "$tmpdir/timeout2.json" || fail "timeout retry"
timeout_retry_after=$(curl -fsS http://127.0.0.1:18997/__stats)
python3 - "$timeout_retry_before" "$timeout_retry_after" <<'PY' || fail "timeout retry created a purchase"
import json, sys
before = json.loads(sys.argv[1])
after = json.loads(sys.argv[2])
assert after["purchase_attempts"] == before["purchase_attempts"] + 1, (before, after)
assert before["purchase_requests"] == after["purchase_requests"], (before, after)
PY
python3 - "$tmpdir/timeout2.json" "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "timeout retry json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"], data
assert data["status"] == "pending_approval", data
state = json.load(open(sys.argv[2]))
rec = next(rec for rec in state["requests"].values() if rec.get("name") == "web-timeout")
assert rec.get("request_id") == data["request_id"], (rec, data)
PY

# --- 409 conflict, 422 offer unavailable and ambiguous 503 ---
./plak.sh panel buy-server --offer 12 --region 13 --name conflict-a --idempotency-key fixed-key --json > "$tmpdir/conflict-a.json" || fail "conflict seed"
set +e
./plak.sh panel buy-server --offer 30 --region 40 --name conflict-b --idempotency-key fixed-key --json > "$tmpdir/conflict-b.json" 2>"$tmpdir/conflict-b.err"
conflict_rc=$?
set -e
[ "$conflict_rc" -ne 0 ] || fail "idempotency conflict accepted"
grep -q "idempotency key was already used" "$tmpdir/conflict-b.err" || fail "idempotency conflict message"
grep -q "different purchase data" "$tmpdir/conflict-b.err" || fail "idempotency conflict guidance"
python3 - "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "409 state"
import json, sys
data = json.load(open(sys.argv[1]))
rec = next(rec for rec in data["requests"].values() if rec.get("name") == "conflict-b")
assert rec.get("status") == "failed", rec
assert rec.get("request_id") is None, rec
PY
./plak.sh panel buy-server --offer 30 --region 40 --name conflict-b --new --json > "$tmpdir/conflict-b-new.json" || fail "new after 409"
python3 - "$tmpdir/conflict-b-new.json" <<'PY' || fail "new after 409 json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"], data
assert data["status"] == "pending_approval", data
PY

set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-422 --json > "$tmpdir/offer-422.json" 2>"$tmpdir/offer-422.err"
offer_422_rc=$?
set -e
[ "$offer_422_rc" -ne 0 ] || fail "offer unavailable accepted"
grep -q "not available for checkout" "$tmpdir/offer-422.err" || fail "offer unavailable message"
grep -q "plak panel offers" "$tmpdir/offer-422.err" || fail "offer unavailable guidance"
python3 - "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "422 state"
import json, sys
data = json.load(open(sys.argv[1]))
rec = next(rec for rec in data["requests"].values() if rec.get("name") == "web-422")
assert rec.get("status") == "failed", rec
assert rec.get("request_id") is None, rec
PY

set +e
./plak.sh panel buy-server --offer 999 --region 999 --name bad-pair --json > "$tmpdir/bad-pair.json" 2>"$tmpdir/bad-pair.err"
bad_pair_rc=$?
set -e
[ "$bad_pair_rc" -ne 0 ] || fail "invalid offer/region accepted"
grep -q "not available for checkout" "$tmpdir/bad-pair.err" || fail "invalid pair message"

set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-422-once --json > "$tmpdir/422-once.json" 2>"$tmpdir/422-once.err"
once_rc=$?
set -e
[ "$once_rc" -ne 0 ] || fail "one-time 422 accepted"
./plak.sh panel buy-server --offer 12 --region 13 --name web-422-once --new --json > "$tmpdir/422-once-new.json" || fail "new after 422"
python3 - "$tmpdir/422-once-new.json" <<'PY' || fail "new after 422 json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"], data
assert data["status"] == "pending_approval", data
PY

set +e
./plak.sh panel buy-server --offer 12 --region 13 --name web-503 --json > "$tmpdir/503.json" 2>"$tmpdir/503.err"
ambig_rc=$?
set -e
[ "$ambig_rc" -ne 0 ] || fail "ambiguous 503 accepted"
grep -q "outcome is ambiguous" "$tmpdir/503.err" || fail "503 ambiguity message"
python3 - "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "503 state"
import json, sys
data = json.load(open(sys.argv[1]))
rec = next(rec for rec in data["requests"].values() if rec.get("name") == "web-503")
assert rec.get("request_id") is None, rec
assert rec.get("idempotency_key"), rec
PY
stats_503_before=$(curl -fsS http://127.0.0.1:18997/__stats)
./plak.sh panel buy-server --offer 12 --region 13 --name web-503 --json > "$tmpdir/503-retry.json" || fail "503 retry"
stats_503_after=$(curl -fsS http://127.0.0.1:18997/__stats)
python3 - "$stats_503_before" "$stats_503_after" <<'PY' || fail "503 retry created a purchase"
import json, sys
before = json.loads(sys.argv[1])
after = json.loads(sys.argv[2])
assert after["purchase_attempts"] == before["purchase_attempts"] + 1, (before, after)
assert before["purchase_requests"] == after["purchase_requests"], (before, after)
PY
python3 - "$tmpdir/503-retry.json" "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "503 retry json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"], data
state = json.load(open(sys.argv[2]))
rec = next(rec for rec in state["requests"].values() if rec.get("name") == "web-503")
assert rec.get("request_id") == data["request_id"], (rec, data)
PY

# --- every documented purchase status is classified correctly ---
purchase_status_check() {
    local name="$1" offer="$2" region="$3" expected="$4" expected_rc="$5" expected_ambiguous="$6"
    local buy_json="$tmpdir/status-$name-buy.json" status_json="$tmpdir/status-$name.json" req_id rc
    ./plak.sh panel buy-server --offer "$offer" --region "$region" --name "$name" --json > "$buy_json" || fail "status buy $name"
    req_id=$(python3 - "$buy_json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["request_id"])
PY
)
    set +e
    ./plak.sh panel purchase-request "$req_id" --json > "$status_json" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq "$expected_rc" ] || fail "status $name rc=$rc"
    python3 - "$status_json" "$expected" "$expected_ambiguous" <<'PY' || fail "status $name json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == sys.argv[2], data
assert bool(data.get("ambiguous")) is (sys.argv[3] == "1"), data
pending = data["status"] in ("pending_approval", "approved", "checkout_open")
assert data["approval_required"] is pending, data
if not pending:
    assert not data.get("expired"), data
PY
}

purchase_status_check web-approved 12 13 approved 0 0
purchase_status_check web-checkout 12 14 checkout_open 0 0
purchase_status_check web-paid 20 13 paid 0 0
purchase_status_check web-provisioning 30 40 provisioning 0 0
purchase_status_check web-fulfilled 31 41 fulfilled 0 0
purchase_status_check web-cancelled 12 13 cancelled 1 0
purchase_status_check web-manual 12 14 manual_review 3 1
purchase_status_check web-paused 12 13 paused 3 1
set +e
./plak.sh panel buy-server --offer 20 --region 13 --name web-paid --new --json > "$tmpdir/paid-new.json" 2>"$tmpdir/paid-new.err"
paid_new_rc=$?
set -e
[ "$paid_new_rc" -ne 0 ] || fail "--new accepted a paid request"
grep -q "is 'paid'" "$tmpdir/paid-new.err" || fail "paid --new guidance"
set +e
./plak.sh panel buy-server --offer 12 --region 14 --name web-manual --new --json > "$tmpdir/manual-new.json" 2>"$tmpdir/manual-new.err"
manual_new_rc=$?
set -e
[ "$manual_new_rc" -ne 0 ] || fail "--new accepted an ambiguous request"
grep -q "needs panel/support review" "$tmpdir/manual-new.err" || fail "--new ambiguous guidance"

seed_conn "billing-token"
./plak.sh panel buy-server --offer 12 --region 13 --name billing-only --json > "$tmpdir/billing-only.json" || fail "billing-only buy-server"
python3 - "$tmpdir/billing-only.json" <<'PY' || fail "billing-only buy-server json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["request_id"], data
assert data["status"] == "pending_approval", data
PY
set +e
./plak.sh panel offers --json > "$tmpdir/billing-only-offers.json" 2>"$tmpdir/billing-only-offers.err"
billing_offers_rc=$?
set -e
[ "$billing_offers_rc" -ne 0 ] || fail "billing-only token listed offers"
grep -q "user:read" "$tmpdir/billing-only-offers.err" || fail "billing-only offers scope hint"

seed_conn "ro-token"
./plak.sh panel offers --json > "$tmpdir/offers-readonly.json" || fail "read-only catalog"
python3 - "$tmpdir/offers-readonly.json" <<'PY' || fail "read-only catalog json"
import json, sys
items = json.load(open(sys.argv[1]))["data"]
assert len(items) == 9, items
PY
seed_conn "no-billing-token"
./plak.sh panel offers --json > "$tmpdir/offers-free.json" || fail "free catalog"
./plak.sh panel buy-server --offer 12 --region 13 --name scope-test --json 2>"$tmpdir/billing-scope.txt" >/dev/null && fail "billing scope accepted"
grep -q "billing:request" "$tmpdir/billing-scope.txt" || fail "billing scope hint"
grep -q "cannot approve or pay" "$tmpdir/billing-scope.txt" || fail "billing scope explanation"
./plak.sh panel purchase-request 41 --json 2>"$tmpdir/billing-read-scope.txt" >/dev/null && fail "billing read scope accepted"
grep -q "billing:request" "$tmpdir/billing-read-scope.txt" || fail "billing read scope hint"
seed_conn "write-test-token"

# --- auth, rate limit and Cloudflare Access stay actionable ---
seed_conn "bad-token"
./plak.sh panel purchase-request 41 --json 2>"$tmpdir/bad-token.txt" >/dev/null && fail "bad token accepted"
grep -q "Token invalid" "$tmpdir/bad-token.txt" || fail "bad token message"
seed_conn "rate-token"
./plak.sh panel purchase-request 41 --json 2>"$tmpdir/rate-read.txt" >/dev/null && fail "rate-limited read accepted"
grep -q "Rate limited" "$tmpdir/rate-read.txt" || fail "rate read message"
grep -q "7" "$tmpdir/rate-read.txt" || fail "rate retry-after"
grep -q "Polling stopped for purchase request #41" "$tmpdir/rate-read.txt" || fail "rate read lost the request id"
rate_before=$(curl -fsS http://127.0.0.1:18997/__stats)
./plak.sh panel buy-server --offer 12 --region 13 --name rate-test --json 2>"$tmpdir/rate-write.txt" >/dev/null && fail "rate-limited purchase accepted"
grep -q "Rate limited" "$tmpdir/rate-write.txt" || fail "rate write message"
rate_after=$(curl -fsS http://127.0.0.1:18997/__stats)
python3 - "$rate_before" "$rate_after" <<'PY' || fail "rate limit persisted a purchase"
import json, sys
before = json.loads(sys.argv[1])
after = json.loads(sys.argv[2])
assert before["purchase_requests"] == after["purchase_requests"], (before, after)
PY
seed_conn "cf-token"
./plak.sh panel offers 2>"$tmpdir/cf-access.txt" >/dev/null && fail "Cloudflare Access page accepted"
grep -q "Cloudflare Access" "$tmpdir/cf-access.txt" || fail "Cloudflare Access hint"
seed_conn "write-test-token"

# --- local purchase list ---
./plak.sh panel purchases --json > "$tmpdir/purchases.json" || fail "purchases"
python3 - "$tmpdir/purchases.json" <<'PY' || fail "purchases json"
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
assert data["data"], data
assert any(item.get("request_id") == 41 for item in data["data"]), data
for item in data["data"]:
    if item.get("status") not in ("pending_approval", "approved", "checkout_open"):
        assert item.get("expired") is False, item
assert "write-test-token" not in raw
assert "idempotency_key" not in raw
PY
./plak.sh panel purchases > "$tmpdir/purchases.txt" || fail "purchases human"
grep -q "REQUEST" "$tmpdir/purchases.txt" || fail "purchases table"

# --- corrupt local state fails closed, never starts a purchase ---
cp "$PLAK_HOME/panel-purchases.json" "$tmpdir/purchases-backup.json"
printf 'not json\n' > "$PLAK_HOME/panel-purchases.json"
corrupt_stats_before=$(curl -fsS http://127.0.0.1:18997/__stats)
set +e
./plak.sh panel buy-server --offer 12 --region 13 --name corrupt-state --json > "$tmpdir/corrupt-state.json" 2>"$tmpdir/corrupt-state.err"
corrupt_rc=$?
set -e
[ "$corrupt_rc" -ne 0 ] || fail "corrupt state accepted"
grep -q "Cannot read the local purchase state" "$tmpdir/corrupt-state.err" || fail "corrupt state message"
set +e
./plak.sh panel purchases --json > "$tmpdir/corrupt-list.json" 2>"$tmpdir/corrupt-list.err"
corrupt_list_rc=$?
set -e
[ "$corrupt_list_rc" -ne 0 ] || fail "corrupt list accepted"
grep -q "Cannot read" "$tmpdir/corrupt-list.err" || fail "corrupt list message"
corrupt_stats_after=$(curl -fsS http://127.0.0.1:18997/__stats)
python3 - "$corrupt_stats_before" "$corrupt_stats_after" <<'PY' || fail "corrupt state created a purchase"
import json, sys
before = json.loads(sys.argv[1])
after = json.loads(sys.argv[2])
assert before["purchase_attempts"] == after["purchase_attempts"], (before, after)
assert before["purchase_requests"] == after["purchase_requests"], (before, after)
PY
cp "$tmpdir/purchases-backup.json" "$PLAK_HOME/panel-purchases.json"
chmod 600 "$PLAK_HOME/panel-purchases.json"

# --- three independent requests stay isolated ---
./plak.sh panel buy-server --offer 12 --region 13 --name iso-a --json > "$tmpdir/iso-a.json" || fail "iso a"
./plak.sh panel buy-server --offer 30 --region 40 --name iso-b --json > "$tmpdir/iso-b.json" || fail "iso b"
./plak.sh panel buy-server --offer 12 --region 14 --name iso-c --json > "$tmpdir/iso-c.json" || fail "iso c"
python3 - "$tmpdir/iso-a.json" "$tmpdir/iso-b.json" "$tmpdir/iso-c.json" "$PLAK_HOME/panel-purchases.json" <<'PY' || fail "isolated purchases"
import json, sys
requests = [json.load(open(path)) for path in sys.argv[1:4]]
ids = [item["request_id"] for item in requests]
assert len(set(ids)) == 3, ids
state = json.load(open(sys.argv[4]))
records = list(state["requests"].values())
for name, offer, region in (("iso-a", 12, 13), ("iso-b", 30, 40), ("iso-c", 12, 14)):
    matches = [rec for rec in records if rec.get("name") == name]
    assert len(matches) == 1, (name, matches)
    assert matches[0]["offer_id"] == offer and matches[0]["region_id"] == region, (name, matches)
PY

# --- help and agent contract do not teach a bypass ---
./plak.sh panel help > "$tmpdir/panel-help.txt" || fail "panel help"
for needle in "offers" "buy-server" "purchase-request" "billing:request" "purchase_required"; do
    grep -q "$needle" "$tmpdir/panel-help.txt" || fail "panel help lacks $needle"
done
grep -qi "approve or pay" skills/plak-cli/SKILL.md || fail "skill lacks approval prohibition"
grep -q "D14/D21" skills/plak-cli/SKILL.md || fail "skill lacks manual backend distinction"
grep -q "provisioning_unknown" docs/panel.md || fail "panel docs lack ambiguous statuses"
# --- legacy create-server is retired, never global/comped ---
./plak.sh panel create-server --name purchase --provider 1 --region 2 --plan 3 2>"$tmpdir/purchase-required.txt" >/dev/null && fail "purchase_required accepted"
grep -q "plak panel offers" "$tmpdir/purchase-required.txt" || fail "purchase_required offers hint"
grep -q "buy-server" "$tmpdir/purchase-required.txt" || fail "purchase_required buy-server hint"
./plak.sh panel create-server --name retired --provider 1 --region 2 --plan 3 2>"$tmpdir/retired.txt" >/dev/null && fail "retired create-server accepted"
grep -qi "retired" "$tmpdir/retired.txt" || fail "retired route hint"
grep -qi "no global or comped" "$tmpdir/retired.txt" || fail "no fallback hint"

# --- paid server deletion is a scheduled cancellation, not immediate ---
./plak.sh panel delete-server paid-10 --yes --json > "$tmpdir/paid-delete.json" || fail "paid delete"
python3 - "$tmpdir/paid-delete.json" <<'PY' || fail "paid delete json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["deleted"] is False, data
assert data["scheduled"] is True, data
assert data["task_id"] == 5, data
assert "end of the paid period" in data["message"], data
PY
./plak.sh panel delete-server paid-10 --yes > "$tmpdir/paid-delete.txt" 2>/dev/null || fail "paid delete human"
grep -q "end of the paid period" "$tmpdir/paid-delete.txt" || fail "paid delete message"
grep -q "No immediate server deletion" "$tmpdir/paid-delete.txt" || fail "paid delete immediate warning"
grep -q "Scheduled billing task: #5" "$tmpdir/paid-delete.txt" || fail "paid delete task id"
if grep -qi "server deleted" "$tmpdir/paid-delete.txt"; then fail "paid delete claimed immediate deletion"; fi

echo "panel-write tests passed"
