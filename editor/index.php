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
<link rel="stylesheet" href="editor.css">
</head>
<body class="<?= $embed ? 'embed' : '' ?>">
<header class="topbar">
  <div class="brand">
    <span class="brand-mark" aria-hidden="true">&gt;</span>
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
    <button type="button" id="code-toggle">Code</button>
    <button type="button" id="save" class="primary" disabled>Save</button>
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

<script src="editor.js" defer></script>
</body>
</html>
