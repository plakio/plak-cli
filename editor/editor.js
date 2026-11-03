(() => {
  const meta = (name) => document.querySelector(`meta[name="${name}"]`)?.content || '';
  const site = meta('plak-site');
  const domain = meta('plak-domain');
  const csrf = meta('plak-csrf');
  const initialFile = (meta('plak-file') || 'index.html').replace(/^\/+/, '');
  const embed = meta('plak-embed') === '1';

  const fileSelect = document.getElementById('file-select');
  const preview = document.getElementById('preview');
  const code = document.getElementById('code');
  const saveButton = document.getElementById('save');
  const codeToggle = document.getElementById('code-toggle');
  const undoButton = document.getElementById('undo');
  const redoButton = document.getElementById('redo');
  const themeToggle = document.getElementById('theme-toggle');
  const closeButton = document.getElementById('close');
  const status = document.getElementById('status');
  const banner = document.getElementById('banner');
  const imageModal = document.getElementById('image-modal');
  const imageUrl = document.getElementById('image-url');
  const imageAlt = document.getElementById('image-alt');
  const imageFile = document.getElementById('image-file');
  const imageUpload = document.getElementById('image-upload');
  const imageUploadStatus = document.getElementById('image-upload-status');
  const imagePreview = document.getElementById('image-preview');
  const linkModal = document.getElementById('link-modal');
  const linkHref = document.getElementById('link-href');
  const linkTarget = document.getElementById('link-target');

  const state = {
    files: [],
    file: '',
    source: '',
    saved: '',
    sha: '',
    dirty: false,
    saving: false,
    mode: 'preview',
    initial: new WeakMap(),
    loading: false,
  };
  const imageEditor = { index: -1 };
  const linkEditor = { index: -1 };

  if (closeButton) closeButton.hidden = !embed;

  function updateThemeToggle() {
    if (!themeToggle) return;
    const dark = document.documentElement.dataset.theme === 'dark';
    const label = dark ? 'Switch to light mode' : 'Switch to dark mode';
    themeToggle.title = label;
    themeToggle.setAttribute('aria-label', label);
  }

  if (themeToggle) {
    themeToggle.addEventListener('click', () => {
      const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      document.documentElement.dataset.theme = next;
      try { localStorage.setItem('plak-editor-theme', next); } catch (event) {}
      updateThemeToggle();
    });
    updateThemeToggle();
  }

  async function request(action, { method = 'GET', params = {}, body = null } = {}) {
    const url = new URL('api.php', location.href);
    url.searchParams.set('action', action);
    url.searchParams.set('site', site);
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
    });

    const response = await fetch(url, {
      method,
      cache: 'no-store',
      headers: {
        'X-Plak-CSRF': csrf,
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify({ ...body, site, csrf }) : undefined,
    });

    return parseResponse(response);
  }

  async function upload(file) {
    const url = new URL('api.php', location.href);
    url.searchParams.set('action', 'upload');
    url.searchParams.set('site', site);
    const form = new FormData();
    form.append('file', file);
    form.append('site', site);
    form.append('csrf', csrf);

    const response = await fetch(url, {
      method: 'POST',
      cache: 'no-store',
      headers: { 'X-Plak-CSRF': csrf },
      body: form,
    });
    return parseResponse(response);
  }

  async function parseResponse(response) {
    let data;
    try {
      data = await response.json();
    } catch {
      throw new Error(`Invalid server response (${response.status}).`);
    }
    if (!response.ok || !data.success) {
      const error = new Error(data.message || `Request failed (${response.status}).`);
      error.code = data.code || '';
      error.sha256 = data.sha256 || '';
      throw error;
    }
    return data;
  }

  function escapeText(value) {
    return String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  }

  function escapeAttr(value) {
    return String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  }

  function sanitizeInlineHtml(html) {
    const template = document.createElement('template');
    template.innerHTML = html;
    const allowed = new Set(['b', 'strong', 'i', 'em', 'u']);
    const serialize = (node) => {
      if (node.nodeType === 3) return escapeText(node.nodeValue || '');
      if (node.nodeType !== 1) return '';
      const tag = node.tagName.toLowerCase();
      if (tag === 'br') return '<br>';
      const inner = Array.from(node.childNodes).map(serialize).join('');
      return allowed.has(tag) ? `<${tag}>${inner}</${tag}>` : inner;
    };
    return Array.from(template.content.childNodes).map(serialize).join('');
  }

  function decodeAttr(value) {
    return String(value)
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  }

  function getAttr(tag, name) {
    const pattern = new RegExp(
      `\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>]+))`,
      'i',
    );
    const match = tag.match(pattern);
    if (!match) return '';
    return decodeAttr(match[1] ?? match[2] ?? match[3] ?? '');
  }

  function setAttr(tag, name, value, removeEmpty = true) {
    const pattern = new RegExp(`\\s${name}\\s*=\\s*(?:"[^"]*"|'[^']*'|[^\\s"'=<>]+)`, 'i');
    const next = value === null || value === undefined ? '' : String(value);
    if (removeEmpty && next === '') return tag.replace(pattern, '');
    if (pattern.test(tag)) return tag.replace(pattern, ` ${name}="${escapeAttr(next)}"`);

    const close = tag.match(/\/?>\s*$/);
    if (!close) return tag;
    const body = tag.slice(0, close.index).replace(/\s+$/, '');
    return `${body} ${name}="${escapeAttr(next)}"${close[0]}`;
  }

  function findTag(source, name, index) {
    let seen = 0;
    for (const segment of tokenize(source)) {
      if (segment.type !== 'tag') continue;
      const info = tagInfo(segment.value);
      if (!info || info.closing || info.name !== name) continue;
      if (seen === index) return segment.value;
      seen += 1;
    }
    return null;
  }

  function replaceTag(source, name, index, transform) {
    const segments = tokenize(source);
    let seen = 0;
    for (const segment of segments) {
      if (segment.type !== 'tag') continue;
      const info = tagInfo(segment.value);
      if (!info || info.closing || info.name !== name) continue;
      if (seen === index) {
        segment.value = transform(segment.value);
        break;
      }
      seen += 1;
    }
    return segments.map((segment) => segment.value).join('');
  }

  const EDITABLE = new Set([
    'a', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'blockquote', 'figcaption', 'div', 'span',
    'td', 'th', 'dt', 'dd', 'caption', 'summary',
    'label', 'button', 'strong', 'b', 'em', 'i', 'u', 'small', 'time',
    'address', 'cite', 'q',
  ]);
  const FORBIDDEN = new Set([
    'script', 'style', 'iframe', 'noscript', 'svg', 'template',
    'textarea', 'select', 'option', 'video', 'audio', 'canvas',
  ]);
  const RAW_TEXT = new Set(['script', 'style', 'textarea', 'title']);
  const VOID = new Set([
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
    'link', 'meta', 'param', 'source', 'track', 'wbr',
  ]);

  function findTagEnd(source, start) {
    let quote = '';
    for (let index = start + 1; index < source.length; index += 1) {
      const char = source[index];
      if (quote) {
        if (char === quote) quote = '';
      } else if (char === '"' || char === "'") {
        quote = char;
      } else if (char === '>') {
        return index + 1;
      }
    }
    return source.length;
  }

  function tagInfo(tag) {
    const match = tag.match(/^<\s*(\/?)\s*([a-zA-Z0-9-]+)/);
    if (!match || /^<\s*[!?]/.test(tag)) return null;
    return { closing: match[1] === '/', name: match[2].toLowerCase() };
  }

  function tokenize(source) {
    const segments = [];
    const stack = [];
    let cursor = 0;

    while (cursor < source.length) {
      if (source[cursor] === '<') {
        if (source.startsWith('<!--', cursor)) {
          const end = source.indexOf('-->', cursor + 4);
          const stop = end === -1 ? source.length : end + 3;
          segments.push({ type: 'tag', value: source.slice(cursor, stop) });
          cursor = stop;
          continue;
        }
        if (source.startsWith('<![CDATA[', cursor)) {
          const end = source.indexOf(']]>', cursor + 9);
          const stop = end === -1 ? source.length : end + 3;
          segments.push({ type: 'tag', value: source.slice(cursor, stop) });
          cursor = stop;
          continue;
        }
        if (source.startsWith('<!', cursor) || source.startsWith('<?', cursor)) {
          const end = source.indexOf('>', cursor);
          const stop = end === -1 ? source.length : end + 1;
          segments.push({ type: 'tag', value: source.slice(cursor, stop) });
          cursor = stop;
          continue;
        }

        const end = findTagEnd(source, cursor);
        const tag = source.slice(cursor, end);
        segments.push({ type: 'tag', value: tag });
        const info = tagInfo(tag);

        if (info) {
          if (!info.closing && !VOID.has(info.name) && !/\/\s*>$/.test(tag)) {
            stack.push(info.name);
            if (RAW_TEXT.has(info.name)) {
              const close = new RegExp(`</\\s*${info.name}\\s*>`, 'i');
              const rest = source.slice(end);
              const match = rest.match(close);
              if (match) {
                const contentEnd = end + match.index;
                if (contentEnd > end) {
                  segments.push({
                    type: 'text',
                    value: source.slice(end, contentEnd),
                    editable: false,
                  });
                }
                stack.pop();
                cursor = contentEnd;
                continue;
              }
            }
          } else if (info.closing) {
            const index = stack.lastIndexOf(info.name);
            if (index !== -1) stack.splice(index);
          }
        }

        cursor = end;
        continue;
      }

      const next = source.indexOf('<', cursor);
      const stop = next === -1 ? source.length : next;
      segments.push({
        type: 'text',
        value: source.slice(cursor, stop),
        editable: stack.some((name) => EDITABLE.has(name))
          && !stack.some((name) => FORBIDDEN.has(name)),
      });
      cursor = stop;
    }

    return segments;
  }

  function baseHref() {
    const directory = state.file.includes('/')
      ? state.file.slice(0, state.file.lastIndexOf('/') + 1)
      : '';
    return `${domain.replace(/\/+$/, '')}/${directory}`;
  }

  function buildPreview(source) {
    const segments = tokenize(source);
    let textIndex = 0;
    let imageIndex = 0;
    let linkIndex = 0;
    const openLinks = [];
    const body = segments.map((segment) => {
      if (segment.type === 'text') {
        if (!segment.editable || !segment.value.trim()) return segment.value;
        const index = textIndex;
        textIndex += 1;
        return `<span data-plak-text-index="${index}" contenteditable="true" spellcheck="true">${segment.value}</span>`;
      }

      const info = tagInfo(segment.value);
      if (!info) return segment.value;
      if (info.name === 'img' && !info.closing) {
        const index = imageIndex;
        imageIndex += 1;
        return setAttr(segment.value, 'data-plak-image-index', String(index), false);
      }
      if (info.name === 'a' && !info.closing) {
        const index = linkIndex;
        linkIndex += 1;
        openLinks.push(index);
        return setAttr(segment.value, 'data-plak-link-index', String(index), false);
      }
      if (info.name === 'a' && info.closing) {
        const index = openLinks.pop();
        if (index === undefined) return segment.value;
        return `<span class="plak-link-edit" data-plak-link-edit="${index}" contenteditable="false">Edit link</span>${segment.value}`;
      }
      return segment.value;
    }).join('');

    const head = `
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob: https: http:; media-src data: blob: https: http:; style-src 'unsafe-inline' https: http:; font-src data: https: http:; script-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'">
      <base href="${escapeAttr(baseHref())}">
      <style data-plak-editor-styles>
        [data-plak-text-index] { cursor: text; outline: 1px dashed transparent !important; outline-offset: 2px !important; }
        [data-plak-text-index]:hover { outline-color: rgba(183, 250, 69, .9) !important; background: rgba(183, 250, 69, .12) !important; }
        [data-plak-text-index]:focus { outline: 2px solid #b7fa45 !important; background: rgba(183, 250, 69, .16) !important; }
        img[data-plak-image-index] { cursor: pointer; }
        img[data-plak-image-index]:hover { outline: 3px solid #b7fa45; outline-offset: -3px; }
        img[data-plak-image-index].plak-image-drop {
          outline: 3px dashed #b7fa45 !important;
          outline-offset: -3px !important;
          opacity: .72;
          cursor: copy;
        }
        .plak-link-edit {
          display: none;
          margin-left: .35rem;
          padding: 1px 5px;
          border-radius: 4px;
          background: #b7fa45;
          color: #10110f !important;
          font: 600 10px/1.6 "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
          text-decoration: none !important;
          vertical-align: middle;
          cursor: pointer;
        }
        a[data-plak-link-index]:hover .plak-link-edit,
        a[data-plak-link-index]:focus-within .plak-link-edit { display: inline-block; }
        .plak-format-bar {
          all: initial;
          position: fixed;
          left: 12px;
          bottom: 12px;
          z-index: 2147483647;
          display: flex;
          gap: 2px;
          padding: 3px;
          border-radius: 8px;
          background: rgba(16, 17, 15, .92);
          box-shadow: 0 4px 16px rgba(0, 0, 0, .28);
          font: 600 12px/1 "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
        }
        .plak-format-bar button {
          all: unset;
          box-sizing: border-box;
          display: grid;
          place-items: center;
          width: 30px;
          height: 28px;
          border-radius: 5px;
          color: #fff;
          cursor: pointer;
          text-align: center;
        }
        .plak-format-bar button:hover { background: rgba(255, 255, 255, .16); }
        .plak-format-bar button:focus-visible { outline: 2px solid #b7fa45; outline-offset: 1px; }
      </style>`;

    let documentHtml = body
      .replace(/<base\b[^>]*>/gi, '')
      .replace(/<meta[^>]+http-equiv=["']?refresh["']?[^>]*>/gi, '')
      .replace(/<meta[^>]+http-equiv=["']?Content-Security-Policy["']?[^>]*>/gi, '');

    if (/<head(?:\s[^>]*)?>/i.test(documentHtml)) {
      documentHtml = documentHtml.replace(/<head(?:\s[^>]*)?>/i, (match) => match + head);
    } else if (/<html(?:\s[^>]*)?>/i.test(documentHtml)) {
      documentHtml = documentHtml.replace(
        /<html(?:\s[^>]*)?>/i,
        (match) => `${match}<head>${head}</head>`,
      );
    } else {
      documentHtml = `<!doctype html><html><head>${head}</head><body>${documentHtml}</body></html>`;
    }

    const toolbar = `
      <div class="plak-format-bar" contenteditable="false" role="toolbar" aria-label="Text formatting">
        <button type="button" data-plak-format="bold" title="Bold"><b>B</b></button>
        <button type="button" data-plak-format="italic" title="Italic"><i>I</i></button>
        <button type="button" data-plak-format="underline" title="Underline"><u>U</u></button>
      </div>`;
    if (/<\/body>/i.test(documentHtml)) {
      documentHtml = documentHtml.replace(/<\/body>/i, `${toolbar}</body>`);
    } else {
      documentHtml += toolbar;
    }

    return documentHtml;
  }

  function replaceTextSegment(source, index, html) {
    const segments = tokenize(source);
    let textIndex = 0;
    for (const segment of segments) {
      if (segment.type !== 'text' || !segment.editable || !segment.value.trim()) continue;
      if (textIndex === index) {
        segment.value = sanitizeInlineHtml(html);
        break;
      }
      textIndex += 1;
    }
    return segments.map((segment) => segment.value).join('');
  }

  function updateChrome() {
    saveButton.disabled = !state.dirty || state.saving;
    if (state.saving) {
      status.textContent = 'Saving…';
    } else if (state.dirty) {
      status.textContent = 'Unsaved changes';
    } else if (state.loading) {
      status.textContent = 'Loading…';
    } else {
      status.textContent = 'Saved';
    }
  }

  const history = { stack: [], index: -1, timer: null };

  function updateHistoryChrome() {
    if (undoButton) undoButton.disabled = history.index <= 0;
    if (redoButton) {
      redoButton.disabled = history.index < 0 || history.index >= history.stack.length - 1;
    }
  }

  function pushHistory(source) {
    if (history.index >= 0 && history.stack[history.index] === source) {
      updateHistoryChrome();
      return;
    }
    history.stack = history.stack.slice(0, history.index + 1);
    history.stack.push(source);
    if (history.stack.length > 120) history.stack.shift();
    history.index = history.stack.length - 1;
    updateHistoryChrome();
  }

  function resetHistory(source = state.source) {
    if (history.timer) {
      clearTimeout(history.timer);
      history.timer = null;
    }
    history.stack = [source];
    history.index = 0;
    updateHistoryChrome();
  }

  function scheduleHistory() {
    if (history.timer) clearTimeout(history.timer);
    history.timer = setTimeout(() => {
      history.timer = null;
      pushHistory(state.source);
    }, 450);
  }

  function flushHistory() {
    if (history.timer) {
      clearTimeout(history.timer);
      history.timer = null;
    }
    pushHistory(state.source);
  }

  function restoreHistory() {
    if (history.index < 0 || history.index >= history.stack.length) return;
    state.source = history.stack[history.index];
    state.dirty = state.source !== state.saved;
    code.value = state.source;
    if (state.mode === 'preview') renderPreview();
    updateChrome();
    updateHistoryChrome();
  }

  function undo() {
    flushHistory();
    if (history.index <= 0) return;
    history.index -= 1;
    restoreHistory();
  }

  function redo() {
    flushHistory();
    if (history.index >= history.stack.length - 1) return;
    history.index += 1;
    restoreHistory();
  }

  function showBanner(message, withReload = false) {
    banner.replaceChildren();
    if (!message) {
      banner.hidden = true;
      return;
    }
    banner.append(document.createTextNode(message));
    if (withReload) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = 'Reload file';
      button.addEventListener('click', () => {
        if (confirm('Discard your unsaved changes and reload the file?')) {
          loadFile(state.file, true).catch((error) => showBanner(error.message, true));
        }
      });
      banner.append(button);
    }
    banner.hidden = false;
  }

  function attachPreview() {
    const doc = preview.contentDocument;
    if (!doc) return;

    state.initial = new WeakMap();
    doc.addEventListener('click', (event) => {
      if (event.target.closest('a, button')) event.preventDefault();
    });
    doc.addEventListener('submit', (event) => event.preventDefault());
    // Commit on input so Save enables as soon as the user types instead of
    // waiting for the editable element to lose focus.
    doc.addEventListener('input', () => commitAll());
    doc.addEventListener('blur', () => {
      commitAll();
      flushHistory();
    }, true);
    doc.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        requestClose();
        return;
      }
      const mod = event.metaKey || event.ctrlKey;
      if (!mod) return;
      const key = event.key.toLowerCase();
      if (key === 'z') {
        event.preventDefault();
        if (event.shiftKey) redo();
        else undo();
      } else if (key === 'y') {
        event.preventDefault();
        redo();
      } else if (key === 's') {
        event.preventDefault();
        save().catch((error) => showBanner(error.message));
      } else if (key === 'b' || key === 'i' || key === 'u') {
        event.preventDefault();
        doc.execCommand('styleWithCSS', false, false);
        doc.execCommand(key === 'b' ? 'bold' : key === 'i' ? 'italic' : 'underline', false, null);
        commitAll();
      }
    });

    doc.querySelectorAll('[data-plak-format]').forEach((button) => {
      button.addEventListener('mousedown', (event) => event.preventDefault());
      button.addEventListener('click', () => {
        doc.execCommand('styleWithCSS', false, false);
        doc.execCommand(button.dataset.plakFormat, false, null);
        commitAll();
      });
    });

    doc.querySelectorAll('[data-plak-text-index]').forEach((element) => {
      state.initial.set(element, element.innerHTML);
      element.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' && !event.shiftKey) {
          event.preventDefault();
          element.blur();
        }
      });
    });

    doc.querySelectorAll('[data-plak-image-index]').forEach((element) => {
      element.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        openImageModal(Number(element.dataset.plakImageIndex));
      });
    });

    doc.querySelectorAll('[data-plak-link-edit]').forEach((element) => {
      element.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        openLinkModal(Number(element.dataset.plakLinkEdit));
      });
    });

    let dropTarget = null;
    const clearDrop = () => {
      if (dropTarget) dropTarget.classList.remove('plak-image-drop');
      dropTarget = null;
    };
    const draggedFiles = (event) => (
      Array.from(event.dataTransfer?.types || []).includes('Files')
    );
    doc.addEventListener('dragover', (event) => {
      if (draggedFiles(event)) event.preventDefault();
      const image = event.target.closest?.('img[data-plak-image-index]');
      if (!image) return;
      if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
      if (dropTarget !== image) {
        clearDrop();
        dropTarget = image;
        image.classList.add('plak-image-drop');
      }
    });
    doc.addEventListener('dragleave', (event) => {
      if (event.target === dropTarget) clearDrop();
    });
    doc.addEventListener('drop', async (event) => {
      const files = Array.from(event.dataTransfer?.files || []);
      if (files.length) event.preventDefault();
      clearDrop();
      const image = event.target.closest?.('img[data-plak-image-index]');
      if (!image) {
        if (files.length) {
          showBanner('Drop the image over an existing image to replace it.');
        }
        return;
      }
      if (!files.length) return;
      if (files.length > 1) {
        showBanner('Drop one image at a time.');
        return;
      }
      const file = files[0];
      if (!file.type.startsWith('image/')) {
        showBanner('Drop an image file: JPEG, PNG, GIF, WebP or AVIF.');
        return;
      }
      const index = Number(image.dataset.plakImageIndex);
      const fileAtDrop = state.file;
      image.style.opacity = '0.45';
      try {
        const data = await upload(file);
        if (state.file !== fileAtDrop) return;
        commitAll();
        state.source = replaceTag(state.source, 'img', index, (tag) => setAttr(tag, 'src', data.url));
        state.dirty = state.source !== state.saved;
        pushHistory(state.source);
        renderPreview();
        updateChrome();
      } catch (error) {
        image.style.opacity = '';
        showBanner(error.message);
      }
    });
  }

  function commitAll() {
    if (state.mode !== 'preview') return;
    const doc = preview.contentDocument;
    if (!doc) return;

    const changed = [];
    doc.querySelectorAll('[data-plak-text-index]').forEach((element) => {
      const index = Number(element.dataset.plakTextIndex);
      if (Number.isNaN(index)) return;
      const original = state.initial.get(element);
      if (original !== undefined && element.innerHTML !== original) {
        changed.push({ index, html: element.innerHTML });
      }
    });
    if (!changed.length) return;

    changed.sort((left, right) => right.index - left.index);
    let next = state.source;
    changed.forEach(({ index, html }) => {
      next = replaceTextSegment(next, index, html);
    });

    if (next !== state.source) {
      state.source = next;
      state.dirty = state.source !== state.saved;
      scheduleHistory();
    }
    doc.querySelectorAll('[data-plak-text-index]').forEach((element) => {
      state.initial.set(element, element.innerHTML);
    });
    updateChrome();
  }

  function renderPreview() {
    state.mode = 'preview';
    preview.hidden = false;
    code.hidden = true;
    codeToggle.textContent = 'Code';
    preview.onload = attachPreview;
    preview.srcdoc = buildPreview(state.source);
  }

  function resolveUrl(value) {
    if (!value) return '';
    try {
      return new URL(value, baseHref()).href;
    } catch {
      return '';
    }
  }

  function updateImagePreview() {
    const url = resolveUrl(imageUrl.value.trim());
    if (!url) {
      imagePreview.hidden = true;
      imagePreview.removeAttribute('src');
      return;
    }
    imagePreview.hidden = false;
    imagePreview.src = url;
  }

  function closeImageModal() {
    imageModal.hidden = true;
    imageEditor.index = -1;
    preview.focus();
  }

  function openImageModal(index) {
    const tag = findTag(state.source, 'img', index);
    if (tag === null) return;
    imageEditor.index = index;
    imageUrl.value = getAttr(tag, 'src');
    imageAlt.value = getAttr(tag, 'alt');
    imageFile.value = '';
    imageUploadStatus.textContent = '';
    updateImagePreview();
    imageModal.hidden = false;
    imageUrl.focus();
    imageUrl.select();
  }

  function applyImage() {
    if (imageEditor.index < 0) return;
    const url = imageUrl.value.trim();
    if (url === '') {
      imageUploadStatus.textContent = 'Enter an image URL or upload a file.';
      imageUrl.focus();
      return;
    }
    commitAll();
    state.source = replaceTag(state.source, 'img', imageEditor.index, (tag) => {
      const withSrc = setAttr(tag, 'src', url);
      return setAttr(withSrc, 'alt', imageAlt.value.trim(), false);
    });
    state.dirty = state.source !== state.saved;
    pushHistory(state.source);
    renderPreview();
    updateChrome();
    closeImageModal();
  }

  function closeLinkModal() {
    linkModal.hidden = true;
    linkEditor.index = -1;
    preview.focus();
  }

  function openLinkModal(index) {
    const tag = findTag(state.source, 'a', index);
    if (tag === null) return;
    linkEditor.index = index;
    linkHref.value = getAttr(tag, 'href');
    linkTarget.checked = getAttr(tag, 'target').toLowerCase() === '_blank';
    linkModal.hidden = false;
    linkHref.focus();
    linkHref.select();
  }

  function applyLink() {
    if (linkEditor.index < 0) return;
    commitAll();
    state.source = replaceTag(state.source, 'a', linkEditor.index, (tag) => {
      const withHref = setAttr(tag, 'href', linkHref.value.trim());
      return setAttr(withHref, 'target', linkTarget.checked ? '_blank' : '');
    });
    state.dirty = state.source !== state.saved;
    pushHistory(state.source);
    renderPreview();
    updateChrome();
    closeLinkModal();
  }

  async function uploadImage(file) {
    imageUploadStatus.textContent = 'Uploading…';
    imageUpload.disabled = true;
    try {
      const data = await upload(file);
      imageUrl.value = data.url;
      updateImagePreview();
      imageUploadStatus.textContent = `Uploaded ${data.path}`;
    } catch (error) {
      imageUploadStatus.textContent = error.message;
    } finally {
      imageUpload.disabled = false;
    }
  }

  async function loadFile(file, force = false) {
    if (!force && state.dirty && !confirm('Discard your unsaved changes?')) return;
    state.loading = true;
    updateChrome();
    showBanner('');
    const data = await request('read', { params: { file } });
    state.file = data.file;
    state.source = data.content;
    state.saved = data.content;
    state.sha = data.sha256;
    state.dirty = false;
    state.loading = false;
    code.value = state.source;
    fileSelect.value = state.file;
    resetHistory(state.source);
    renderPreview();
    updateChrome();
  }

  async function loadFiles() {
    const data = await request('files');
    state.files = data.files || [];
    fileSelect.replaceChildren();
    state.files.forEach((file) => {
      const option = document.createElement('option');
      option.value = file.path;
      option.textContent = file.path;
      fileSelect.append(option);
    });
    if (!state.files.length) {
      showBanner('No HTML files were found in this site.');
      saveButton.disabled = true;
      status.textContent = 'No HTML files';
      return;
    }
    const wanted = state.files.some((file) => file.path === initialFile)
      ? initialFile
      : state.files[0].path;
    state.file = wanted;
    fileSelect.value = wanted;
    await loadFile(wanted, true);
  }

  async function save() {
    if (state.saving) return;
    if (state.mode === 'code') {
      state.source = code.value;
      state.dirty = state.source !== state.saved;
    } else {
      commitAll();
    }
    if (!state.dirty) return;

    state.saving = true;
    updateChrome();
    showBanner('');
    try {
      const data = await request('save', {
        method: 'POST',
        body: {
          file: state.file,
          content: state.source,
          base_sha256: state.sha,
        },
      });
      state.saved = state.source;
      state.sha = data.sha256;
      state.dirty = false;
      resetHistory(state.source);
      showBanner('');
      if (embed && window.parent !== window) {
        window.parent.postMessage({ type: 'plak-editor-saved' }, '*');
      }
    } catch (error) {
      showBanner(error.message, error.code === 'conflict');
    } finally {
      state.saving = false;
      updateChrome();
    }
  }

  fileSelect.addEventListener('change', () => {
    const next = fileSelect.value;
    if (next === state.file) return;
    if (state.dirty && !confirm('Discard your unsaved changes?')) {
      fileSelect.value = state.file;
      return;
    }
    loadFile(next, true).catch((error) => showBanner(error.message));
  });

  codeToggle.addEventListener('click', () => {
    if (state.mode === 'preview') {
      commitAll();
      flushHistory();
      state.mode = 'code';
      code.value = state.source;
      preview.hidden = true;
      code.hidden = false;
      codeToggle.textContent = 'Preview';
      code.focus();
    } else {
      state.source = code.value;
      state.dirty = state.source !== state.saved;
      flushHistory();
      renderPreview();
      updateChrome();
    }
  });

  code.addEventListener('input', () => {
    state.source = code.value;
    state.dirty = state.source !== state.saved;
    scheduleHistory();
    updateChrome();
  });
  code.addEventListener('blur', flushHistory);

  saveButton.addEventListener('click', () => save().catch((error) => showBanner(error.message)));
  undoButton.addEventListener('click', undo);
  redoButton.addEventListener('click', redo);

  document.querySelectorAll('[data-modal-close]').forEach((button) => {
    button.addEventListener('click', () => {
      if (button.dataset.modalClose === 'image') closeImageModal();
      else closeLinkModal();
    });
  });
  imageUrl.addEventListener('input', updateImagePreview);
  imageUpload.addEventListener('click', () => imageFile.click());
  imageFile.addEventListener('change', () => {
    const file = imageFile.files?.[0];
    if (file) uploadImage(file);
  });
  document.getElementById('image-apply').addEventListener('click', applyImage);
  document.getElementById('link-apply').addEventListener('click', applyLink);

  function requestClose() {
    if (!embed || window.parent === window) return;
    if (state.dirty && !confirm('Discard your unsaved changes?')) return;
    window.parent.postMessage({ type: 'plak-editor-close' }, '*');
  }

  closeButton.addEventListener('click', requestClose);
  // Focus lives inside this iframe while editing, so the parent cannot hear
  // Escape; close from here instead.
  window.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    event.preventDefault();
    if (!imageModal.hidden) {
      closeImageModal();
      return;
    }
    if (!linkModal.hidden) {
      closeLinkModal();
      return;
    }
    requestClose();
  });

  window.addEventListener('keydown', (event) => {
    const mod = event.metaKey || event.ctrlKey;
    if (!mod) return;
    const key = event.key.toLowerCase();
    if (key === 's') {
      event.preventDefault();
      save().catch((error) => showBanner(error.message));
      return;
    }
    const target = event.target;
    if (target instanceof Element && target.closest('input, textarea, select')) return;
    if (key === 'z') {
      event.preventDefault();
      if (event.shiftKey) redo();
      else undo();
    } else if (key === 'y') {
      event.preventDefault();
      redo();
    }
  });

  window.addEventListener('beforeunload', (event) => {
    if (!state.dirty) return;
    event.preventDefault();
    event.returnValue = '';
  });

  loadFiles().catch((error) => {
    status.textContent = 'Could not load';
    showBanner(error.message);
  });
})();
