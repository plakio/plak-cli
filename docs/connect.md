# `plak connect` — CLI ↔ panel (CLI-24)

Device flow estilo Botmail. La CLI pide un pairing, el humano aprueba con
1 clic en el panel y el mismo token pendiente se convierte en API key
personal. Sin copiar secretos a mano.

```bash
plak connect --panel https://cloud.plak.io   # producción (defecto)
plak connect --dev                             # $PLAK_PANEL_DEV_URL (defecto http://127.0.0.1:8000)
plak connect --billing                         # pide billing:request al aprobar el dispositivo
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

## Scopes de las API keys

El pairing normal crea una clave con `user:read` + `ssh:authorize` (lectura y
autorización SSH). `plak connect --billing` solicita además `billing:request`
para poder comprar servidores; el panel decide si lo concede al aprobar el
dispositivo (PLA-277). Hasta que el panel desplegado lo conceda, la CLI avisa
y el fallback es una API key manual con ese scope.

Los scopes de escritura (`servers:write`, `sites:write`) y `billing:request`
son opt-in: se marcan al crear una clave en **Perfil > API Keys**. Para
usarlos en la CLI, conecta esa clave con `plak connect --manual
--token-stdin`.

`offers` necesita `user:read`; `buy-server` y `purchase-request` solo
necesitan `billing:request` (el panel valida el par oferta/región en el
`POST`). Una clave con ambos scopes cubre el flujo completo: explorar el
catálogo y solicitar/consultar la compra.

`plak connect status` muestra los scopes reales de la conexión y si puede
solicitar compras (`billing_granted` en `--json`). `billing:request` solo
permite solicitar una compra y consultar su estado; no puede aprobar ni pagar.
El titular abre el `approval_url` interno en un navegador autenticado. La CLI
nunca recibe ni imprime la URL de checkout de Polar, el customer portal ni el
token.

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
