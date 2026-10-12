#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home" PLAK_NO_PATH_PRELUDE=1
mkdir -p "$HOME" "$tmpdir/bin"
export PLAK_INSTALL_DIR="$tmpdir/bin" PLAK_INSTALL_URL="file://$ROOT_DIR/plak.sh"
bash "$ROOT_DIR/install.sh" > "$tmpdir/success"
grep -q 'Installed Plak' "$tmpdir/success"
"$PLAK_INSTALL_DIR/plak" version | grep -Eq '^plak v[0-9]+\.[0-9]+\.[0-9]+$'
cp "$PLAK_INSTALL_DIR/plak" "$tmpdir/original"
# Same entrypoint as curl | bash, with a local deterministic payload.
bash < "$ROOT_DIR/install.sh" > "$tmpdir/piped"
cmp "$tmpdir/original" "$PLAK_INSTALL_DIR/plak"
for payload in empty html syntax foreign wrong-version; do
    case "$payload" in
        empty) : > "$tmpdir/payload" ;;
        html) printf '<html>not a release</html>\n' > "$tmpdir/payload" ;;
        syntax) printf '#!/usr/bin/env bash\nPLAK_VERSION="1.2.3"\nif\n' > "$tmpdir/payload" ;;
        foreign) cp /usr/bin/env "$tmpdir/payload" ;;
        wrong-version) printf '#!/usr/bin/env bash\nPLAK_VERSION="1.2.3"\necho "coreutils: unknown program '\''plak'\''" >&2\nexit 1\n' > "$tmpdir/payload" ;;
    esac
    if PLAK_INSTALL_URL="file://$tmpdir/payload" bash "$ROOT_DIR/install.sh" > "$tmpdir/output" 2>&1; then
        echo "Invalid $payload was accepted" >&2; exit 1
    fi
    if grep -q 'Installed Plak' "$tmpdir/output"; then exit 1; fi
    cmp "$tmpdir/original" "$PLAK_INSTALL_DIR/plak"
done
if PLAK_INSTALL_URL="file://$tmpdir/missing" bash "$ROOT_DIR/install.sh" > "$tmpdir/output" 2>&1; then exit 1; fi
grep -q 'Could not download' "$tmpdir/output"
cmp "$tmpdir/original" "$PLAK_INSTALL_DIR/plak"
# Replacing a symlink must preserve the original target's bytes.
cp /usr/bin/env "$tmpdir/foreign-program"
cp "$tmpdir/foreign-program" "$tmpdir/foreign-before"
rm "$PLAK_INSTALL_DIR/plak"
ln -s "$tmpdir/foreign-program" "$PLAK_INSTALL_DIR/plak"
bash "$ROOT_DIR/install.sh" >/dev/null
[ ! -L "$PLAK_INSTALL_DIR/plak" ]
cmp "$tmpdir/foreign-before" "$tmpdir/foreign-program"
# Local developer install uses the same validation.
bash "$ROOT_DIR/install.sh" --dev >/dev/null
cmp "$ROOT_DIR/plak.sh" "$PLAK_INSTALL_DIR/plak"
# Simulated WSL is Linux, irrespective of kernel string / CPU architecture.
mkdir -p "$tmpdir/tools"
cat > "$tmpdir/tools/uname" <<'UNAME'
#!/usr/bin/env bash
case "$1" in -s) echo "${TEST_OS:-Linux}" ;; -m) echo "${TEST_ARCH:-x86_64}" ;; *) echo 'Linux microsoft-standard-WSL2' ;; esac
UNAME
chmod +x "$tmpdir/tools/uname"
for arch in x86_64 aarch64; do
    PATH="$tmpdir/tools:$PATH" TEST_ARCH="$arch" bash "$ROOT_DIR/install.sh" >/dev/null
done
if PATH="$tmpdir/tools:$PATH" TEST_OS=Windows_NT bash "$ROOT_DIR/install.sh" > "$tmpdir/output" 2>&1; then exit 1; fi
grep -q 'Unsupported operating system' "$tmpdir/output"
[ -z "$(find "$PLAK_INSTALL_DIR" -name '.plak-install.*' -print)" ]
echo 'Installer validation, piped download, preservation and simulated Linux architecture tests passed (not real WSL)'
