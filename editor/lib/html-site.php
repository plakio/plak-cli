<?php
declare(strict_types=1);

/**
 * Shared helpers for the local static-site HTML editor.
 *
 * The editor and the capture router both run on the same machine and only
 * touch files under ~/Plak/Sites/<site>.localhost/public.
 */

if (!defined('PLAK_HTML_HOME')) {
    // Replaced with the invoking user's home when Plak deploys the editor.
    define('PLAK_HTML_HOME', '__PLAK_HOME__');
}

function plak_html_home(): string
{
    return rtrim(PLAK_HTML_HOME, '/');
}

function plak_html_sites_dir(): string
{
    return plak_html_home() . '/Plak/Sites';
}

function plak_html_site_name(string $site): ?string
{
    return preg_match('/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/', $site) ? $site : null;
}

function plak_html_public_dir(string $site): ?string
{
    $name = plak_html_site_name($site);
    if ($name === null || plak_html_home() === '') {
        return null;
    }

    $public = realpath(plak_html_sites_dir() . '/' . $name . '.localhost/public');
    if ($public === false || !is_dir($public)) {
        return null;
    }
    // The HTML editor is only for static sites. WordPress has its own plugin.
    if (is_file($public . '/wp-config.php')) {
        return null;
    }
    return $public;
}

function plak_html_resolve(string $public, string $rel, bool $allowDir = false): ?string
{
    $rel = str_replace('\\', '/', $rel);
    if ($rel === '' || str_contains($rel, "\0")) {
        return null;
    }

    $rel = ltrim($rel, '/');
    if (preg_match('#(^|/)\.\.(/|$)#', $rel)) {
        return null;
    }

    $path = realpath($public . '/' . $rel);
    if ($path === false) {
        return null;
    }
    if ($path !== $public && !str_starts_with($path, $public . DIRECTORY_SEPARATOR)) {
        return null;
    }

    if (is_dir($path)) {
        if (!$allowDir) {
            return null;
        }
        $path = $path . '/index.html';
    }

    if (!is_file($path) || !preg_match('/\.(?:html?|htm)$/i', $path)) {
        return null;
    }
    return $path;
}

function plak_html_https_port(): int
{
    $port = 443;
    $config = plak_html_home() . '/Plak/config';
    if (is_file($config)) {
        $cfg = parse_ini_file($config);
        if (is_array($cfg) && !empty($cfg['HTTPS_PORT'])) {
            $port = (int) $cfg['HTTPS_PORT'];
        }
    }
    return $port;
}

function plak_html_dashboard_base(): string
{
    $port = plak_html_https_port();
    return 'https://plak.localhost' . ($port === 443 ? '' : ':' . $port);
}

function plak_html_site_base(string $site): ?string
{
    $name = plak_html_site_name($site);
    if ($name === null) {
        return null;
    }
    $port = plak_html_https_port();
    return 'https://' . $name . '.localhost' . ($port === 443 ? '' : ':' . $port);
}
