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
        min-height: 40px;
        padding: .55rem .9rem;
        border: 1px solid #2f36fa;
        border-radius: 8px;
        background: #2f36fa;
        color: #fff;
        box-shadow: 0 6px 20px rgba(16, 17, 15, .22);
        cursor: pointer;
        font: 600 13px/1 ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        letter-spacing: .01em;
      }
      .launcher:hover { filter: brightness(1.08); }
      .launcher:focus-visible { outline: 3px solid rgba(47, 54, 250, .45); outline-offset: 3px; }
      .overlay {
        position: fixed;
        inset: 0;
        z-index: 3;
        background: #fff;
      }
      .overlay[hidden] { display: none; }
      .frame-wrap {
        width: 100%;
        height: 100%;
        background: #fff;
        overflow: hidden;
      }
      iframe {
        display: block;
        width: 100%;
        height: 100%;
        border: 0;
        background: #fff;
      }
      @media (max-width: 700px) {
        .launcher { right: 14px; bottom: 14px; }
      }
    </style>
    <button type="button" class="launcher" id="plak-edit-launcher">Edit</button>
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
