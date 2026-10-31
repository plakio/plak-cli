<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/lib/html-site.php';

$site = isset($_GET['plak_site']) ? (string) $_GET['plak_site'] : '';
$requested = isset($_GET['plak_path']) ? (string) $_GET['plak_path'] : '/';
$public = plak_html_public_dir($site);
if ($public === null) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Site not found.');
}

$rel = $requested === '/' || $requested === '' ? 'index.html' : ltrim($requested, '/');
$file = plak_html_resolve($public, $rel, false);
if ($file === null) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Not found.');
}

$html = file_get_contents($file);
if ($html === false) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    exit('Could not read the file.');
}

$host = (string) ($_SERVER['HTTP_HOST'] ?? '');
$hostname = strtolower(rtrim(preg_replace('/:\d+$/', '', $host) ?: $host, '.'));

// Only decorate the site's own local host (or an explicit local mapping).
// A `plak share` tunnel or a LAN address must never receive the editor.
$allowedHosts = [strtolower($site . '.localhost')];
$mappingsFile = dirname($public) . '/mappings';
if (is_file($mappingsFile)) {
    foreach (file($mappingsFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $mapping) {
        $mapping = strtolower(trim($mapping));
        if ($mapping !== '' && !str_starts_with($mapping, '#')) {
            $allowedHosts[] = rtrim($mapping, '.');
        }
    }
}
if (!in_array($hostname, $allowedHosts, true)) {
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'HEAD') {
        exit;
    }
    echo $html;
    exit;
}

$editorBase = plak_html_dashboard_base();
$page = '/' . ltrim($rel, '/');
$loader = '<script src="' . htmlspecialchars($editorBase . '/editor/loader.js?v=1', ENT_QUOTES, 'UTF-8') . '"'
    . ' data-plak-site="' . htmlspecialchars($site, ENT_QUOTES, 'UTF-8') . '"'
    . ' data-plak-host="' . htmlspecialchars($hostname, ENT_QUOTES, 'UTF-8') . '"'
    . ' data-plak-page="' . htmlspecialchars($page, ENT_QUOTES, 'UTF-8') . '"></script>';

if (stripos($html, '</body>') !== false) {
    $html = preg_replace_callback(
        '/<\/body>/i',
        static fn(): string => $loader . '</body>',
        $html,
        1
    );
} else {
    $html .= $loader;
}

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'HEAD') {
    exit;
}
echo $html;
