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
  const closeButton = document.getElementById('close');
  const status = document.getElementById('status');
  const banner = document.getElementById('banner');

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

  if (closeButton) closeButton.hidden = !embed;

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

  const EDITABLE = new Set([
    'a', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'blockquote', 'figcaption', 'div', 'span',
    'td', 'th', 'dt', 'dd', 'caption', 'summary',
    'label', 'button', 'strong', 'em', 'small', 'time',
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
    const body = segments.map((segment) => {
      if (segment.type !== 'text') return segment.value;
      if (!segment.editable || !segment.value.trim()) return segment.value;
      const index = textIndex;
      textIndex += 1;
      return `<span data-plak-text-index="${index}" contenteditable="true" spellcheck="true">${segment.value}</span>`;
    }).join('');

    const head = `
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob: https: http:; media-src data: blob: https: http:; style-src 'unsafe-inline' https: http:; font-src data: https: http:; script-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'">
      <base href="${escapeAttr(baseHref())}">
      <style data-plak-editor-styles>
        [data-plak-text-index] { cursor: text; outline: 1px dashed transparent !important; outline-offset: 2px !important; }
        [data-plak-text-index]:hover { outline-color: rgba(47, 54, 250, .55) !important; background: rgba(47, 54, 250, .06) !important; }
        [data-plak-text-index]:focus { outline: 2px solid #2f36fa !important; background: rgba(47, 54, 250, .08) !important; }
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

    return documentHtml;
  }

  function replaceTextSegment(source, index, text) {
    const segments = tokenize(source);
    let textIndex = 0;
    for (const segment of segments) {
      if (segment.type !== 'text' || !segment.editable || !segment.value.trim()) continue;
      if (textIndex === index) {
        segment.value = escapeText(text);
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
    doc.addEventListener('blur', () => commitAll(), true);

    doc.querySelectorAll('[data-plak-text-index]').forEach((element) => {
      state.initial.set(element, element.textContent || '');
      element.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' && !event.shiftKey) {
          event.preventDefault();
          element.blur();
        }
      });
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
      if (original !== undefined && (element.textContent || '') !== original) {
        changed.push({ index, text: element.textContent || '' });
      }
    });
    if (!changed.length) return;

    changed.sort((left, right) => right.index - left.index);
    let next = state.source;
    changed.forEach(({ index, text }) => {
      next = replaceTextSegment(next, index, text);
    });

    if (next !== state.source) {
      state.source = next;
      state.dirty = state.source !== state.saved;
    }
    doc.querySelectorAll('[data-plak-text-index]').forEach((element) => {
      state.initial.set(element, element.textContent || '');
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
      state.mode = 'code';
      code.value = state.source;
      preview.hidden = true;
      code.hidden = false;
      codeToggle.textContent = 'Preview';
      code.focus();
    } else {
      state.source = code.value;
      state.dirty = state.source !== state.saved;
      renderPreview();
      updateChrome();
    }
  });

  code.addEventListener('input', () => {
    state.source = code.value;
    state.dirty = state.source !== state.saved;
    updateChrome();
  });

  saveButton.addEventListener('click', () => save().catch((error) => showBanner(error.message)));

  closeButton.addEventListener('click', () => {
    if (embed && window.parent !== window) {
      window.parent.postMessage({ type: 'plak-editor-close' }, '*');
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
