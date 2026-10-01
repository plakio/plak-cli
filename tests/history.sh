#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016 # Compiled shell + literal PHP test programs.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
command -v php >/dev/null || { echo 'history tests skipped: PHP unavailable'; exit 0; }
./compile.sh >/dev/null
tmpdir=$(mktemp -d)
child_pid=""
trap '[ -z "$child_pid" ] || kill -KILL "$child_pid" 2>/dev/null || true; rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home" PLAK_NO_PATH_PRELUDE=1
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/frankenphp" <<'FRANK'
#!/usr/bin/env bash
shift
exec php "$@"
FRANK
cat > "$HOME/.local/bin/wp" <<'WP'
#!/usr/bin/env php
<?php
$args=array_slice($argv,1); if(($args[0]??'')==='--allow-root') array_shift($args);
if(getenv('FAIL_HISTORY_WP')==='1') exit(7);
switch($args[0]??'') {
    case 'eval': echo json_encode(getcwd().'/wp-content'); break;
    case 'plugin':
        $header=file_get_contents('wp-content/plugins/demo/demo.php');
        preg_match('/Version: (.+)/',$header,$m);
        echo json_encode([['name'=>'demo','status'=>'active','version'=>$m[1]??'unknown']]); break;
    case 'theme': echo json_encode([['name'=>'demo','status'=>'active','version'=>'1.0']]); break;
    default: exit(1);
}
WP
chmod +x "$HOME/.local/bin/"*
export PATH="$HOME/.local/bin:$PATH"
source ./plak.sh >/dev/null
export PLAK_SITE_CMD="$ROOT_DIR/plak.sh"
site="$SITES_DIR/demo.localhost"
content="$site/public/wp-content"
store="$site/private/history"
mkdir -p "$content/plugins/demo" "$content/themes/demo" "$content/mu-plugins"
touch "$site/public/wp-config.php"
printf '<?php // Version: 1.0\n' > "$content/plugins/demo/demo.php"
printf 'original\n' > "$content/themes/demo/style.css"
printf '<?php // must use\n' > "$content/mu-plugins/helper.php"
history_test_id() { php -r '$r=json_decode(stream_get_contents(STDIN),true); echo $r["id"];'; }
plak_history demo save --note $'first "checkpoint"\nwith a newline' > "$tmpdir/result"
first=$(history_test_id < "$tmpdir/result")
[ -f "$store/records/$first/files/plugins/demo/demo.php" ]
plak_history demo save > "$tmpdir/result"
grep -q '"changed": false' "$tmpdir/result"
[ "$(find "$store/records" -name manifest.json | wc -l)" = 1 ]
printf '<?php // Version: 2.0\n' > "$content/plugins/demo/demo.php"
printf 'new\n' > "$content/plugins/demo/added.txt"
rm "$content/mu-plugins/helper.php"
second=$(plak_history demo save --note update | history_test_id)
plak_history demo diff "$first" "$second" > "$tmpdir/diff"
grep -q 'modified' "$tmpdir/diff"
grep -q 'added' "$tmpdir/diff"
grep -q 'removed' "$tmpdir/diff"
grep -q '2.0' "$tmpdir/diff"
"$ROOT_DIR/plak.sh" history demo list --json > "$tmpdir/list-cli"
grep -q "$first" "$tmpdir/list-cli"
"$ROOT_DIR/plak.sh" history --help > "$tmpdir/help-cli"
grep -q 'history <site> restore' "$tmpdir/help-cli"
plak_history demo show "$first" plugins/demo > "$tmpdir/show"
if grep -q 'themes/demo/style.css' "$tmpdir/show"; then exit 1; fi
plak_history demo restore "$first" plugins/demo --yes > "$tmpdir/restore"
grep -q 'Version: 1.0' "$content/plugins/demo/demo.php"
[ ! -e "$content/plugins/demo/added.txt" ]
grep -q original "$content/themes/demo/style.css"
plak_history demo restore "$second" plugins/demo/demo.php --yes > "$tmpdir/restore"
grep -q 'Version: 2.0' "$content/plugins/demo/demo.php"
safety=$(php -r '$r=json_decode(file_get_contents($argv[1]),true); echo $r["safety_id"];' "$tmpdir/restore")
plak_history demo restore "$safety" plugins/demo/demo.php --yes >/dev/null
grep -q 'Version: 1.0' "$content/plugins/demo/demo.php"
plak_history demo restore "$first" mu-plugins/helper.php --yes >/dev/null
[ -f "$content/mu-plugins/helper.php" ]
plak_history demo restore "$second" mu-plugins/helper.php --yes >/dev/null
[ ! -e "$content/mu-plugins/helper.php" ]
if plak_history demo restore "$first" '../outside' --yes >/dev/null 2>&1; then exit 1; fi
mkdir -p "$tmpdir/external"
printf secret > "$tmpdir/external/secret"
ln -s "$tmpdir/external" "$content/plugins/linked"
linked=$(plak_history demo save | history_test_id)
[ ! -e "$store/records/$linked/files/plugins/linked/secret" ]
if plak_history demo restore "$linked" plugins/linked --yes >/dev/null 2>&1; then exit 1; fi
grep -q secret "$tmpdir/external/secret"
git -C "$content/plugins/demo" init -q
git -C "$content/plugins/demo" add demo.php
index_before=$(php -r 'echo hash_file("sha256",$argv[1]);' "$content/plugins/demo/.git/index")
if plak_history demo restore "$second" plugins/demo --yes >/dev/null 2>&1; then exit 1; fi
index_after=$(php -r 'echo hash_file("sha256",$argv[1]);' "$content/plugins/demo/.git/index")
[ "$index_before" = "$index_after" ]
rm -rf "$content/plugins/demo/.git"
touch "$site/public/.git"
if plak_history demo restore "$second" plugins/demo --yes >/dev/null 2>&1; then exit 1; fi
rm "$site/public/.git"
# A failed metadata query must not publish a record.
before=$(find "$store/records" -name manifest.json | wc -l)
export FAIL_HISTORY_WP=1
if plak_history demo save > "$tmpdir/result" 2> "$tmpdir/error"; then exit 1; fi
grep -q 'metadata query failed' "$tmpdir/error"
unset FAIL_HISTORY_WP
[ "$(find "$store/records" -name manifest.json | wc -l)" = "$before" ]
# Another process owns the advisory site lock; no mutation is allowed.
php -r '$f=fopen($argv[1],"c"); flock($f,LOCK_EX); file_put_contents($argv[2],"ready"); sleep(15);' "$store/lock" "$tmpdir/ready" &
locker=$!
for _ in {1..100}; do [ ! -f "$tmpdir/ready" ] || break; sleep 0.01; done
if plak_history demo save > "$tmpdir/result" 2> "$tmpdir/error"; then kill "$locker"; exit 1; fi
grep -q 'Another history operation' "$tmpdir/error"
kill "$locker"; wait "$locker" 2>/dev/null || true
# Model an interrupted replacement after moving the old selection aside.
token=abcdef123456
mkdir -p "$store/.restore-$token"
mv "$content/plugins/demo" "$store/.restore-$token/old"
mkdir -p "$content/plugins/demo"
printf broken > "$content/plugins/demo/demo.php"
php -r 'file_put_contents($argv[1],json_encode(["selection"=>"plugins/demo","transaction"=>"abcdef123456","existed"=>true,"safety_id"=>$argv[2]]));' "$store/restore.json" "$safety"
if plak_history demo save > "$tmpdir/result" 2> "$tmpdir/error"; then exit 1; fi
grep -q 'Interrupted rollback' "$tmpdir/error"
plak_history demo recover --yes > "$tmpdir/recover"
grep -q 'Version: 1.0' "$content/plugins/demo/demo.php"
[ ! -e "$store/restore.json" ]
# Kill the real PHP transaction after moving the current component to recovery.
# Fault injection is only in a temporary copy of the embedded test program.
if [ "$(uname -s)" = Linux ] && php -r 'exit(function_exists("posix_kill") ? 0 : 1);'; then
    plak_history_program > "$tmpdir/fault-program"
    python3 - "$tmpdir/fault-program" <<'PY'
import sys
p=sys.argv[1]; code=open(p).read()
line='if($journal[\'existed\'] && !rename($destination,$transaction.\'/old\')) historyFail(\'Cannot move current selection to recovery.\');'
assert line in code
code=code.replace(line,line+'\n        file_put_contents(getenv("PLAK_TEST_STOP"),"ready"); posix_kill(getmypid(),19);',1)
open(p,'w').write(code)
PY
    PLAK_TEST_STOP="$tmpdir/restore-stop" PLAK_HISTORY_SITE="$site" PLAK_HISTORY_WP="$HOME/.local/bin/wp" PLAK_HISTORY_FRANK="$HOME/.local/bin/frankenphp" PLAK_HISTORY_ARGS="[\"restore\",\"$second\",\"plugins/demo\",\"--yes\"]" \
        php -r "$(cat "$tmpdir/fault-program")" > "$tmpdir/interrupted-result" 2> "$tmpdir/interrupted-error" &
    child_pid=$!
    for _ in {1..100}; do [ ! -f "$tmpdir/restore-stop" ] || break; sleep 0.02; done
    [ -f "$tmpdir/restore-stop" ]
    kill -KILL "$child_pid"; wait "$child_pid" 2>/dev/null || true; child_pid=""
    [ -f "$store/restore.json" ]
    plak_history demo recover --yes > "$tmpdir/kill-recovery"
    grep -q 'Version: 1.0' "$content/plugins/demo/demo.php"
    [ ! -e "$store/restore.json" ]
fi
# Snapshot corruption must be detected before replacing current content.
printf corrupt > "$store/records/$second/files/plugins/demo/demo.php"
if plak_history demo restore "$second" plugins/demo --yes > "$tmpdir/result" 2> "$tmpdir/error"; then exit 1; fi
grep -q 'changed or corrupt' "$tmpdir/error"
grep -q 'Version: 1.0' "$content/plugins/demo/demo.php"
# Background jobs expose completion and actionable errors.
plak_history demo save --note 'background note with spaces' --background > "$tmpdir/queued"
for _ in {1..100}; do
    plak_history demo jobs > "$tmpdir/jobs"
    if grep -q '"status": "done"' "$tmpdir/jobs"; then break; fi
    sleep 0.05
done
grep -q '"status": "done"' "$tmpdir/jobs"
plak_history demo restore invalid plugins/demo --yes --background > "$tmpdir/queued"
for _ in {1..100}; do
    plak_history demo jobs > "$tmpdir/jobs"
    if grep -q '"status": "failed"' "$tmpdir/jobs"; then break; fi
    sleep 0.05
done
grep -q '"status": "failed"' "$tmpdir/jobs"
grep -q 'Invalid history ID' "$tmpdir/jobs"
# Scheduling is opt-in, invokes the user's CLI, and preserves other cron jobs.
export TEST_CRONTAB="$tmpdir/crontab"
printf '0 0 * * * unrelated-job\n' > "$TEST_CRONTAB"
crontab() {
    if [ "$1" = -l ]; then cat "$TEST_CRONTAB";
    else cp "$1" "$TEST_CRONTAB"; fi
}
plak_history demo schedule daily --enable >/dev/null
plak_history demo schedule daily --enable >/dev/null
[ "$(grep -c '# plak-history:demo' "$TEST_CRONTAB")" = 1 ]
grep -q 'HOME=' "$TEST_CRONTAB"
grep -q 'unrelated-job' "$TEST_CRONTAB"
plak_history demo schedule --disable >/dev/null
if grep -q '# plak-history:demo' "$TEST_CRONTAB"; then exit 1; fi
grep -q unrelated-job "$TEST_CRONTAB"
echo 'Component history save/diff/rollback/jobs/schedule tests passed'
