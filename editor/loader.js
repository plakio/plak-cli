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
        gap: 8px;
        min-height: 44px;
        padding: 11px 16px;
        border: 1px solid #10110f;
        border-radius: 0;
        background: #b7fa45;
        color: #10110f;
        box-shadow: 4px 4px 0 #10110f;
        cursor: pointer;
        font: 600 13px/1 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        letter-spacing: .04em;
        text-transform: uppercase;
      }
      .launcher:hover { transform: translate(2px, 2px); box-shadow: 2px 2px 0 #10110f; }
      .launcher:focus-visible { outline: 3px solid #344aff; outline-offset: 3px; }
      .overlay {
        position: fixed;
        inset: 0;
        z-index: 3;
        display: grid;
        place-items: center;
        padding: 16px;
      }
      .overlay[hidden] { display: none; }
      .backdrop {
        position: absolute;
        inset: 0;
        background: rgba(8, 10, 14, .62);
        backdrop-filter: blur(3px);
      }
      .frame-wrap {
        position: relative;
        width: min(100%, 1440px);
        height: calc(100vh - 32px);
        border: 1px solid #10110f;
        background: #fff;
        box-shadow: 8px 8px 0 #10110f;
        overflow: hidden;
      }
      iframe {
        display: block;
        width: 100%;
        height: 100%;
        border: 0;
        background: #fff;
      }
      .close {
        position: absolute;
        top: 10px;
        right: 10px;
        z-index: 2;
        width: 38px;
        height: 38px;
        border: 1px solid #10110f;
        border-radius: 0;
        background: #fff;
        color: #10110f;
        cursor: pointer;
        font: 600 20px/1 system-ui, sans-serif;
      }
      .close:hover { background: #b7fa45; }
      @media (max-width: 700px) {
        .overlay { padding: 0; }
        .frame-wrap { width: 100%; height: 100vh; box-shadow: none; }
        .launcher { right: 14px; bottom: 14px; }
      }
    </style>
    <button type="button" class="launcher" id="plak-edit-launcher">Edit</button>
    <div class="overlay" id="plak-edit-overlay" hidden>
      <div class="backdrop"></div>
      <div class="frame-wrap">
        <button type="button" class="close" id="plak-edit-close" aria-label="Close editor" title="Close editor">×</button>
        <iframe id="plak-edit-frame" title="Plak HTML editor"></iframe>
      </div>
    </div>`;

  document.documentElement.appendChild(hostElement);

  const launcher = shadow.getElementById('plak-edit-launcher');
  const overlay = shadow.getElementById('plak-edit-overlay');
  const frame = shadow.getElementById('plak-edit-frame');
  const close = shadow.getElementById('plak-edit-close');
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
    close.focus();
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
  close.addEventListener('click', shut);

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
