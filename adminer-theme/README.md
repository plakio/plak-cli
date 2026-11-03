<p align="center">
  <h2 align="center">Plak for Adminer</h2>
</p>

<p align="center">
  A <a href="https://plak.sh">Plak</a>-native skin for <a href="https://www.adminer.org/">Adminer</a>, matching the local-site landing page and dashboard.
</p>

## About

Dark and light themes, toggled from the top-right:

- **Dark** — shell green-black (`#0e110f`), panels (`#151a16`), acid actions (`#b7fa45`).
- **Light** — paper (`#f5f5f1`), ink borders, acid actions.

Typography uses Outfit and JetBrains Mono in the same roles as Plak's Console dashboard: sans UI and mono metadata. First visits start in dark mode; the toggle persists an explicit choice in `localStorage`.

## Features

- Plak design tokens for colors, radii, shadows, and type.
- Plak DB brand treatment in the Adminer sidebar.
- Explicit light/dark toggle with a sun/moon icon, persisted in `localStorage`.
- Drag-to-resize sidebar (180–480px), double-click the handle to reset. Width persisted in `localStorage`.
- Hidden Logout button (Plak's autologin makes it a no-op).
- Brand title links back to the server home.
- CSP-safe: all injected scripts use Adminer's `nonce()`.

## Usage

Adminer auto-loads any `adminer.css` next to its entry point. Drop both files in:

```bash
curl -sL "https://raw.githubusercontent.com/plakio/plak-cli/main/adminer-theme/adminer.css" -o adminer.css
curl -sL "https://raw.githubusercontent.com/plakio/plak-cli/main/adminer-theme/adminer.js"  -o adminer.js
```

`adminer.js` is loaded via an override on the `Adminer::head()` method — see Plak's `commands/install` for the entry-point PHP that wires it in.

## Compatibility

- Adminer 5.x (uses the `Adminer\` namespace).
- Modern browsers — CSS custom properties, `oklch()`, `color-mix()`, pointer events.

## License

MIT.

## Credits

- [Adminer](https://www.adminer.org/) — database management in a single PHP file.
- [Plak](https://github.com/plakio/plak-cli) — local WordPress development.
