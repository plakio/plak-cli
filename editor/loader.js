(() => {
  const script = document.currentScript;
  if (!script || window.top !== window.self) return;

  const site = script.dataset.plakSite || '';
  const host = script.dataset.plakHost || '';
  const page = script.dataset.plakPage || '/';
  if (!site || !host || location.hostname !== host) return;
  if (document.getElementById('plak-editor-host')) return;

  const editorOrigin = new URL(script.src).origin;
  const file = page === '/' ? 'index.html' : page.replace(/^\/+/, '');
  const editorUrl = `${editorOrigin}/editor/?site=${encodeURIComponent(site)}&embed=1&file=${encodeURIComponent(file)}`;

  const hostElement = document.createElement('div');
  hostElement.id = 'plak-editor-host';
  hostElement.style.cssText = 'position:fixed;inset:0;z-index:2147483647;pointer-events:none;';
  const shadow = hostElement.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      .launcher,
      .overlay { pointer-events: auto; }
      .launcher {
        position: fixed;
        right: 20px;
        bottom: 20px;
        z-index: 2;
        display: inline-flex;
        align-items: center;
        gap: 7px;
        min-height: 38px;
        padding: .5rem .8rem;
        border: 1px solid #e4e7ed;
        border-radius: 6px;
        background: rgba(255, 255, 255, .97);
        color: #17213a;
        box-shadow: 0 8px 18px rgba(13, 31, 63, .12);
        cursor: pointer;
        font: 600 12px/1 "DM Sans", Inter, ui-sans-serif, system-ui, -apple-system, sans-serif;
        letter-spacing: -.01em;
        backdrop-filter: blur(8px) saturate(140%);
        -webkit-backdrop-filter: blur(8px) saturate(140%);
      }
      .launcher::before {
        content: "";
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: #b7fa45;
        flex: none;
      }
      .launcher span { color: #5e6a80; font-family: "IBM Plex Mono", ui-monospace, Menlo, monospace; font-size: 11px; }
      .launcher:hover { border-color: #3156f5; color: #3156f5; transform: translateY(-1px); }
      .launcher:hover span { color: #3156f5; }
      .launcher:focus-visible { outline: 2px solid #3156f5; outline-offset: 3px; }
      .overlay {
        position: fixed;
        inset: 0;
        z-index: 3;
        background: #f6f8fb;
      }
      .overlay[hidden] { display: none; }
      .frame-wrap {
        width: 100%;
        height: 100%;
        background: #f6f8fb;
        overflow: hidden;
      }
      iframe {
        display: block;
        width: 100%;
        height: 100%;
        border: 0;
        background: #ffffff;
      }
      @media (max-width: 700px) {
        .launcher { right: 14px; bottom: 14px; }
      }
    </style>
    <button type="button" class="launcher" id="plak-edit-launcher"><span aria-hidden="true">&lt;/&gt;</span> Edit site</button>
    <div class="overlay" id="plak-edit-overlay" hidden>
      <div class="frame-wrap">
        <iframe id="plak-edit-frame" title="Plak HTML editor"></iframe>
      </div>
    </div>`;

  document.documentElement.appendChild(hostElement);

  const launcher = shadow.getElementById('plak-edit-launcher');
  const overlay = shadow.getElementById('plak-edit-overlay');
  const frame = shadow.getElementById('plak-edit-frame');
  let opened = false;
  let saved = false;
  let previousOverflow = '';

  function open() {
    if (opened) return;
    opened = true;
    frame.src = editorUrl;
    overlay.hidden = false;
    previousOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = 'hidden';
    frame.focus();
  }

  function shut() {
    if (!opened) return;
    opened = false;
    overlay.hidden = true;
    frame.src = 'about:blank';
    document.documentElement.style.overflow = previousOverflow;
    if (saved) {
      saved = false;
      location.reload();
    } else {
      launcher.focus();
    }
  }

  launcher.addEventListener('click', open);

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && opened) {
      event.preventDefault();
      shut();
    }
  });

  window.addEventListener('message', (event) => {
    if (event.origin !== editorOrigin) return;
    if (event.data?.type === 'plak-editor-close') shut();
    if (event.data?.type === 'plak-editor-saved') saved = true;
  });

  const url = new URL(location.href);
  if (url.searchParams.get('plak-edit') === '1') {
    url.searchParams.delete('plak-edit');
    history.replaceState(null, '', url.pathname + url.search + url.hash);
    open();
  }
})();
