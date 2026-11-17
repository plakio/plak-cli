/* Plak local i18n runtime.
 *
 * The dictionary is injected before this file as `window.PLAK_I18N`.
 * Locale preference lives in localStorage and in the `plak_lang` cookie
 * (domain-wide so db.plak.localhost can follow it). The URL never changes.
 */
(function () {
  'use strict';

  var DICT = window.PLAK_I18N || {};
  var SUPPORTED = ['en', 'es', 'pt', 'fr'];
  var NAMES = { en: 'English', es: 'Español', pt: 'Português', fr: 'Français' };
  var STORAGE_KEY = 'plak-lang';
  var COOKIE = 'plak_lang';
  var ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];
  var current = detect();
  var originalTitle = typeof document !== 'undefined' ? document.title : '';
  var observer = null;
  var started = false;

  function normalize(value) {
    var code = String(value || '').toLowerCase().split('-')[0];
    return SUPPORTED.indexOf(code) === -1 ? null : code;
  }

  function readCookie(name) {
    var parts = String(document.cookie || '').split(';');
    var found = null;
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i].replace(/^\s+/, '');
      if (part.indexOf(name + '=') === 0) {
        found = decodeURIComponent(part.slice(name.length + 1));
      }
    }
    return found;
  }

  function writeCookie(name, value) {
    var maxAge = 60 * 60 * 24 * 365;
    var base = '; path=/; max-age=' + maxAge + '; SameSite=Lax';
    try {
      document.cookie = name + '=' + encodeURIComponent(value) + base;
      document.cookie = name + '=' + encodeURIComponent(value) + base + '; Domain=.plak.localhost';
      document.cookie = 'adminer_lang=' + encodeURIComponent(value) + base + '; Domain=.plak.localhost';
    } catch (error) {}
  }

  function detect() {
    try {
      var stored = normalize(localStorage.getItem(STORAGE_KEY));
      if (stored) return stored;
    } catch (error) {}
    var cookie = normalize(readCookie(COOKIE));
    if (cookie) return cookie;
    var candidates = navigator.languages || [navigator.language];
    for (var i = 0; i < candidates.length; i++) {
      var candidate = normalize(candidates[i]);
      if (candidate) return candidate;
    }
    return 'en';
  }

  function map(locale) {
    return DICT[locale] || {};
  }

  function interpolate(value, replace) {
    if (!replace) return value;
    Object.keys(replace).forEach(function (key) {
      value = value.split(':' + key).join(String(replace[key]));
    });
    return value;
  }

  function exact(value) {
    var translated = map(current)[value];
    return typeof translated === 'string' ? translated : null;
  }

  function countForm(singular, plural, count) {
    return count === 1 ? singular : plural;
  }

  function patterns(value) {
    var m;
    if (current === 'en') return null;

    // Relative times keep the compact dashboard format.
    if (value === 'now') return { es: 'ahora', pt: 'agora', fr: 'maintenant' }[current];
    if ((m = /^(\d+)m$/.exec(value))) return m[1] + ' min';
    if ((m = /^(\d+)h$/.exec(value))) return m[1] + ' h';
    if ((m = /^(\d+)d$/.exec(value))) return m[1] + ' d';
    if ((m = /^(\d+)mo$/.exec(value))) {
      return m[1] + ({ es: ' mes', pt: ' mês', fr: ' mois' }[current]);
    }
    if ((m = /^(\d+)y$/.exec(value))) {
      return m[1] + ({ es: ' a', pt: ' a', fr: ' an' }[current]);
    }

    // Counts and plurals.
    if ((m = /^(\d+) HTML files?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'archivo HTML', pt: 'arquivo HTML', fr: 'fichier HTML' }[current], { es: 'archivos HTML', pt: 'arquivos HTML', fr: 'fichiers HTML' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) files?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'archivo', pt: 'arquivo', fr: 'fichier' }[current], { es: 'archivos', pt: 'arquivos', fr: 'fichiers' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) sites?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'sitio', pt: 'site', fr: 'site' }[current], { es: 'sitios', pt: 'sites', fr: 'sites' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) of (\d+) sites?$/.exec(value))) {
      return m[1] + ' ' + ({ es: 'de', pt: 'de', fr: 'sur' }[current]) + ' ' + m[2] + ' ' + countForm({ es: 'sitio', pt: 'site', fr: 'site' }[current], { es: 'sitios', pt: 'sites', fr: 'sites' }[current], Number(m[2]));
    }
    if ((m = /^(\d+) entries?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'entrada', pt: 'entrada', fr: 'entrée' }[current], { es: 'entradas', pt: 'entradas', fr: 'entrées' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) requests?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'solicitud', pt: 'solicitação', fr: 'requête' }[current], { es: 'solicitudes', pt: 'solicitações', fr: 'requêtes' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) users?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'usuario', pt: 'usuário', fr: 'utilisateur' }[current], { es: 'usuarios', pt: 'usuários', fr: 'utilisateurs' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) plugins?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'complemento', pt: 'plug-in', fr: 'plugin' }[current], { es: 'complementos', pt: 'plug-ins', fr: 'plugins' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) themes?$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'tema', pt: 'tema', fr: 'thème' }[current], { es: 'temas', pt: 'temas', fr: 'thèmes' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) installed$/.exec(value))) {
      return m[1] + ' ' + countForm({ es: 'instalado', pt: 'instalado', fr: 'installé' }[current], { es: 'instalados', pt: 'instalados', fr: 'installés' }[current], Number(m[1]));
    }
    if ((m = /^(\d+) of 3 running$/.exec(value))) {
      return m[1] + ' ' + ({ es: 'de 3 en ejecución', pt: 'de 3 em execução', fr: 'sur 3 en cours' }[current]);
    }

    // Dynamic messages from the dashboard and the API.
    if ((m = /^(.+) finished\.$/.exec(value))) {
      return translateText(m[1]) + ({ es: ' finalizado.', pt: ' concluído.', fr: ' terminé.' }[current]);
    }
    if ((m = /^(.+) failed — check the log and retry from the CLI if needed\.$/.exec(value))) {
      return translateText(m[1]) + ({ es: ' falló — revisa el registro y reintenta desde la CLI si es necesario.', pt: ' falhou — verifique o log e tente novamente pela CLI se necessário.', fr: ' a échoué — consultez le journal et réessayez depuis la CLI si nécessaire.' }[current]);
    }
    if ((m = /^Snapshot of (.+)$/.exec(value))) {
      return { es: 'Copia de ', pt: 'Backup de ', fr: 'Sauvegarde de ' }[current] + m[1];
    }
    if ((m = /^Restore (.+)$/.exec(value))) {
      return { es: 'Restaurar ', pt: 'Restaurar ', fr: 'Restaurer ' }[current] + m[1];
    }
    if ((m = /^Import (.+)$/.exec(value))) {
      return { es: 'Importar ', pt: 'Importar ', fr: 'Importer ' }[current] + m[1];
    }
    if ((m = /^(.+) is stopped\. Run plak enable\.$/.exec(value))) {
      return m[1] + ({ es: ' está detenido. Ejecuta plak enable.', pt: ' está parado. Execute plak enable.', fr: ' est arrêté. Exécutez plak enable.' }[current]);
    }
    if ((m = /^(.+) deleted\.$/.exec(value))) return m[1] + ({ es: ' eliminado.', pt: ' excluído.', fr: ' supprimé.' }[current]);
    if ((m = /^(.+) created\.$/.exec(value))) return m[1] + ({ es: ' creado.', pt: ' criado.', fr: ' créé.' }[current]);
    if ((m = /^(.+) copied\.$/.exec(value))) return m[1] + ({ es: ' copiado.', pt: ' copiado.', fr: ' copié.' }[current]);
    if ((m = /^wp-cli failed \((\d+)\)\.$/.exec(value))) {
      return ({ es: 'wp-cli falló (', pt: 'wp-cli falhou (', fr: 'wp-cli a échoué (' }[current]) + m[1] + ').';
    }
    if (value === 'wp-cli returned nothing.') {
      return { es: 'wp-cli no devolvió nada.', pt: 'wp-cli não retornou nada.', fr: 'wp-cli n’a rien renvoyé.' }[current];
    }
    if (value === 'Site name not provided for deletion.') {
      return { es: 'No se proporcionó el nombre del sitio para eliminar.', pt: 'O nome do site não foi fornecido para exclusão.', fr: 'Nom du site non fourni pour la suppression.' }[current];
    }
    if (value === 'Invalid site name provided.') {
      return { es: 'El nombre del sitio no es válido.', pt: 'O nome do site fornecido é inválido.', fr: 'Le nom du site fourni est invalide.' }[current];
    }
    if ((m = /^Upload failed \(code (\d+)\)\.$/.exec(value))) {
      return { es: 'La subida falló (código ' + m[1] + ').', pt: 'O upload falhou (código ' + m[1] + ').', fr: 'Le téléversement a échoué (code ' + m[1] + ').' }[current];
    }
    if ((m = /^Could not create site: (.+)$/.exec(value))) {
      return { es: 'No se pudo crear el sitio: ' + m[1], pt: 'Não foi possível criar o site: ' + m[1], fr: 'Impossible de créer le site : ' + m[1] }[current];
    }
    if ((m = /^Edit (.+) · Plak local$/.exec(value))) {
      return { es: 'Editar ', pt: 'Editar ', fr: 'Modifier ' }[current] + m[1] + ' · Plak local';
    }
    if ((m = /^Delete (.+)\? This removes its files and database\.$/.exec(value))) {
      return { es: '¿Eliminar ' + m[1] + '? Esto borra sus archivos y su base de datos.', pt: 'Excluir ' + m[1] + '? Isso remove os arquivos e o banco de dados.', fr: 'Supprimer ' + m[1] + ' ? Cela supprime ses fichiers et sa base de données.' }[current];
    }
    return null;
  }

  function translateText(value) {
    if (typeof value !== 'string' || !value) return value;
    var trimmed = value.trim();
    if (!trimmed) return value;
    var translated = exact(trimmed);
    if (translated === null) translated = patterns(trimmed);
    if (translated === null || translated === trimmed) return value;
    var start = value.indexOf(trimmed);
    if (start === -1) return value;
    return value.slice(0, start) + translated + value.slice(start + trimmed.length);
  }

  function translateAttr(value) {
    if (typeof value !== 'string' || !value) return value;
    var trimmed = value.trim();
    if (!trimmed) return value;
    var translated = exact(trimmed);
    if (translated === null) translated = patterns(trimmed);
    return translated === null ? value : translated;
  }

  function ignored(element) {
    if (!element || element.nodeType !== 1) return false;
    var tag = element.tagName;
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'CODE' || tag === 'PRE' ||
        tag === 'TEXTAREA' || tag === 'IFRAME' || tag === 'SVG' || tag === 'OBJECT') {
      return true;
    }
    if (element.isContentEditable) return true;
    if (element.hasAttribute && element.hasAttribute('data-i18n-ignore')) return true;
    if (element.matches && element.matches('.site-name, .host-accent, .site-domain, .site-path, .editor-preview-hero, .editor-card-title, .console-out, .mail-html, .mail-from, .mail-subject, .mail-snippet, .comp-title, .comp-slug, .wp-cli-output, #file-select')) {
      return true;
    }
    return false;
  }

  function inIgnored(node) {
    var element = node.nodeType === 1 ? node : node.parentElement;
    while (element) {
      if (ignored(element)) return true;
      element = element.parentElement;
    }
    return false;
  }

  function translateTextNode(node, force) {
    var value = node.nodeValue;
    if (!force && node.__plakRendered === value) return;
    // Alpine can replace a translated node with a new English source. If the
    // current value is neither the source nor our last render, adopt it.
    if (node.__plakSource === undefined ||
        (node.__plakRendered !== undefined && value !== node.__plakRendered)) {
      node.__plakSource = value;
    }
    var source = node.__plakSource;
    var next = translateText(source);
    node.__plakRendered = next;
    if (value !== next) node.nodeValue = next;
  }

  function translateAttrNode(element, attr, force) {
    if (!element.hasAttribute(attr)) return;
    var value = element.getAttribute(attr);
    if (!element.__plakAttrs) element.__plakAttrs = {};
    if (!element.__plakAttrRendered) element.__plakAttrRendered = {};
    var rendered = element.__plakAttrRendered[attr];
    if (!force && rendered === value) return;
    if (element.__plakAttrs[attr] === undefined ||
        (rendered !== undefined && value !== rendered)) {
      element.__plakAttrs[attr] = value;
    }
    var source = element.__plakAttrs[attr];
    var next = translateAttr(source);
    element.__plakAttrRendered[attr] = next;
    if (value !== next) element.setAttribute(attr, next);
  }

  function translateNode(node, force) {
    if (!node || inIgnored(node)) return;
    if (node.nodeType === 3) {
      translateTextNode(node, force);
      return;
    }
    if (node.nodeType === 11) {
      for (var fragmentChild = node.firstChild; fragmentChild; fragmentChild = fragmentChild.nextSibling) {
        translateNode(fragmentChild, force);
      }
      return;
    }
    if (node.nodeType !== 1) return;
    for (var i = 0; i < ATTRS.length; i++) {
      translateAttrNode(node, ATTRS[i], force);
    }
    for (var child = node.firstChild; child; child = child.nextSibling) {
      translateNode(child, force);
    }
  }

  function apply(root, force) {
    var target = root || document.body;
    if (!target) return;
    translateNode(target, !!force);
    if (started) updateSwitcher();
    if (originalTitle) {
      var title = exact(originalTitle);
      if (title === null) title = patterns(originalTitle);
      if (title === null) title = originalTitle;
      if (document.title !== title) document.title = title;
    }
  }

  function updateSwitcher() {
    var codes = document.querySelectorAll('[data-lang-code]');
    for (var i = 0; i < codes.length; i++) codes[i].textContent = current.toUpperCase();
    var options = document.querySelectorAll('[data-lang-option]');
    for (var j = 0; j < options.length; j++) {
      var active = options[j].getAttribute('data-lang-option') === current;
      options[j].classList.toggle('active', active);
      options[j].setAttribute('aria-selected', active ? 'true' : 'false');
      var check = options[j].querySelector('.lang-check');
      if (check) check.style.visibility = active ? 'visible' : 'hidden';
    }
    var selects = document.querySelectorAll('[data-lang-select]');
    for (var k = 0; k < selects.length; k++) selects[k].value = current;
  }

  function setLocale(next) {
    var normalized = normalize(next);
    if (!normalized) return current;
    current = normalized;
    try { localStorage.setItem(STORAGE_KEY, current); } catch (error) {}
    writeCookie(COOKIE, current);
    document.documentElement.lang = current;
    document.documentElement.removeAttribute('data-i18n-pending');
    apply(document.body, true);
    try {
      window.dispatchEvent(new CustomEvent('plak:locale', { detail: { locale: current } }));
    } catch (error) {}
    return current;
  }

  function t(key, replace) {
    var translated = exact(key);
    if (translated === null) translated = patterns(key);
    if (translated === null) translated = key;
    return interpolate(translated, replace);
  }

  function tc(key, count) {
    var translated = t(key);
    var parts = translated.split('|');
    return interpolate(count === 1 ? parts[0] : (parts[1] || parts[0]), { count: count });
  }

  function bindSwitchers() {
    var toggles = document.querySelectorAll('[data-lang-toggle]');
    for (var i = 0; i < toggles.length; i++) {
      if (toggles[i].__plakBound) continue;
      toggles[i].__plakBound = true;
      toggles[i].addEventListener('click', function (event) {
        event.stopPropagation();
        var wrap = this.closest('[data-lang-wrap]') || this.parentElement;
        var menu = wrap && wrap.querySelector('[data-lang-menu]');
        if (!menu) return;
        var opening = menu.hidden;
        menu.hidden = !opening;
        this.setAttribute('aria-expanded', opening ? 'true' : 'false');
      });
    }
    var options = document.querySelectorAll('[data-lang-option]');
    for (var j = 0; j < options.length; j++) {
      if (options[j].__plakBound) continue;
      options[j].__plakBound = true;
      options[j].addEventListener('click', function () {
        setLocale(this.getAttribute('data-lang-option'));
        var wrap = this.closest('[data-lang-wrap]');
        var toggle = wrap && wrap.querySelector('[data-lang-toggle]');
        var menu = wrap && wrap.querySelector('[data-lang-menu]');
        if (menu) menu.hidden = true;
        if (toggle) toggle.setAttribute('aria-expanded', 'false');
      });
    }
    var selects = document.querySelectorAll('[data-lang-select]');
    for (var k = 0; k < selects.length; k++) {
      if (selects[k].__plakBound) continue;
      selects[k].__plakBound = true;
      selects[k].addEventListener('change', function () {
        setLocale(this.value);
      });
    }
    if (!document.__plakLangOutside) {
      document.__plakLangOutside = true;
      document.addEventListener('click', function (event) {
        var wraps = document.querySelectorAll('[data-lang-wrap]');
        for (var i = 0; i < wraps.length; i++) {
          if (wraps[i].contains(event.target)) continue;
          var menu = wraps[i].querySelector('[data-lang-menu]');
          var toggle = wraps[i].querySelector('[data-lang-toggle]');
          if (menu) menu.hidden = true;
          if (toggle) toggle.setAttribute('aria-expanded', 'false');
        }
      });
      document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        var menus = document.querySelectorAll('[data-lang-menu]');
        for (var i = 0; i < menus.length; i++) menus[i].hidden = true;
        var toggles = document.querySelectorAll('[data-lang-toggle]');
        for (var j = 0; j < toggles.length; j++) toggles[j].setAttribute('aria-expanded', 'false');
      });
    }
  }

  function startObserver() {
    if (observer || typeof MutationObserver === 'undefined') return;
    observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var mutation = mutations[i];
        if (mutation.type === 'characterData') {
          translateNode(mutation.target, false);
        } else if (mutation.type === 'childList') {
          for (var j = 0; j < mutation.addedNodes.length; j++) translateNode(mutation.addedNodes[j], false);
        } else if (mutation.type === 'attributes') {
          var attr = mutation.attributeName;
          if (ATTRS.indexOf(attr) === -1) continue;
          translateAttrNode(mutation.target, attr, false);
        }
      }
    });
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ATTRS
    });
  }

  function init() {
    if (started) return;
    started = true;
    document.documentElement.lang = current;
    apply(document.body, false);
    bindSwitchers();
    startObserver();
    document.documentElement.removeAttribute('data-i18n-pending');
  }

  // Hide the body until the first non-English pass is applied. English never
  // needs the pending state, so a missing i18n.js cannot hide the dashboard.
  if (current !== 'en') document.documentElement.setAttribute('data-i18n-pending', '');

  window.PlakI18n = {
    get locale() { return current; },
    supported: SUPPORTED,
    names: NAMES,
    normalize: normalize,
    detect: detect,
    t: t,
    tc: tc,
    translateText: translateText,
    translateAttr: translateAttr,
    setLocale: setLocale,
    apply: apply,
    refresh: function () { apply(document.body, false); bindSwitchers(); },
    init: init
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
  document.addEventListener('alpine:initialized', function () { apply(document.body); });
})();
