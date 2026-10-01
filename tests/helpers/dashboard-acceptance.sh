# shellcheck disable=SC2154,SC2016 # Caller fixture variables; literal PHP/argv injection tests.
# Real API/WP-CLI/Mailpit acceptance in the multisite fixture's isolated stack.
acceptance_post() {
    command curl --noproxy '*' --cacert "$ca" -fsS --max-time 120 \
        --connect-to "plak.localhost:443:127.0.0.1:$https_port" \
        -H 'Origin: https://plak.localhost' -H 'Content-Type: application/json' \
        --data "{\"action\":\"$1\",\"csrf\":\"$dashboard_token\"${2:-}}" https://plak.localhost/api.php
}
acceptance_assert_success() {
    python3 - "$1" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r.get('success'),r
PY
}
public="$SITES_DIR/dash-manual.localhost/public"
plak_multisite_wp "$public" user create live-editor editor@dash-manual.localhost --role=editor > "$tmpdir/editor-create"
acceptance_post site_users ',"site_name":"dash-manual"' > "$tmpdir/live-users"
python3 - "$tmpdir/live-users" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['success']
assert any(u['user_login']=='live-editor' and 'editor' in u['roles'] for u in r['items'])
PY
acceptance_post site_cron ',"site_name":"dash-manual"' > "$tmpdir/live-cron"
acceptance_assert_success "$tmpdir/live-cron"
acceptance_post site_cron_run ',"site_name":"dash-manual","hook":"unknown_live_test_hook"' > "$tmpdir/live-cron-failed"
python3 - "$tmpdir/live-cron-failed" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert not r['success'] and r['exit_code']!=0 and r['duration_ms']>=0
PY
acceptance_post site_wpcli ',"site_name":"dash-manual","args":["option","add","live-special","space ; $(touch /do-not-run)"]' > "$tmpdir/live-console"
acceptance_assert_success "$tmpdir/live-console"
[ "$(plak_multisite_wp "$public" option get live-special)" = 'space ; $(touch /do-not-run)' ]

# Core updates preserve local configuration and custom content, and downgrades
# require the explicit flag. Version transitions use an already-existing site.
cp "$public/wp-config.php" "$tmpdir/core-config-before"
printf '<?php // custom local content\n' > "$public/wp-content/mu-plugins/acceptance-marker.php"
current=$(plak_multisite_wp "$public" core version)
if plak_core update dash-manual --version 6.8.1 > "$tmpdir/downgrade-refusal" 2>&1; then
    [ "$current" = 6.8.1 ] || { echo 'Implicit downgrade was allowed' >&2; exit 1; }
fi
plak_core update dash-manual --version 6.8.1 --allow-downgrade > "$tmpdir/core-down"
[ "$(plak_multisite_wp "$public" core version)" = 6.8.1 ]
plak_core update dash-manual --version 6.8.2 > "$tmpdir/core-up"
[ "$(plak_multisite_wp "$public" core version)" = 6.8.2 ]
cmp "$public/wp-config.php" "$tmpdir/core-config-before"
grep -q 'custom local content' "$public/wp-content/mu-plugins/acceptance-marker.php"

if [ -n "${PLAK_TEST_MAILPIT:-}" ]; then
    read -r mail_http mail_smtp < <(python3 - <<'PY'
import socket
s=[socket.socket(),socket.socket()]
for x in s: x.bind(('127.0.0.1',0))
print(*(x.getsockname()[1] for x in s))
PY
)
    "$PLAK_TEST_MAILPIT" --listen "127.0.0.1:$mail_http" --smtp "127.0.0.1:$mail_smtp" \
        --database "$tmpdir/mailpit.db" --disable-version-check > "$tmpdir/mailpit.log" 2>&1 &
    mailpit_pid=$!
    export PLAK_MAILPIT_URL="http://127.0.0.1:$mail_http"
    for _ in {1..50}; do
        if command curl -fsS "$PLAK_MAILPIT_URL/api/v1/info" >/dev/null 2>&1; then break; fi
        sleep 0.1
    done
    python3 - "$mail_smtp" <<'PY'
import smtplib,sys
from email.message import EmailMessage
m=EmailMessage(); m['From']='admin@dash-manual.localhost'; m['To']='editor@dash-manual.localhost'; m['Subject']='Live acceptance mail'
m.set_content('https://dash-manual.localhost/wp-login.php?key=test')
m.add_alternative('<html><script>alert(1)</script><img src="https://external.invalid/pixel"><a href="https://dash-manual.localhost/wp-login.php?key=test">Login</a></html>',subtype='html')
with smtplib.SMTP('127.0.0.1',int(sys.argv[1])) as smtp: smtp.send_message(m)
PY
fi
# Register the dashboard-created site's host and refresh the web environment.
regenerate_caddyfile > "$tmpdir/acceptance-generate"
isolate_live_caddyfile
kill "$web_pid"; wait "$web_pid" || true
"$PLAK_TEST_FRANKENPHP" run --config "$CADDYFILE_PATH" >> "$tmpdir/web.log" 2>&1 &
web_pid=$!
for _ in {1..100}; do
    if acceptance_post site_users ',"site_name":"dash-manual"' > "$tmpdir/live-ready" 2>/dev/null; then break; fi
    sleep 0.1
done
acceptance_post site_user_login ',"site_name":"dash-manual","user_login":"live-editor"' > "$tmpdir/live-editor-login"
acceptance_assert_success "$tmpdir/live-editor-login"
login=$(python3 - "$tmpdir/live-editor-login" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['url'])
PY
)
command curl --noproxy '*' --cacert "$ca" -fsSL --max-redirs 5 --max-time 30 \
    --connect-to "dash-manual.localhost:443:127.0.0.1:$https_port" \
    -c "$tmpdir/editor-cookies" -b "$tmpdir/editor-cookies" "$login" > "$tmpdir/editor-admin"
grep -q 'wp-admin-bar' "$tmpdir/editor-admin"
plak_multisite_wp "$public" eval '$user=get_user_by("login","live-editor"); if(get_user_meta($user->ID,"plak_site_login_token",true)!=="") WP_CLI::error("Token not consumed");'

if [ -n "${PLAK_TEST_MAILPIT:-}" ]; then
    acceptance_post mail_messages ',"site_name":"dash-manual","scope":"site"' > "$tmpdir/live-mail"
    mail_id=$(python3 - "$tmpdir/live-mail" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['success'] and len(r['messages'])==1,r
assert r['messages'][0]['site']=='dash-manual.localhost'; print(r['messages'][0]['id'])
PY
)
    acceptance_post mail_message ",\"id\":\"$mail_id\"" > "$tmpdir/live-mail-detail"
    acceptance_assert_success "$tmpdir/live-mail-detail"
    if grep -q 'alert(1)' "$tmpdir/live-mail-detail"; then echo 'Script mail content not stripped' >&2; exit 1; fi
    # Remote image URLs can be shown/copied; the iframe CSP blocks loading them
    # by default. That rendering boundary is exercised by dashboard.sh.
    acceptance_post mail_delete ",\"ids\":[\"$mail_id\"]" > "$tmpdir/live-mail-deleted"
    acceptance_assert_success "$tmpdir/live-mail-deleted"
    kill "$mailpit_pid"; wait "$mailpit_pid" || true; mailpit_pid=""
    acceptance_post mail_messages ',"scope":"all"' > "$tmpdir/live-mail-offline"
    grep -q '"offline":true' "$tmpdir/live-mail-offline"
fi
echo 'Real dashboard roles/login/cron/argv, core transitions and Mailpit API acceptance passed'
