#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "static transfer regression failed: $*" >&2
    exit 1
}

export HOME="$tmpdir/home"
export PLAK_NO_PATH_PRELUDE=1
site_public="$HOME/Plak/Sites/foo.localhost/public"
mkdir -p "$site_public/uploads" "$HOME/Plak/Sites/foo.localhost/private" \
    "$HOME/Plak/Sites/foo.localhost/logs" "$HOME/Plak/App/gui/editor" \
    "$tmpdir/bin" "$tmpdir/remote/public"

printf '<!doctype html><html><body>local</body></html>\n' > "$site_public/index.html"
printf 'image\n' > "$site_public/uploads/pic.txt"
printf 'private\n' > "$HOME/Plak/Sites/foo.localhost/private/secret"
printf 'log\n' > "$HOME/Plak/Sites/foo.localhost/logs/site.log"
printf 'editor\n' > "$HOME/Plak/App/gui/editor/secret"
printf 'remote old\n' > "$tmpdir/remote/public/old.html"

cat > "$tmpdir/bin/ssh" <<'SSH'
#!/usr/bin/env bash
set -euo pipefail
while [ $# -gt 0 ]; do
    case "$1" in
        -o|-p|-i|-l) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
[ $# -gt 0 ] || exit 2
shift
exec bash -c "$*"
SSH
chmod +x "$tmpdir/bin/ssh"
export PATH="$tmpdir/bin:$PATH"

source ./plak.sh >/dev/null 2>&1
log_step() { :; }
log_success() { :; }
log_error() { echo "ERROR: $*" >&2; exit 1; }

export PLAK_PUSH_TMP_DIR="$tmpdir/push-tmp"
mkdir -p "$PLAK_PUSH_TMP_DIR"
export PLAK_PULL_TMP_DIR="$tmpdir/pull-tmp"
mkdir -p "$PLAK_PULL_TMP_DIR"

# Dry run must not touch the remote.
plak_site_push_static foo "$site_public" fake-host "$tmpdir/remote/public" "" 1 1 >"$tmpdir/push-dry.log"
[ ! -e "$tmpdir/remote/public/index.html" ] || fail "dry run changed the remote"

plak_site_push_static foo "$site_public" fake-host "$tmpdir/remote/public" "" 1 0 >"$tmpdir/push.log"
grep -q 'local' "$tmpdir/remote/public/index.html" || fail "push did not upload index.html"
[ -f "$tmpdir/remote/public/uploads/pic.txt" ] || fail "push did not upload assets"
[ -f "$tmpdir/remote/public/old.html" ] || fail "push deleted a remote-only file"
[ ! -e "$tmpdir/remote/public/private" ] || fail "push uploaded private/"
[ ! -e "$tmpdir/remote/public/logs" ] || fail "push uploaded logs/"
[ ! -e "$tmpdir/remote/public/secret" ] || fail "push uploaded editor files"
[ -n "$(find "$HOME/.plak/backups" -name public.tar.gz -type f 2>/dev/null | head -1)" ] \
    || fail "push did not create a remote backup"
plak_remote_transfer_cleanup

# Pull mirrors the remote public tree and keeps a local backup.
mkdir -p "$tmpdir/remote2/public/assets"
printf '<!doctype html><html><body>remote</body></html>\n' > "$tmpdir/remote2/public/index.html"
printf 'asset\n' > "$tmpdir/remote2/public/assets/app.css"
printf 'stale\n' > "$site_public/stale.html"

plak_site_pull_static foo "$site_public" fake-host "$tmpdir/remote2/public" "" 1 1 >"$tmpdir/pull-dry.log"
grep -q 'local' "$site_public/index.html" || fail "pull dry run changed the local site"

plak_site_pull_static foo "$site_public" fake-host "$tmpdir/remote2/public" "" 1 0 >"$tmpdir/pull.log"
grep -q 'remote' "$site_public/index.html" || fail "pull did not download index.html"
[ -f "$site_public/assets/app.css" ] || fail "pull did not download assets"
[ ! -e "$site_public/stale.html" ] || fail "pull did not mirror the remote tree"
backup=$(find "$HOME/Plak/cache/static-pull/foo" -name '*.tar.gz' -type f | head -1)
[ -n "$backup" ] || fail "pull did not create a local backup"
tar -tzf "$backup" | grep -q 'stale.html' || fail "local backup does not contain the old file"
plak_remote_transfer_cleanup

# Exercise the command branches with a bound remote and a local ssh shim.
cat > "$HOME/Plak/config" <<'CONFIG'
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=plak
DB_PASSWORD=plak
CONFIG
mkdir -p "$HOME/.ssh"
cat > "$HOME/.ssh/config" <<CONFIG
Host fake
    HostName fake
    User test
    Port 22
    # plak-remote-path: $tmpdir/remote2/public
CONFIG
printf 'fake\n' > "$HOME/Plak/Sites/foo.localhost/.remote"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpdir/bin/gum"
chmod +x "$tmpdir/bin/gum"

printf '<!doctype html><html><body>command push</body></html>\n' > "$site_public/index.html"
PLAK_RT_REMOTE_FILES=""
plak_site_push foo --yes >"$tmpdir/push-command.log"
grep -q 'command push' "$tmpdir/remote2/public/index.html" || fail "push command did not use the static branch"

printf '<!doctype html><html><body>command pull</body></html>\n' > "$tmpdir/remote2/public/index.html"
plak_site_pull foo --yes >"$tmpdir/pull-command.log"
grep -q 'command pull' "$site_public/index.html" || fail "pull command did not use the static branch"

echo "Static transfer regression tests passed."
