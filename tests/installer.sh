#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home" PLAK_NO_PATH_PRELUDE=1 PLAK_CLI_ONLY=1
mkdir -p "$HOME" "$tmpdir/bin"
export PLAK_INSTALL_DIR="$tmpdir/bin" PLAK_INSTALL_URL="file://$ROOT_DIR/plak.sh"
export PATH="$PLAK_INSTALL_DIR:$PATH"
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
grep -qi 'could not download' "$tmpdir/output"
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

# macOS arm64 Homebrew path selection, without running the installer.
mac_home="$tmpdir/homebrew"
mkdir -p "$mac_home/bin"
cat > "$mac_home/bin/brew" <<'BREW'
#!/usr/bin/env bash
case "${1:-}" in
    --prefix) printf '%s\n' "$TEST_BREW_PREFIX" ;;
    shellenv) printf 'export PATH="%s/bin:$PATH"\n' "$TEST_BREW_PREFIX" ;;
    list)
        case "${2:-}" in
            --versions)
                [ "${TEST_BREW_FORMULA:-0}" = "1" ] || exit 1
                case "${3:-}" in
                    plak-cli|plakio/tap/plak-cli) printf '%s 0.4.66\n' "$3" ;;
                    *) exit 1 ;;
                esac
                ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
BREW
chmod +x "$mac_home/bin/brew"
(
    export PLAK_INSTALLER_LIB_ONLY=1 TEST_BREW_PREFIX="$mac_home"
    export PATH="$mac_home/bin:/usr/bin:/bin"
    source "$ROOT_DIR/install.sh"
    selected=$(plak_installer_choose_dir Darwin arm64)
    [ "$selected" = "$mac_home/bin" ] || exit 1
    PATH="/usr/bin:/bin"
    selected=$(plak_installer_choose_dir Darwin arm64)
    [ "$selected" = "/usr/local/bin" ] || exit 1
    selected=$(plak_installer_choose_dir Darwin x86_64)
    [ "$selected" = "/usr/local/bin" ] || exit 1
    selected=$(plak_installer_choose_dir Linux aarch64)
    [ "$selected" = "/usr/local/bin" ] || exit 1
) || { echo 'macOS Homebrew path selection failed' >&2; exit 1; }

# The universal installer must never replace a Homebrew-owned plak. Doing so
# turns the keg symlink into a regular file and makes every later
# `brew upgrade` fail at the link step.
mkdir -p "$mac_home/Cellar/plak-cli/0.4.66/bin"
cp "$ROOT_DIR/plak.sh" "$mac_home/Cellar/plak-cli/0.4.66/bin/plak"
ln -s ../Cellar/plak-cli/0.4.66/bin/plak "$mac_home/bin/plak"
(
    export PLAK_INSTALLER_LIB_ONLY=1 TEST_BREW_PREFIX="$mac_home" TEST_BREW_FORMULA=1
    export PATH="$mac_home/bin:/usr/bin:/bin"
    source "$ROOT_DIR/install.sh"
    plak_installer_homebrew_owns_destination "$mac_home/bin/plak" || exit 1
    plak_installer_homebrew_owns_destination "$mac_home/Cellar/plak-cli/0.4.66/bin/plak" || exit 1
    if plak_installer_homebrew_owns_destination "$tmpdir/bin/plak"; then exit 1; fi
) || { echo 'Homebrew ownership detection failed' >&2; exit 1; }

broken_home="$tmpdir/homebrew-broken"
mkdir -p "$broken_home/bin"
cp "$ROOT_DIR/plak.sh" "$broken_home/bin/plak"
(
    export PLAK_INSTALLER_LIB_ONLY=1 TEST_BREW_PREFIX="$broken_home" TEST_BREW_FORMULA=1
    export PATH="$mac_home/bin:/usr/bin:/bin"
    source "$ROOT_DIR/install.sh"
    plak_installer_homebrew_owns_destination "$broken_home/bin/plak" || exit 1
) || { echo 'broken Homebrew link detection failed' >&2; exit 1; }

if PLAK_INSTALL_DIR="$mac_home/bin" PLAK_INSTALL_URL="file://$ROOT_DIR/plak.sh" \
    PATH="$mac_home/bin:$PATH" bash "$ROOT_DIR/install.sh" \
    > "$tmpdir/homebrew-refusal" 2>&1; then
    echo 'Installer replaced a Homebrew-managed CLI' >&2
    exit 1
fi
grep -q 'managed by Homebrew' "$tmpdir/homebrew-refusal"
grep -q 'brew link --overwrite plak-cli' "$tmpdir/homebrew-refusal"
[ -L "$mac_home/bin/plak" ] || { echo 'Installer replaced the Homebrew symlink' >&2; exit 1; }
cmp -s "$ROOT_DIR/plak.sh" "$mac_home/Cellar/plak-cli/0.4.66/bin/plak" \
    || { echo 'Installer modified the Homebrew keg' >&2; exit 1; }

# Homebrew requires the Xcode Command Line Tools. An installed toolchain is
# accepted silently; when it is missing, non-interactive runs fail with the
# exact command instead of starting Apple's GUI installer and blocking.
mkdir -p "$tmpdir/clt"
cat > "$tmpdir/clt/xcode-select" <<'XCODE'
#!/usr/bin/env bash
case "${1:-}" in
    -p)
        [ "${TEST_CLT_INSTALLED:-0}" = "1" ] || exit 1
        echo /Library/Developer/CommandLineTools
        ;;
esac
XCODE
chmod +x "$tmpdir/clt/xcode-select"
(
    PLAK_INSTALLER_LIB_ONLY=1
    source "$ROOT_DIR/install.sh"
    PATH="$tmpdir/clt:/usr/bin:/bin"
    export TEST_CLT_INSTALLED=1
    plak_installer_ensure_xcode_clt || exit 1
    AUTO_YES=true
    export TEST_CLT_INSTALLED=0
    if plak_installer_ensure_xcode_clt > "$tmpdir/clt-missing.out" 2>&1; then exit 1; fi
) || { echo 'Xcode Command Line Tools handling failed' >&2; exit 1; }
grep -q "xcode-select --install" "$tmpdir/clt-missing.out"
# Actual executable launch (not bash script invocation) must also work before
# replacing the previous installation. Simulate a broken shebang interpreter.
cat > "$tmpdir/tools/bash" <<'BASH'
#!/bin/bash
case "$1" in */.plak-install.*) echo 'test interpreter cannot execute installed Plak' >&2; exit 126 ;; esac
exec /bin/bash "$@"
BASH
chmod +x "$tmpdir/tools/bash"
if PATH="$tmpdir/tools:$PATH" /bin/bash "$ROOT_DIR/install.sh" > "$tmpdir/output" 2>&1; then exit 1; fi
grep -qE 'Invalid Plak script|failed validation|executable validation failed' "$tmpdir/output"
cmp "$tmpdir/original" "$PLAK_INSTALL_DIR/plak"
[ -z "$(find "$PLAK_INSTALL_DIR" -name '.plak-install.*' -print)" ]
echo 'Installer validation, piped download, preservation and simulated Linux architecture tests passed (not real WSL)'
