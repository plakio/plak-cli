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
if ($requestHost === '') {
    plak_editor_error('Invalid request host.', 403);
}
// Browsers omit Origin on same-origin GET and the editor page sets
// Referrer-Policy: no-referrer, so an empty source is expected. The CSRF token
// above is what proves the caller loaded the editor page. When the browser
// does send a source, it must match the host serving the API.
if ($sourceHost !== '' && strcasecmp($requestHost, $sourceHost) !== 0) {
    plak_editor_error('Cross-origin request blocked.', 403);
}
$fetchSite = strtolower((string) ($_SERVER['HTTP_SEC_FETCH_SITE'] ?? ''));
if ($sourceHost === '' && in_array($fetchSite, ['cross-site', 'same-site'], true)) {
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

if ($method === 'POST' && $action === 'upload') {
    $file = $_FILES['file'] ?? null;
    if (!is_array($file) || ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        plak_editor_error('No image was uploaded.');
    }
    $size = (int) ($file['size'] ?? 0);
    if ($size <= 0 || $size > 10 * 1024 * 1024) {
        plak_editor_error('Images must be between 1 byte and 10 MB.', 413);
    }
    $tmp = (string) ($file['tmp_name'] ?? '');
    if ($tmp === '' || !is_uploaded_file($tmp)) {
        plak_editor_error('Invalid image upload.', 400);
    }
    $mime = function_exists('finfo_open')
        ? (string) (new finfo(FILEINFO_MIME_TYPE))->file($tmp)
        : (string) mime_content_type($tmp);
    $extensions = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'image/avif' => 'avif',
    ];
    if (!isset($extensions[$mime])) {
        plak_editor_error('Upload a valid image: JPEG, PNG, GIF, WebP or AVIF.', 415);
    }

    $uploads = $public . '/uploads';
    if (!is_dir($uploads) && !@mkdir($uploads, 0755, true) && !is_dir($uploads)) {
        plak_editor_error('Could not create the uploads folder.', 500);
    }
    $realUploads = realpath($uploads);
    if ($realUploads === false || !str_starts_with($realUploads, $public . DIRECTORY_SEPARATOR)) {
        plak_editor_error('Invalid uploads folder.', 500);
    }

    $original = (string) ($file['name'] ?? '');
    $base = strtolower((string) pathinfo($original, PATHINFO_FILENAME));
    $base = trim((string) preg_replace('/[^a-z0-9]+/', '-', $base), '-');
    if ($base === '') {
        $base = 'image';
    }
    $name = substr($base, 0, 60) . '-' . bin2hex(random_bytes(4)) . '.' . $extensions[$mime];
    $target = $realUploads . '/' . $name;
    if (!@move_uploaded_file($tmp, $target)) {
        plak_editor_error('Could not store the uploaded image.', 500);
    }
    @chmod($target, 0644);

    plak_editor_json([
        'success' => true,
        'url' => '/uploads/' . $name,
        'path' => 'uploads/' . $name,
        'bytes' => $size,
        'mime' => $mime,
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
