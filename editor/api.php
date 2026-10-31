<?php
declare(strict_types=1);

require_once dirname(__DIR__, 2) . '/lib/html-site.php';
require_once dirname(__DIR__) . '/dashboard-auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function plak_editor_json(array $payload, int $status = 200): never
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function plak_editor_error(string $message, int $status = 400, array $extra = []): never
{
    plak_editor_json(['success' => false, 'message' => $message] + $extra, $status);
}

$ip = (string) ($_SERVER['REMOTE_ADDR'] ?? '');
$loopback = in_array($ip, ['127.0.0.1', '::1', '::ffff:127.0.0.1'], true);
// Allow the WSL2 private adapter so a Windows browser can reach the editor,
// but never the Tailscale CGNAT/ULA ranges: editing is local-only.
$private = preg_match('/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|fe80:|::ffff:(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.))/i', $ip) === 1;
if (!$loopback && !$private) {
    plak_editor_error('This answers only on the machine running Plak.', 403);
}

$token = plak_site_dashboard_token(plak_html_home() . '/Plak/cache/dashboard-token');
$given = (string) ($_SERVER['HTTP_X_PLAK_CSRF'] ?? '');
if ($given === '' || !hash_equals($token, $given)) {
    plak_editor_error('Invalid or missing CSRF token.', 403);
}

$requestHost = preg_replace('/:\d+$/', '', (string) ($_SERVER['HTTP_HOST'] ?? ''));
$source = (string) ($_SERVER['HTTP_ORIGIN'] ?? ($_SERVER['HTTP_REFERER'] ?? ''));
$sourceHost = $source !== '' ? (string) parse_url($source, PHP_URL_HOST) : '';
if ($requestHost === '' || $sourceHost === '' || strcasecmp($requestHost, $sourceHost) !== 0) {
    plak_editor_error('Cross-origin request blocked.', 403);
}

$method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
$action = (string) ($_GET['action'] ?? '');
$site = (string) ($_GET['site'] ?? '');
$public = plak_html_public_dir($site);
if ($public === null) {
    plak_editor_error('Static site not found.', 404);
}

if ($method === 'GET' && $action === 'files') {
    $files = [];
    try {
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($public, FilesystemIterator::SKIP_DOTS)
        );
        foreach ($iterator as $entry) {
            if (!$entry->isFile()) {
                continue;
            }
            $path = $entry->getPathname();
            $rel = substr($path, strlen($public) + 1);
            if (preg_match('#(^|/)\.#', $rel)) {
                continue;
            }
            if (preg_match('#(^|/)(wp-content|wp-includes|wp-admin|node_modules|vendor)(/|$)#i', $rel)) {
                continue;
            }
            if (!preg_match('/\.(?:html?|htm)$/i', $rel)) {
                continue;
            }
            $files[] = [
                'path' => str_replace(DIRECTORY_SEPARATOR, '/', $rel),
                'size' => (int) $entry->getSize(),
                'mtime' => (int) $entry->getMTime(),
            ];
            if (count($files) >= 500) {
                break;
            }
        }
    } catch (Throwable $e) {
        plak_editor_error('Could not list the site files.', 500);
    }

    usort($files, static function (array $a, array $b): int {
        if ($a['path'] === 'index.html') return -1;
        if ($b['path'] === 'index.html') return 1;
        return strcasecmp($a['path'], $b['path']);
    });

    plak_editor_json([
        'success' => true,
        'site' => $site,
        'domain' => plak_html_site_base($site),
        'files' => $files,
    ]);
}

if ($method === 'GET' && $action === 'read') {
    $file = (string) ($_GET['file'] ?? '');
    $path = plak_html_resolve($public, $file, false);
    if ($path === null) {
        plak_editor_error('HTML file not found.', 404);
    }
    $size = (int) filesize($path);
    if ($size > 5 * 1024 * 1024) {
        plak_editor_error('HTML file is too large to edit (max 5 MB).', 413);
    }
    $content = file_get_contents($path);
    if ($content === false) {
        plak_editor_error('Could not read the HTML file.', 500);
    }
    if (function_exists('mb_check_encoding') && !mb_check_encoding($content, 'UTF-8')) {
        plak_editor_error('HTML file is not valid UTF-8.', 415);
    }
    plak_editor_json([
        'success' => true,
        'file' => str_replace(DIRECTORY_SEPARATOR, '/', substr($path, strlen($public) + 1)),
        'content' => $content,
        'sha256' => hash('sha256', $content),
        'mtime' => (int) filemtime($path),
        'size' => $size,
    ]);
}

if ($method === 'POST' && $action === 'save') {
    $raw = file_get_contents('php://input');
    $input = json_decode((string) $raw, true);
    if (!is_array($input)) {
        plak_editor_error('Invalid JSON body.');
    }

    $file = (string) ($input['file'] ?? '');
    $content = (string) ($input['content'] ?? '');
    $baseSha = (string) ($input['base_sha256'] ?? '');
    $path = plak_html_resolve($public, $file, false);
    if ($path === null) {
        plak_editor_error('HTML file not found.', 404);
    }
    if (strlen($content) > 5 * 1024 * 1024) {
        plak_editor_error('HTML file is too large to save (max 5 MB).', 413);
    }
    if (function_exists('mb_check_encoding') && !mb_check_encoding($content, 'UTF-8')) {
        plak_editor_error('HTML content is not valid UTF-8.', 415);
    }

    $current = file_get_contents($path);
    if ($current === false) {
        plak_editor_error('Could not read the current HTML file.', 500);
    }
    $currentSha = hash('sha256', $current);
    if ($baseSha === '' || !hash_equals($currentSha, $baseSha)) {
        plak_editor_json([
            'success' => false,
            'code' => 'conflict',
            'message' => 'The file changed on disk. Reload before saving.',
            'sha256' => $currentSha,
        ], 409);
    }

    $backupDir = plak_html_home() . '/Plak/cache/html-editor/' . $site . '/' . str_replace(['/', '\\'], '__', $file);
    if (!is_dir($backupDir) && !@mkdir($backupDir, 0755, true) && !is_dir($backupDir)) {
        plak_editor_error('Could not create the editor backup folder.', 500);
    }
    $backup = $backupDir . '/' . date('Ymd-His') . '-' . bin2hex(random_bytes(3)) . '.html';
    if (!@copy($path, $backup)) {
        plak_editor_error('Could not back up the current HTML file.', 500);
    }

    $temp = tempnam(dirname($path), '.plak-edit-');
    if ($temp === false) {
        plak_editor_error('Could not create a temporary file.', 500);
    }
    if (file_put_contents($temp, $content) === false) {
        @unlink($temp);
        plak_editor_error('Could not write the edited HTML file.', 500);
    }
    $mode = fileperms($path);
    if ($mode !== false) {
        @chmod($temp, $mode & 0777);
    }
    if (!@rename($temp, $path)) {
        @unlink($temp);
        plak_editor_error('Could not replace the HTML file.', 500);
    }

    plak_editor_json([
        'success' => true,
        'file' => str_replace(DIRECTORY_SEPARATOR, '/', substr($path, strlen($public) + 1)),
        'sha256' => hash('sha256', $content),
        'mtime' => (int) filemtime($path),
        'backup' => basename($backup),
    ]);
}

plak_editor_error('Unsupported action.', 405);
