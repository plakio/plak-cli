<?php
declare(strict_types=1);

require_once dirname(__DIR__, 2) . '/lib/html-site.php';
require_once dirname(__DIR__) . '/dashboard-auth.php';

$site = isset($_GET['site']) ? (string) $_GET['site'] : '';
$public = plak_html_public_dir($site);
if ($public === null) {
    http_response_code(404);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Editor · Plak</title></head><body style="font-family:system-ui;padding:3rem;background:#f5f5f1;color:#10110f"><h1>Static site not found</h1><p>The HTML editor only opens static sites. If this is a WordPress site, use its HTML Editor plugin.</p><p><a href="' . htmlspecialchars(plak_html_dashboard_base(), ENT_QUOTES, 'UTF-8') . '/">Back to the Plak dashboard</a></p></body></html>';
    exit;
}

$token = plak_site_dashboard_token(plak_html_home() . '/Plak/cache/dashboard-token');
$domain = plak_html_site_base($site) ?: '';
$initialFile = isset($_GET['file']) ? ltrim((string) $_GET['file'], '/') : 'index.html';
$embed = isset($_GET['embed']) && (string) $_GET['embed'] === '1';
$dashboard = plak_html_dashboard_base();
$siteUrl = $domain . '/';
$dashboardHost = parse_url($dashboard, PHP_URL_HOST) ?: 'plak.localhost';
$dashboardPort = parse_url($dashboard, PHP_URL_PORT);
$editorHost = $dashboardHost . ($dashboardPort ? ':' . $dashboardPort : '');
// Cache-bust assets per deploy so an upgrade never reuses an old editor.
$jsVersion = (string) (@filemtime(__DIR__ . '/editor.js') ?: 1);
$cssVersion = (string) (@filemtime(__DIR__ . '/editor.css') ?: 1);

header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="plak-csrf" content="<?= htmlspecialchars($token, ENT_QUOTES, 'UTF-8') ?>">
<meta name="plak-site" content="<?= htmlspecialchars($site, ENT_QUOTES, 'UTF-8') ?>">
<meta name="plak-domain" content="<?= htmlspecialchars($domain, ENT_QUOTES, 'UTF-8') ?>">
<meta name="plak-file" content="<?= htmlspecialchars($initialFile, ENT_QUOTES, 'UTF-8') ?>">
<meta name="plak-embed" content="<?= $embed ? '1' : '0' ?>">
<link rel="icon" type="image/png" href="data:image/png;base64,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">
<link rel="apple-touch-icon" href="data:image/png;base64,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">
<title>Edit <?= htmlspecialchars($site, ENT_QUOTES, 'UTF-8') ?> · Plak local</title>
<script>
(function () {
  try {
    var saved = localStorage.getItem('plak-theme') || localStorage.getItem('plak-editor-theme');
    var theme = (saved === 'dark' || saved === 'light') ? saved : 'light';
    document.documentElement.setAttribute('data-theme', theme);
  } catch (event) {
    document.documentElement.setAttribute('data-theme', 'light');
  }
})();
</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;450;500;550;600;650;700;750&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="editor.css?v=<?= $cssVersion ?>">
</head>
<body class="<?= $embed ? 'embed' : '' ?>">
<div class="local-context" aria-label="Local environment">
  <span class="ctx-local"><span class="ctx-dot"></span>LOCAL</span>
  <span class="ctx-host"><?= htmlspecialchars($editorHost, ENT_QUOTES, 'UTF-8') ?>/editor</span>
  <span class="ctx-sep">·</span>
  <span class="ctx-site"><?= htmlspecialchars($site, ENT_QUOTES, 'UTF-8') ?></span>
  <a class="ctx-link" href="<?= htmlspecialchars($dashboard, ENT_QUOTES, 'UTF-8') ?>/">Back to dashboard ↗</a>
</div>
<header class="topbar">
  <div class="brand">
    <svg class="brand-cloud" viewBox="0 0 375 156" aria-hidden="true"><path fill="currentColor" d="M 368.640625 128.355469 L 200.929688 128.355469 C 197.421875 128.355469 194.574219 125.519531 194.574219 122.015625 C 194.574219 118.511719 197.421875 115.675781 200.929688 115.675781 L 323.390625 115.675781 C 326.898438 115.675781 329.742188 112.835938 329.742188 109.335938 C 329.742188 105.832031 326.898438 102.992188 323.390625 102.992188 L 310.15625 102.992188 C 307.757812 86.25 297.835938 71.125 279.460938 67.597656 C 279.945312 64.574219 280.203125 61.472656 280.203125 58.3125 C 280.203125 26.152344 254.082031 0.0859375 221.859375 0.0859375 C 193.839844 0.0859375 170.4375 19.800781 164.8125 46.085938 L 164.808594 46.085938 C 156.394531 41.386719 146.695312 38.710938 136.367188 38.710938 C 113.375 38.710938 93.488281 51.988281 83.984375 71.285156 L 6.363281 71.285156 C 2.851562 71.285156 0.0078125 74.125 0.0078125 77.625 C 0.0078125 81.125 2.851562 83.964844 6.363281 83.964844 L 128.820312 83.964844 C 132.332031 83.964844 135.175781 86.804688 135.175781 90.308594 C 135.175781 93.8125 132.332031 96.648438 128.820312 96.648438 L 51.609375 96.648438 C 48.101562 96.648438 45.257812 99.488281 45.257812 102.992188 C 45.257812 106.496094 48.101562 109.335938 51.609375 109.335938 L 79.355469 109.335938 C 85.046875 135.535156 108.410156 155.164062 136.367188 155.164062 L 280.859375 155.164062 C 289.902344 153.535156 297.003906 148.257812 302.015625 141.039062 L 368.640625 141.039062 C 372.148438 141.039062 374.992188 138.199219 374.992188 134.699219 C 374.992188 131.195312 372.148438 128.355469 368.640625 128.355469 "/></svg>
    <span class="brand-name">Plak<b>.</b></span>
    <span class="brand-pill">LOCAL</span>
  </div>
  <div class="site">
    <strong><?= htmlspecialchars($site, ENT_QUOTES, 'UTF-8') ?></strong>
    <a href="<?= htmlspecialchars($siteUrl, ENT_QUOTES, 'UTF-8') ?>" target="_blank" rel="noopener">open site ↗</a>
  </div>
  <label class="file-picker">
    <span>File</span>
    <select id="file-select" aria-label="HTML file"></select>
  </label>
  <div class="actions">
    <button type="button" id="undo" class="icon" disabled title="Undo" aria-label="Undo">↶</button>
    <button type="button" id="redo" class="icon" disabled title="Redo" aria-label="Redo">↷</button>
    <button type="button" id="theme-toggle" class="icon" title="Toggle theme" aria-label="Toggle theme">◐</button>
    <button type="button" id="code-toggle">Code</button>
    <button type="button" id="save" class="primary" disabled title="Save (⌘S)">Save</button>
    <span id="status" class="status">Loading…</span>
    <a class="ghost" href="<?= htmlspecialchars($dashboard, ENT_QUOTES, 'UTF-8') ?>/" target="_blank" rel="noopener" id="dashboard-link">Dashboard</a>
    <button type="button" id="close" class="ghost" hidden>Close</button>
  </div>
</header>

<div id="banner" class="banner" hidden></div>

<main class="canvas">
  <iframe id="preview" title="Site preview" sandbox="allow-same-origin"></iframe>
  <textarea id="code" spellcheck="false" hidden></textarea>
</main>

<div class="modal" id="image-modal" hidden>
  <div class="modal-backdrop" data-modal-close="image"></div>
  <section class="modal-card" role="dialog" aria-modal="true" aria-labelledby="image-modal-title">
    <header>
      <h2 id="image-modal-title">Image</h2>
      <button type="button" class="modal-x" data-modal-close="image" aria-label="Close image editor">×</button>
    </header>
    <label class="field">Image URL
      <input id="image-url" type="text" placeholder="https://… or /uploads/…" autocomplete="off">
    </label>
    <div class="field">Upload from computer
      <div class="field-row">
        <input id="image-file" type="file" accept="image/jpeg,image/png,image/gif,image/webp,image/avif" hidden>
        <button type="button" id="image-upload">Choose image…</button>
        <span id="image-upload-status" class="muted"></span>
      </div>
    </div>
    <label class="field">Alt text
      <input id="image-alt" type="text" autocomplete="off">
    </label>
    <div class="image-preview"><img id="image-preview" alt=""></div>
    <footer class="modal-actions">
      <button type="button" data-modal-close="image">Cancel</button>
      <button type="button" id="image-apply" class="primary">Apply</button>
    </footer>
  </section>
</div>

<div class="modal" id="link-modal" hidden>
  <div class="modal-backdrop" data-modal-close="link"></div>
  <section class="modal-card" role="dialog" aria-modal="true" aria-labelledby="link-modal-title">
    <header>
      <h2 id="link-modal-title">Link</h2>
      <button type="button" class="modal-x" data-modal-close="link" aria-label="Close link editor">×</button>
    </header>
    <label class="field">Link URL
      <input id="link-href" type="text" placeholder="https://…, /page.html or #section" autocomplete="off">
    </label>
    <label class="check">
      <input id="link-target" type="checkbox">
      Open in a new tab
    </label>
    <footer class="modal-actions">
      <button type="button" data-modal-close="link">Cancel</button>
      <button type="button" id="link-apply" class="primary">Apply</button>
    </footer>
  </section>
</div>

<script src="editor.js?v=<?= $jsVersion ?>" defer></script>
</body>
</html>
