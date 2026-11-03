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
<title>Edit <?= htmlspecialchars($site, ENT_QUOTES, 'UTF-8') ?> · Plak</title>
<script>
(function () {
  try {
    var saved = localStorage.getItem('plak-editor-theme');
    var theme = (saved === 'dark' || saved === 'light') ? saved : 'dark';
    document.documentElement.setAttribute('data-theme', theme);
  } catch (event) {
    document.documentElement.setAttribute('data-theme', 'dark');
  }
})();
</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="editor.css?v=<?= $cssVersion ?>">
</head>
<body class="<?= $embed ? 'embed' : '' ?>">
<header class="topbar">
  <div class="brand">
    <span class="brand-mark" aria-hidden="true">P</span>
    <span>Plak <span class="brand-sub">HTML editor</span></span>
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
