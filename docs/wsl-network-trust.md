# WSL local domains and HTTPS

Static HTML deployment is not implicated in the WordPress CLI regression.
The reported custom `plak-web.localhost` assets returned HTTP 200 from Windows.
Those host/browser observations have not been independently reproduced here.

## Resolution and privileges

`.localhost` is special-use: Chrome/Edge can resolve it internally without a
hosts entry. Linux libc tools, curl builds, NSS/systemd configuration and Windows
resolution may differ. Check the actual clients, not just one browser:

```sh
getent ahostsv4 plak-web.localhost
curl --cacert /path/to/current/root.crt https://plak-web.localhost/
```

In Windows, compare `Resolve-DnsName plak-web.localhost` with Chrome/Edge access;
a DNS cmdlet failure does not imply that a browser's special-use handling fails.
Record WSL NAT/mirrored networking and localhost-forwarding configuration. If
Windows cannot reach the endpoint, test its port/forwarding first; a hosts entry
cannot repair networking. `plak wsl-hosts` remains an explicit Windows hosts
operation requiring administrator authorization (#39), not a universal prerequisite.

WSL reload avoids Linux hosts edits when `getent ahostsv4` already resolves the
`.localhost` name to 127.0.0.1. If not, Plak attempts its existing Linux hosts
setup and now returns an explicit failure on denied sudo. Run it interactively
with authorization rather than swallowing that error. Never test against real
hosts files in automation. Custom mappings may still require hosts/DNS setup.

## Explicit Windows trust

Caddy `tls internal` creates a local CA. Its root is normally at
`${XDG_DATA_HOME:-$HOME/.local/share}/caddy/pki/authorities/local/root.crt`;
the privileged trust copy may be in `/usr/local/share/ca-certificates`.
Check the current Caddy storage/user if that root is absent or has rotated.
Do not copy private keys. Trusting a CA permits it to issue trusted certificates;
only authorize your own Plak CA after verifying its SHA256 fingerprint.

```sh
plak trust --windows          # preview fingerprint; no store changes
plak trust --windows --yes    # explicit import into Windows CurrentUser\Root
```

This requires WSL interop (`powershell.exe`) and openssl. No administrator
elevation, LocalMachine import, system packages or Linux trust changes occur.
Import is idempotent by certificate thumbprint. Policy denial is reported as a
failure. Restart Windows Chrome/Edge after import and verify the certificate
issuer/site name without bypassing warnings. To undo, remove only the displayed
thumbprint from your current-user Windows root store, after checking ownership.

`plak trust` remains the explicit **Linux** system/NSS/Homebrew trust operation;
it does not imply Windows trust. Missing NSS tools are reported with manual
package guidance rather than silently installed. A Linuxbrew curl may use a
different CA bundle (#41). For isolated tests use the exact root with `--cacert`,
never disable TLS verification globally or recommend warning bypasses.

## Remaining manual matrix

Automation on Linux uses temporary certificates and simulated PowerShell/sudo;
it does not establish native Windows trust behavior. Before claiming WSL support
validated, check Ubuntu26.04 WSL2, NAT/mirrored mode, Windows Chrome and Edge,
Linux system and Homebrew curl, successful preview/import/reimport, denied
authorization, CA rotation, and HTTP 200 for custom HTML/CSS/JS/assets. Use fresh
isolated sites and remove only their owned artifacts/certificates afterward.
