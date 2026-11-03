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
        padding: .55rem .85rem;
        border: 1px solid #10110f;
        border-radius: 3px;
        background: #b7fa45;
        color: #10110f;
        box-shadow: 4px 4px 0 #10110f;
        cursor: pointer;
        font: 600 12px/1 "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
        letter-spacing: .02em;
      }
      .launcher span { opacity: .85; }
      .launcher:hover { transform: translate(2px, 2px); box-shadow: 2px 2px 0 #10110f; }
      .launcher:focus-visible { outline: 3px solid #344aff; outline-offset: 3px; }
      .overlay {
        position: fixed;
        inset: 0;
        z-index: 3;
        background: #0e110f;
      }
      .overlay[hidden] { display: none; }
      .frame-wrap {
        width: 100%;
        height: 100%;
        background: #0e110f;
        overflow: hidden;
      }
      iframe {
        display: block;
        width: 100%;
        height: 100%;
        border: 0;
        background: #0e110f;
      }
      @media (max-width: 700px) {
        .launcher { right: 14px; bottom: 14px; }
      }
    </style>
    <button type="button" class="launcher" id="plak-edit-launcher"><span aria-hidden="true">&gt;_</span> Edit</button>
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
