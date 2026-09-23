#!/usr/bin/env bash

# Hermetic regression tests for `plak add --agent` and `plak agent`: plugin
# download/activation, Application Password rotation, wp-mcp registration and
# ability verification, using fakes so no real site, plugin or network is used.
# shellcheck disable=SC2016,SC1091 # Literal shell fixtures; runtime is compiled separately.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home with spaces"
mkdir -p "$HOME/.local/bin" "$HOME/Plak/Sites" "$tmpdir/plugins" "$tmpdir/passwords"
# Keep the harness hermetic: a system wp-mcp (e.g. Homebrew) must not satisfy
# `command -v` and skip the installer path under test.
export PATH="$HOME/.local/bin:/usr/bin:/bin"
export PLAK_TERMINAL_LINKS=0
export WP_LOG="$tmpdir/wp-log" WPMCP_LOG="$tmpdir/wpmcp-log" WPMCP_ENV_LOG="$tmpdir/wpmcp-env"
export CURL_LOG="$tmpdir/curl-log" TEST_PLUGINS="$tmpdir/plugins" TEST_PASSWORDS="$tmpdir/passwords/passwords"
export MYSQL_LOG="$tmpdir/mysql-log" PLAK_WPMCP_BIN_DIR="$HOME/.local/bin"
export TEST_PERMALINK="$tmpdir/permalink" TEST_WPMCP_OPTIONS="$tmpdir/wpmcp-options"

fail() { echo "Agent regression failed: $*" >&2; exit 1; }

printf '#!/usr/bin/env php\n<?php\n' > "$HOME/.local/bin/wp"
chmod +x "$HOME/.local/bin/wp"

cat > "$HOME/.local/bin/frankenphp" <<'FRANK'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = php-cli ] || exit 90
shift
if [ "${1:-}" = "-r" ]; then
    case "${PLAK_AGENT_ZIP_PATH:-}" in
        *wp-mcp*) echo wp-mcp ;;
        *html-editor*) echo html-editor ;;
        *) exit 1 ;;
    esac
    exit 0
fi
shift # drop the wp path
printf '%s\n' "$*" >> "$WP_LOG"
case "${1:-}" in
    core)
        case "${2:-}" in
            download)
                mkdir -p wp-includes
                printf '<?php\n' > wp-includes/version.php
                printf '<?php\n' > wp-settings.php
                ;;
            install) touch .installed ;;
            is-installed) test -f .installed ;;
        esac
        ;;
    config)
        [ "${2:-}" = create ] && { printf '<?php\n' > wp-config.php; cat >> wp-config.php; }
        ;;
    option)
        case "${2:-}" in
            get)
                if [ "${3:-}" = permalink_structure ] && [ -f "$TEST_PERMALINK" ]; then
                    cat "$TEST_PERMALINK"
                fi
                ;;
            update)
                if [ "${3:-}" = permalink_structure ]; then
                    printf '%s' "$4" > "$TEST_PERMALINK"
                elif [ "${3:-}" = wp_mcp_ai_abilities_enabled ] || [ "${3:-}" = wp_mcp_ai_abilities_domain ]; then
                    printf '%s=%s\n' "$3" "$4" >> "$TEST_WPMCP_OPTIONS"
                fi
                ;;
        esac
        ;;
    rewrite) ;; # flush
    plugin)
        case "${2:-}" in
            delete) ;;
            install)
                touch "$TEST_PLUGINS/$(basename "$3" .zip)"
                exit "${PLUGIN_INSTALL_RC:-0}"
                ;;
            is-active) test -f "$TEST_PLUGINS/$3" ;;
        esac
        ;;
    user)
        case "${2:-}" in
            login) echo 'https://agent.localhost/wp-login.php?token=one-time' ;;
            application-password)
                case "${3:-}" in
                    list)
                        echo 'uuid,name'
                        [ -f "$TEST_PASSWORDS" ] && cat "$TEST_PASSWORDS"
                        ;;
                    create)
                        uuid="uuid-$$-$RANDOM"
                        # Mirror WP-CLI: CSV double-quotes values with spaces.
                        printf '%s,"%s"\n' "$uuid" "$5" >> "$TEST_PASSWORDS"
                        echo "app-pass-$uuid"
                        ;;
                    delete)
                        if [ -f "$TEST_PASSWORDS" ]; then
                            grep -v "^$5," "$TEST_PASSWORDS" > "$TEST_PASSWORDS.tmp" || true
                            mv "$TEST_PASSWORDS.tmp" "$TEST_PASSWORDS"
                        fi
                        ;;
                esac
                ;;
        esac
        ;;
esac
FRANK

cat > "$HOME/.local/bin/wp-mcp" <<'WPMCP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$WPMCP_LOG"
printf 'user=%s\npass=%s\n' "${WPMCP_USERNAME:-}" "${WPMCP_PASSWORD:-}" >> "$WPMCP_ENV_LOG"
case "$*" in
    *discover*)
        [ "${WPMCP_DISCOVER_RC:-0}" = 0 ] || exit 1
        echo '{"ok":true,"data":{"abilities":[]}}'
        ;;
    *"auth login"*)
        [ "${WPMCP_LOGIN_RC:-0}" = 0 ] || exit 1
        echo '{"ok":true,"data":{"name":"x"}}'
        ;;
esac
exit 0
WPMCP

cat > "$HOME/.local/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
out="" url="" ua=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output|-o) out="$2"; shift 2 ;;
        --user-agent) ua="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
printf '%s\t%s\n' "$ua" "$url" >> "$CURL_LOG"
if [ -n "$out" ] && [ "$out" != /dev/null ]; then
    if [ "${CURL_BLOCK_PAGE:-0}" = 1 ]; then
        printf '<html>firewall</html>' > "$out"
    else
        printf 'PK\003\004 fake plugin archive' > "$out"
    fi
fi
exit 0
CURL

cat > "$HOME/.local/bin/mysql" <<'MYSQL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MYSQL_LOG"
exit 0
MYSQL

cat > "$HOME/.local/bin/gum" <<'GUM'
#!/usr/bin/env bash
printf '%s\n' "$*"
GUM
for bin in mariadb mailpit jq; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.local/bin/$bin"
done
chmod +x "$HOME/.local/bin/"*

cat > "$HOME/Plak/config" <<'CONFIG'
DB_USER='plak_test'
DB_PASSWORD='test-only'
DB_HOST='127.0.0.1'
DB_PORT='3306'
HTTPS_PORT='443'
CONFIG

# --- direct module tests ----------------------------------------------------
set --
source ./plak.sh >/dev/null 2>&1 || true
# plak.sh prepends system bin dirs; restore the hermetic order so the fakes win.
export PATH="$HOME/.local/bin:/usr/bin:/bin"

site_dir="$SITES_DIR/agent.localhost"
mkdir -p "$site_dir/public"
printf '<?php\n' > "$site_dir/public/wp-config.php"

# A firewall block page served with HTTP 200 must never reach WP-CLI.
: > "$CURL_LOG"
if CURL_BLOCK_PAGE=1 plak_agent_download_plugin "https://downloads.plak.io/wp-mcp-latest.zip" "$tmpdir/blocked.zip" >/dev/null 2>&1; then
    fail 'accepted an HTML block page as a plugin ZIP'
fi
[ ! -e "$tmpdir/blocked.zip" ] || fail 'left a rejected download behind'
grep -q 'PlakCLI/' "$CURL_LOG" || fail 'download did not send the PlakCLI User-Agent'

# Full preparation with fakes.
: > "$WPMCP_LOG"; : > "$WPMCP_ENV_LOG"; : > "$TEST_PASSWORDS"
plak_agent_prepare agent >"$tmpdir/prep.out" 2>"$tmpdir/prep.err" || fail "prepare failed: $(cat "$tmpdir/prep.err")"
[ -f "$TEST_PLUGINS/wp-mcp" ] || fail 'wp-mcp plugin was not installed'
[ -f "$TEST_PLUGINS/html-editor" ] || fail 'html-editor plugin was not installed'
grep -q -- '--json auth login' "$WPMCP_LOG" || fail 'wp-mcp auth login was not called'
grep -q -- '--name agent' "$WPMCP_LOG" || fail 'wp-mcp profile was not named after the site'
grep -q -- '--site agent discover' "$WPMCP_LOG" || fail 'abilities were not verified'
[ "$(cat "$TEST_PERMALINK")" = '/%postname%/' ] || fail 'pretty permalinks were not enabled for the REST API'
grep -q '^wp_mcp_ai_abilities_enabled=1$' "$TEST_WPMCP_OPTIONS" || fail 'WP-MCP abilities were not enabled'
grep -q '^wp_mcp_ai_abilities_domain=agent.localhost$' "$TEST_WPMCP_OPTIONS" || fail 'WP-MCP domain lock was not set'
grep -q '^user=admin$' "$WPMCP_ENV_LOG" || fail 'registration did not pass the WordPress user'
grep -q '^pass=app-pass-' "$WPMCP_ENV_LOG" || fail 'registration did not pass the password via the environment'
if grep -q 'app-pass-' "$WPMCP_LOG"; then fail 'the password leaked into argv'; fi

# Retry is idempotent: the previous password is revoked, not accumulated.
plak_agent_prepare agent >/dev/null 2>&1 || fail 'second prepare failed'
passwords=$(grep -c 'Plak CLI (agent)' "$TEST_PASSWORDS" || true)
[ "$passwords" = 1 ] || fail "expected exactly one password after retry, got $passwords"

# A failed registration must not leave an orphan credential behind.
: > "$TEST_PASSWORDS"
if WPMCP_LOGIN_RC=1 plak_agent_prepare agent >/dev/null 2>&1; then fail 'prepare ignored a registration failure'; fi
if [ -s "$TEST_PASSWORDS" ]; then fail 'left an orphan Application Password after failed registration'; fi

# A failed ability discovery is reported as failure, not success.
if WPMCP_DISCOVER_RC=1 plak_agent_prepare agent >/dev/null 2>&1; then fail 'prepare ignored a discovery failure'; fi

# --- router tests -----------------------------------------------------------
if ./plak.sh add bad --agent --plain >/dev/null 2>&1; then fail 'accepted --agent with --plain'; fi

./plak.sh add agentlive --agent --no-reload >"$tmpdir/add.out" 2>"$tmpdir/add.err" || fail "add --agent failed: $(cat "$tmpdir/add.err")"
[ -f "$TEST_PLUGINS/wp-mcp" ] || fail 'add --agent did not install wp-mcp'
grep -q 'Agent ready' "$tmpdir/add.out" || fail 'add --agent did not report readiness'

# A failed preparation keeps the created site and tells the agent how to retry.
rm -f "$TEST_PLUGINS/wp-mcp" "$TEST_PLUGINS/html-editor"
if CURL_BLOCK_PAGE=1 ./plak.sh add agentfail --agent --no-reload >"$tmpdir/fail.out" 2>"$tmpdir/fail.err"; then
    fail 'add --agent reported success on a blocked download'
fi
[ -f "$SITES_DIR/agentfail.localhost/public/wp-config.php" ] || fail 'removed the WordPress site after an agent failure'
grep -q 'plak agent agentfail' "$tmpdir/fail.err" || fail 'missing retry guidance after agent failure'

./plak.sh agent agent --json >"$tmpdir/agent.json" 2>/dev/null || fail 'plak agent --json failed'
grep -q '"success":true' "$tmpdir/agent.json" || fail 'plak agent --json did not emit a success envelope'
grep -q '"profile":"agent"' "$tmpdir/agent.json" || fail 'plak agent --json missing profile'

# --- CLI installer ----------------------------------------------------------
rm -f "$HOME/.local/bin/wp-mcp"
hash -r
if ! plak_agent_install_cli >/dev/null 2>&1; then fail 'could not install wp-mcp-cli'; fi
[ -x "$HOME/.local/bin/wp-mcp" ] || fail 'wp-mcp was not installed to a PATH directory'
grep -q 'wp-mcp-cli/v0.1.9/wp-mcp.sh' "$CURL_LOG" || fail 'wp-mcp install was not pinned to a release'

# --- skill companion: delegate to wp-mcp-cli when present -------------------
cat > "$HOME/.local/bin/wp-mcp" <<'WPMCP'
#!/usr/bin/env bash
set -euo pipefail
printf 'skill %s\n' "$*" >> "$WPMCP_LOG"
exit 0
WPMCP
chmod +x "$HOME/.local/bin/wp-mcp"
: > "$WPMCP_LOG"
./plak.sh skill install opencode >/dev/null 2>&1 || fail 'skill install failed'
grep -q 'skill install opencode' "$WPMCP_LOG" || fail 'wp-mcp companion skill was not delegated for the selected target'
[ ! -e "$HOME/.codex/skills/wp-mcp/SKILL.md" ] || fail 'wrote the wp-mcp skill to an unselected target'

# --- skill companion: pinned fallback download when wp-mcp is absent --------
rm -f "$HOME/.local/bin/wp-mcp"
hash -r
: > "$CURL_LOG"
./plak.sh skill install opencode >/dev/null 2>&1 || fail 'skill install fallback failed'
[ -f "$HOME/.config/opencode/skills/wp-mcp/SKILL.md" ] || fail 'wp-mcp skill fallback file missing'
grep -q 'wp-mcp-cli/v0.1.9/skills/wp-mcp/SKILL.md' "$CURL_LOG" || fail 'wp-mcp skill fallback was not pinned to a release'
[ ! -e "$HOME/.codex/skills/wp-mcp/SKILL.md" ] || fail 'fallback wrote to an unselected target'

echo 'Agent regression tests passed.'
