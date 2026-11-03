#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

if ! command -v php >/dev/null 2>&1; then
    echo "HTML editor regression test skipped: php not available."
    exit 0
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "HTML editor regression test skipped: curl not available."
    exit 0
fi

tmpdir=$(mktemp -d)
editor_pid=""
router_pid=""
cleanup() {
    [ -z "$editor_pid" ] || kill "$editor_pid" 2>/dev/null || true
    [ -z "$router_pid" ] || kill "$router_pid" 2>/dev/null || true
    [ -z "$editor_pid" ] || wait "$editor_pid" 2>/dev/null || true
    [ -z "$router_pid" ] || wait "$router_pid" 2>/dev/null || true
    rm -rf "$tmpdir"
}
trap cleanup EXIT

fail() {
    echo "HTML editor regression failed: $*" >&2
    exit 1
}

free_port() {
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
}

export HOME="$tmpdir/home"
mkdir -p "$HOME/Plak/Sites/foo.localhost/public"
printf '<!doctype html><html><body><p>Hello editor</p></body></html>\n' > "$HOME/Plak/Sites/foo.localhost/public/index.html"

(
    source ./plak.sh >/dev/null 2>&1
    create_gui_file
) >/dev/null

GUI_DIR="$HOME/Plak/App/gui"
APP_DIR="$HOME/Plak/App"
SITES_DIR="$HOME/Plak/Sites"
CADDYFILE_PATH="$HOME/Plak/Caddyfile"
LOGS_DIR="$HOME/Plak/Logs"
CUSTOM_CADDY_DIR="$HOME/Plak/App/directives"
PLAK_SITE_DIR="$HOME/Plak"

for file in \
    "$GUI_DIR/editor/index.php" \
    "$GUI_DIR/editor/api.php" \
    "$GUI_DIR/editor/editor.js" \
    "$GUI_DIR/editor/loader.js" \
    "$APP_DIR/lib/html-site.php" \
    "$APP_DIR/site-router/render.php"; do
    [ -f "$file" ] || fail "missing generated file: $file"
done
for file in \
    "$GUI_DIR/editor/index.php" \
    "$GUI_DIR/editor/api.php" \
    "$APP_DIR/lib/html-site.php" \
    "$APP_DIR/site-router/render.php"; do
    php -l "$file" >/dev/null || fail "invalid PHP: $file"
done
grep -q 'editor.js?v=' "$GUI_DIR/editor/index.php" || fail "editor.js is not cache-busted"
grep -q 'editor.css?v=' "$GUI_DIR/editor/index.php" || fail "editor.css is not cache-busted"
grep -q 'loader.js?v=' "$APP_DIR/site-router/render.php" || fail "loader.js is not cache-busted"
grep -q "addEventListener('input'" "$GUI_DIR/editor/editor.js" || fail "editor does not commit on input"
grep -q 'data-plak-format="bold"' "$GUI_DIR/editor/editor.js" || fail "editor lacks the bold format control"
grep -q 'plak-image-drop' "$GUI_DIR/editor/editor.js" || fail "editor lacks the image drop target"
grep -q 'id="undo"' "$GUI_DIR/editor/index.php" || fail "editor lacks the undo control"
grep -q 'id="redo"' "$GUI_DIR/editor/index.php" || fail "editor lacks the redo control"
grep -q 'id="theme-toggle"' "$GUI_DIR/editor/index.php" || fail "editor lacks the theme control"
grep -q 'plak-editor-theme' "$GUI_DIR/editor/index.php" || fail "editor theme is not persisted"

editor_port=$(free_port)
router_port=$(free_port)
while [ "$router_port" = "$editor_port" ]; do
    router_port=$(free_port)
done
php -S 127.0.0.1:"$editor_port" -t "$GUI_DIR/editor" >"$tmpdir/editor.log" 2>&1 &
editor_pid=$!
php -S 127.0.0.1:"$router_port" "$APP_DIR/site-router/render.php" >"$tmpdir/router.log" 2>&1 &
router_pid=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 1 "http://127.0.0.1:$editor_port/?site=foo" >"$tmpdir/page.html" 2>/dev/null; then
        break
    fi
    sleep 0.2
done
grep -q 'plak-csrf' "$tmpdir/page.html" || fail "editor page did not render"
token=$(cat "$HOME/Plak/cache/dashboard-token")
[ "${#token}" -eq 64 ] || fail "editor token was not created"

api() {
    local action="$1"
    shift
    curl -fsS -H "X-Plak-CSRF: $token" -H "Origin: http://127.0.0.1:$editor_port" \
        "http://127.0.0.1:$editor_port/api.php?action=$action&site=foo&$*"
}

files=$(api files)
grep -q '"path":"index.html"' <<<"$files" || fail "files API omitted index.html"

# Browsers omit Origin on same-origin GET, and the editor page sends no
# Referer, so a same-origin GET must still work with only the CSRF token.
same_origin=$(curl -fsS -H "X-Plak-CSRF: $token" \
    "http://127.0.0.1:$editor_port/api.php?action=files&site=foo") \
    || fail "same-origin GET without Origin/Referer was rejected"
grep -q '"path":"index.html"' <<<"$same_origin" || fail "same-origin GET omitted index.html"

status=$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Plak-CSRF: $token" \
    -H "Origin: http://evil.example" \
    "http://127.0.0.1:$editor_port/api.php?action=files&site=foo")
[ "$status" = "403" ] || fail "cross-origin Origin was not rejected"
read_json=$(api read "file=index.html")
base_sha=$(printf '%s' "$read_json" | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo $d["sha256"] ?? "";')
[ -n "$base_sha" ] || fail "read API omitted the sha256"

cat > "$tmpdir/save.json" <<JSON
{"file":"index.html","content":"<!doctype html><html><body><p>Edited</p></body></html>\\n","base_sha256":"$base_sha"}
JSON
curl -fsS -X POST -H "X-Plak-CSRF: $token" -H "Origin: http://127.0.0.1:$editor_port" \
    -H 'Content-Type: application/json' --data-binary "@$tmpdir/save.json" \
    "http://127.0.0.1:$editor_port/api.php?action=save&site=foo" >/dev/null
grep -q 'Edited' "$HOME/Plak/Sites/foo.localhost/public/index.html" || fail "save API did not update the file"
[ -n "$(find "$HOME/Plak/cache/html-editor" -type f 2>/dev/null | head -1)" ] || fail "save API did not create a backup"

status=$(curl -sS -o "$tmpdir/conflict.json" -w '%{http_code}' -X POST \
    -H "X-Plak-CSRF: $token" -H "Origin: http://127.0.0.1:$editor_port" \
    -H 'Content-Type: application/json' --data-binary "@$tmpdir/save.json" \
    "http://127.0.0.1:$editor_port/api.php?action=save&site=foo")
[ "$status" = "409" ] || fail "stale save did not return 409"
grep -q '"code":"conflict"' "$tmpdir/conflict.json" || fail "conflict response is not explicit"

status=$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Plak-CSRF: $token" \
    -H "Origin: http://127.0.0.1:$editor_port" \
    "http://127.0.0.1:$editor_port/api.php?action=read&site=foo&file=../../etc/passwd")
[ "$status" = "404" ] || fail "path traversal was not rejected"

# Image upload writes under public/uploads and returns a site-relative URL.
php -r 'file_put_contents($argv[1], base64_decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl9sAAAAASUVORK5CYII="));' \
    "$tmpdir/pixel.png"
upload=$(curl -fsS -H "X-Plak-CSRF: $token" -H "Origin: http://127.0.0.1:$editor_port" \
    -F "file=@$tmpdir/pixel.png;type=image/png" \
    "http://127.0.0.1:$editor_port/api.php?action=upload&site=foo") \
    || fail "image upload failed"
grep -q '"url":"/uploads/' <<<"$upload" || fail "upload response lacks a URL"
upload_path=$(printf '%s' "$upload" | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo $d["path"] ?? "";')
[ -n "$upload_path" ] || fail "upload response lacks a path"
[ -f "$HOME/Plak/Sites/foo.localhost/public/$upload_path" ] || fail "uploaded image is missing"

traversal=$(curl -fsS -H "X-Plak-CSRF: $token" -H "Origin: http://127.0.0.1:$editor_port" \
    -F "file=@$tmpdir/pixel.png;type=image/png;filename=../../evil.png" \
    "http://127.0.0.1:$editor_port/api.php?action=upload&site=foo") \
    || fail "upload with a traversal filename failed"
grep -q '"path":"uploads/' <<<"$traversal" || fail "traversal filename escaped uploads"
[ ! -e "$HOME/Plak/Sites/evil.png" ] || fail "traversal filename wrote outside the site"

printf 'not an image\n' > "$tmpdir/not-image.txt"
status=$(curl -sS -o "$tmpdir/not-image.json" -w '%{http_code}' \
    -H "X-Plak-CSRF: $token" -H "Origin: http://127.0.0.1:$editor_port" \
    -F "file=@$tmpdir/not-image.txt;type=text/plain" \
    "http://127.0.0.1:$editor_port/api.php?action=upload&site=foo")
[ "$status" = "415" ] || fail "non-image upload was not rejected"
grep -q 'valid image' "$tmpdir/not-image.json" || fail "non-image rejection is not explicit"

router_html=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if router_html=$(curl -fsS --max-time 1 -H 'Host: foo.localhost' "http://127.0.0.1:$router_port/?plak_site=foo&plak_path=/" 2>/dev/null); then
        break
    fi
    sleep 0.2
done
grep -q 'Edited' <<<"$router_html" || fail "router did not serve the site"
grep -q 'loader.js' <<<"$router_html" || fail "router did not inject the editor loader"
grep -q '<script' "$HOME/Plak/Sites/foo.localhost/public/index.html" && fail "router wrote the loader into the file"

tunnel_html=$(curl -fsS -H 'Host: tunnel.example' "http://127.0.0.1:$router_port/?plak_site=foo&plak_path=/")
grep -q 'loader.js' <<<"$tunnel_html" && fail "router injected the editor into a tunnel host"

# The Caddyfile injects the router only for static sites with index.html.
mkdir -p "$HOME/Plak/Sites/static.localhost/public" "$HOME/Plak/Sites/wp.localhost/public" "$HOME/Plak/Logs" "$HOME/Plak/App/directives" "$tmpdir/bin"
printf '<!doctype html><html><body>static</body></html>\n' > "$HOME/Plak/Sites/static.localhost/public/index.html"
printf '<?php\n' > "$HOME/Plak/Sites/wp.localhost/public/wp-config.php"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpdir/bin/mailpit"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpdir/bin/caddy"
chmod +x "$tmpdir/bin/mailpit" "$tmpdir/bin/caddy"

(
    source ./plak.sh >/dev/null 2>&1
    SITES_DIR="$SITES_DIR"
    APP_DIR="$APP_DIR"
    CADDYFILE_PATH="$CADDYFILE_PATH"
    LOGS_DIR="$LOGS_DIR"
    CUSTOM_CADDY_DIR="$CUSTOM_CADDY_DIR"
    PLAK_SITE_DIR="$PLAK_SITE_DIR"
    HTTP_PORT=80
    HTTPS_PORT=443
    IS_WSL=false
    CADDY_CMD="$tmpdir/bin/caddy"
    PATH="$tmpdir/bin:$PATH"
    is_caddy_running() { return 0; }
    plak_config_get() { echo 0; }
    plak_site_ini_get() { echo "${2:-}"; }
    regenerate_caddyfile >/dev/null
) || fail "regenerate_caddyfile failed"

grep -q '@plak_editor_html' "$CADDYFILE_PATH" || fail "static site lacks the editor router handle"
grep -q 'plak_site=static' "$CADDYFILE_PATH" || fail "editor router handle lacks the site name"
if awk '/^wp.localhost \{/{flag=1} flag{print} flag&&/^\}$/{exit}' "$CADDYFILE_PATH" | grep -q 'plak_editor'; then
    fail "WordPress site got the static editor router"
fi

echo "HTML editor regression tests passed."
