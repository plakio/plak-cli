#!/usr/bin/env bash
# Opt-in real Caddy/FrankenPHP HTTP and verified TLS, no global trust changes.
# shellcheck disable=SC1091,SC2329 # Sourced CLI and stubbed presentation helper.
set -euo pipefail
[ -n "${PLAK_TEST_FRANKENPHP:-}" ] || { echo 'Static TLS live test skipped: set PLAK_TEST_FRANKENPHP'; exit 0; }
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d /tmp/opencode/plak-static-test.XXXXXX)
pid=""
cleanup() { [ -z "$pid" ] || { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }; rm -rf "$tmpdir"; }
trap cleanup EXIT
export HOME="$tmpdir/home" PLAK_NO_PATH_PRELUDE=1 XDG_DATA_HOME="$tmpdir/data" XDG_CONFIG_HOME="$tmpdir/config"
mkdir -p "$HOME"
source "$ROOT_DIR/plak.sh" >/dev/null
gum() { return 0; }
plak_site_add static --plain --no-reload > "$tmpdir/add"
public="$SITES_DIR/static.localhost/public"
printf 'custom index\n' > "$public/index.html"
printf 'body { color: blue; }\n' > "$public/styles.css"
printf 'console.log("custom");\n' > "$public/app.js"
read -r http_port https_port admin_port < <(python3 - <<'PY'
import socket
sockets=[socket.socket() for _ in range(3)]
for s in sockets: s.bind(('127.0.0.1',0))
print(*(s.getsockname()[1] for s in sockets))
PY
)
cat > "$tmpdir/Caddyfile" <<CADDY
{
  admin 127.0.0.1:$admin_port
  skip_install_trust
  default_bind 127.0.0.1
  http_port $http_port
  https_port $https_port
}
https://static.localhost:$https_port {
  root * "$public"
  tls internal
  file_server
}
CADDY
"$PLAK_TEST_FRANKENPHP" run --config "$tmpdir/Caddyfile" > "$tmpdir/server" 2>&1 &
pid=$!
root="$XDG_DATA_HOME/caddy/pki/authorities/local/root.crt"
for _ in {1..100}; do
    if [ -r "$root" ] && curl --noproxy '*' --cacert "$root" --resolve "static.localhost:$https_port:127.0.0.1" -fsS --max-time 1 "https://static.localhost:$https_port/" > "$tmpdir/index" 2>/dev/null; then break; fi
    sleep 0.1
done
cmp "$public/index.html" "$tmpdir/index"
for asset in styles.css app.js; do
    curl --noproxy '*' --cacert "$root" --resolve "static.localhost:$https_port:127.0.0.1" -fsS --max-time 5 "https://static.localhost:$https_port/$asset" > "$tmpdir/asset"
    cmp "$public/$asset" "$tmpdir/asset"
done
echo 'Plain site/custom HTML/CSS/JS with verified isolated local-CA HTTPS passed (Linux, not Windows)'
