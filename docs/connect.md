# `plak connect` — CLI ↔ panel (CLI-24)

Device flow estilo Botmail. La CLI pide un pairing, el humano aprueba con
1 clic en el panel y el mismo token pendiente se convierte en API key
personal. Sin copiar secretos a mano.

```bash
plak connect --panel https://panel.plak.work   # producción (defecto)
plak connect --dev                             # $PLAK_PANEL_DEV_URL (defecto http://127.0.0.1:8000)
plak connect --manual --token-stdin            # fallback headless/WSL/auto
plak connect status [--json]
plak disconnect [--yes]
```

## Dónde vive la credencial

`${PLAK_HOME:-$HOME/.plak}/connection.json` — directorio `700`, archivo
`600`, escritura atómica. Contiene `panel_url`, `token` e identidad mínima
(`id`, `name`, `email`). Nunca se carga con `source`, nunca sale en logs,
`--json`, ni historial. Pasar el secreto como argumento está prohibido
(`--token` se rechaza); para automatizar: `echo "$KEY" | plak connect
--manual --token-stdin`.

Cambiar de panel/origen exige una conexión nueva; un token de un origen
jamás se reutiliza en otro. El `status` revalida contra `GET /api/v1/user`.

## Desconectar ≠ revocar

`plak disconnect` solo borra la credencial local. La clave sigue viva en el
servidor hasta revocarla en el panel: **Perfil > API Keys > Revoke**.
Revocar ahí no afecta a otras conexiones, y las claves SSH instaladas por
separado tienen su propio ciclo de vida.

## Desarrollo tras Cloudflare Access

La sesión del navegador no se comparte con este cliente HTTP. Si el panel
dev responde con página/redirect de Access en lugar de JSON, la CLI lo
detecta y no lo trata como conexión válida. Proporciona un token de
servicio de forma explícita (distinto de la API key de Plak):

```bash
export PLAK_CF_ACCESS_TOKEN='<valor>'
plak connect --panel <url-dev>
```

## Decisión `/connect`

Este CLI no tiene intérprete conversacional: no existe comando `/connect`.
Cualquier adaptador externo debe invocar `plak connect` y nunca capturar
ni reenviar el secreto a una conversación.

## Dependencias

`curl` + `python3` (parser JSON real). Sin `-L` en la API: el `Bearer`
nunca se reenvía a otro origen por redirecciones. `429` respeta
`Retry-After`; el HTML se detecta y se informa en lugar de parsearse.
