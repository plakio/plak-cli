#!/usr/bin/env bash
# Local dashboard/editor/Adminer i18n regression tests.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null

fail() {
    echo "i18n regression test failed: $1" >&2
    exit 1
}

python3 - <<'PY'
import json
from pathlib import Path
path = Path('assets/lang/i18n.json')
data = json.loads(path.read_text())
assert set(data) == {'en', 'es', 'pt', 'fr'}, data.keys()
for locale in ('es', 'pt', 'fr'):
    assert len(data[locale]) >= 350, (locale, len(data[locale]))
    for key, value in data[locale].items():
        assert key and isinstance(value, str) and value.strip(), (locale, key)
for key in (
    'Overview', 'Websites', 'Services', 'Add site', 'Language',
    'Plak local — sites', 'Invalid request.', 'Back to dashboard ↗',
    'create snapshot', 'refresh info', 'Delete this message?',
):
    for locale in ('es', 'pt', 'fr'):
        assert key in data[locale], (locale, key)
PY

grep -q 'window.PlakI18n' assets/i18n.js || fail 'i18n runtime entry point is missing'
grep -q 'MutationObserver' assets/i18n.js || fail 'i18n runtime does not translate dynamic text'
grep -q 'data-lang-option' assets/i18n.js || fail 'i18n runtime does not bind the language switcher'
grep -q 'data-lang-select' assets/i18n.js || fail 'i18n runtime does not bind native language selects'
grep -q 'adminer_lang' assets/i18n.js || fail 'i18n runtime does not share the Adminer language'
if command -v node >/dev/null 2>&1; then
    node --check assets/i18n.js
    node --check adminer-theme/adminer.js
    node --check editor/editor.js
    node --check editor/loader.js
fi
if grep -R -n -F '?lang=' shared/site/runtime editor/index.php editor/editor.js adminer-theme/adminer.js >/dev/null; then
    fail 'local UI adds a lang URL parameter'
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/plak-i18n.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"
export PLAK_NO_PATH_PRELUDE=1
mkdir -p "$HOME" "$tmpdir/gui"
source ./plak.sh >/dev/null
deploy_i18n_assets "$tmpdir/gui" || fail 'deploy_i18n_assets failed'
[ -s "$tmpdir/gui/i18n.js" ] || fail 'deploy_i18n_assets produced no file'
grep -q 'window.PLAK_I18N' "$tmpdir/gui/i18n.js" || fail 'deployed i18n.js lacks the dictionary'
grep -q '"es"' "$tmpdir/gui/i18n.js" || fail 'deployed i18n.js lacks Spanish'
grep -q 'window.PlakI18n' "$tmpdir/gui/i18n.js" || fail 'deployed i18n.js lacks the runtime'

echo 'Local i18n regression tests passed.'
