// greppit start-up: the <math-text> KaTeX element, then Elm with its
// flags and ports. Kept out of index.html so the Content-Security-Policy
// there can forbid inline scripts.

// KaTeX <math-text> custom element. The Scripta compiler sets the
// `content` and `display` DOM *properties*; the XMarkdown compiler sets
// `data-content` / `data-display` *attributes*. This element accepts
// both, and recovers properties that Elm set before the element was
// upgraded.
//
// KaTeX's "trusted" commands are limited to links to ordinary web
// addresses: no javascript: links, \htmlStyle, \htmlData or
// \includegraphics. Its output goes in with innerHTML, outside Elm's
// protection, so anything trusted here runs in greppit's page.
function katexTrust(ctx) {
    return (ctx.command === '\\href' || ctx.command === '\\url')
        && ['http', 'https', 'mailto'].indexOf(ctx.protocol) >= 0;
}

function initKatex() {
    class MathText extends HTMLElement {
        static get observedAttributes() { return ['data-content', 'data-display']; }
        constructor() {
            super();
            this.attachShadow({ mode: "open" });
            this._content = '';
            this._display = false;
        }
        connectedCallback() {
            this._upgradeProperty('content');
            this._upgradeProperty('display');
            this._readAttributes();
            this._render();
        }
        attributeChangedCallback() {
            this._readAttributes();
            if (this.isConnected) this._render();
        }
        _readAttributes() {
            if (this.hasAttribute('data-content')) this._content = this.getAttribute('data-content');
            if (this.hasAttribute('data-display')) this._display = this.getAttribute('data-display') === 'true';
        }
        _upgradeProperty(prop) {
            if (this.hasOwnProperty(prop)) {
                let value = this[prop];
                delete this[prop];
                this[prop] = value;
            }
        }
        set content(val) { this._content = val; if (this.isConnected) this._render(); }
        get content() { return this._content; }
        set display(val) { this._display = val; if (this.isConnected) this._render(); }
        get display() { return this._display; }
        _render() {
            if (!this._content) return;
            try {
                this.shadowRoot.innerHTML = katex.renderToString(this._content, {
                    throwOnError: false,
                    displayMode: this._display,
                    trust: katexTrust
                });
            } catch (e) {
                // textContent, not innerHTML: the message can quote the source.
                let err = document.createElement('span');
                err.style.color = 'red';
                err.textContent = e && e.message ? e.message : 'KaTeX error';
                this.shadowRoot.replaceChildren(err);
            }
            let link = document.createElement('link');
            link.setAttribute('rel', 'stylesheet');
            link.setAttribute('href', 'https://cdn.jsdelivr.net/npm/katex@0.16.47/dist/katex.min.css');
            link.setAttribute('integrity', 'sha384-nH0MfJ44wi1dd7w6jinlyBgljjS8EJAh2JBoRad8a3VDw2K69vfaaqm4WnR+gXtA');
            link.setAttribute('crossorigin', 'anonymous');
            this.shadowRoot.appendChild(link);
        }
    }
    customElements.define('math-text', MathText);
}

function loadMhchem() {
    var mhchem = document.createElement('script');
    mhchem.type = 'text/javascript';
    mhchem.integrity = 'sha384-fB8BH//9nBzROkMUsu/Dr35jWHIbnKesUo9rW0hfEgw8mZGnkAyBAjKX9F98OVuo';
    mhchem.crossOrigin = 'anonymous';
    mhchem.src = "https://cdn.jsdelivr.net/npm/katex@0.16.47/dist/contrib/mhchem.min.js";
    document.head.appendChild(mhchem);
}

var katexJs = document.createElement('script');
katexJs.type = 'text/javascript';
katexJs.onload = function() { initKatex(); loadMhchem(); };
katexJs.onerror = function(e) { console.error("KaTeX failed to load", e); };
katexJs.integrity = 'sha384-CwjPRVHTvLiMBFjEoij+QZViMV5rhTOIp7CJzl24JEqpRDA1sJFHVXXLURktbYYp';
katexJs.crossOrigin = 'anonymous';
katexJs.src = "https://cdn.jsdelivr.net/npm/katex@0.16.47/dist/katex.min.js";
document.head.appendChild(katexJs);

// Flags for Elm
var apiBase = (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
    ? 'http://localhost:8085'
    : window.location.origin;

var token = localStorage.getItem('greppit-token');
var language = localStorage.getItem('greppit-language');

var app = Elm.Main.init({
    node: document.getElementById('app'),
    flags: {
        apiBase: apiBase,
        initialToken: token,
        initialLanguage: language
    }
});

app.ports.saveToken.subscribe(function(t) {
    localStorage.setItem('greppit-token', t);
});
app.ports.saveLanguage.subscribe(function(lang) {
    localStorage.setItem('greppit-language', lang);
});
app.ports.removeToken.subscribe(function() {
    localStorage.removeItem('greppit-token');
});
app.ports.scrollToElement.subscribe(function (id) {
    requestAnimationFrame(function () {
        var el = document.getElementById(id);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
});

// Resizable columns. Elm draws a .resizer handle between two columns
// (Main.resizer, Editor.view). Dragging it sets a CSS variable on <html>
// that the column's width reads, so Elm's re-renders never undo it; the
// width is remembered in localStorage. Double-click resets it. `side`
// says which neighbour of the handle the variable sizes.
var RESIZERS = {
    left:   { prop: '--col-left-w',        side: 'prev', min: 180 },
    toc:    { prop: '--col-toc-w',         side: 'next', min: 120 },
    editor: { prop: '--editor-source-pct', side: 'prev', min: 200, percent: true }
};
var MIN_OTHER = 200;  // the column on the far side of the handle keeps this much

function widthKey(name) { return 'greppit-width-' + name; }

Object.keys(RESIZERS).forEach(function (name) {
    try {
        var w = localStorage.getItem(widthKey(name));
        if (w) document.documentElement.style.setProperty(RESIZERS[name].prop, w);
    } catch (e) {}
});

document.addEventListener('pointerdown', function (e) {
    var handle = e.target.closest && e.target.closest('.resizer');
    var r = handle && RESIZERS[handle.dataset.resize];
    if (!r || e.button !== 0) return;
    var col = r.side === 'prev' ? handle.previousElementSibling : handle.nextElementSibling;
    var other = r.side === 'prev' ? handle.nextElementSibling : handle.previousElementSibling;
    if (!col || !other) return;
    e.preventDefault();

    var parentWidth = handle.parentElement.getBoundingClientRect().width;
    var startX = e.clientX;
    var startWidth = col.getBoundingClientRect().width;
    var max = startWidth + other.getBoundingClientRect().width - MIN_OTHER;
    var value = null;

    function move(ev) {
        var dx = ev.clientX - startX;
        var w = startWidth + (r.side === 'prev' ? dx : -dx);
        w = Math.max(r.min, Math.min(max, w));
        value = r.percent ? (100 * w / parentWidth).toFixed(2) + '%' : Math.round(w) + 'px';
        document.documentElement.style.setProperty(r.prop, value);
    }
    function up() {
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', up);
        handle.removeEventListener('pointercancel', up);
        handle.classList.remove('active');
        document.body.classList.remove('resizing');
        if (value) try { localStorage.setItem(widthKey(handle.dataset.resize), value); } catch (e) {}
    }
    handle.setPointerCapture(e.pointerId);
    handle.classList.add('active');
    document.body.classList.add('resizing');
    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', up);
    handle.addEventListener('pointercancel', up);
});

document.addEventListener('dblclick', function (e) {
    var handle = e.target.closest && e.target.closest('.resizer');
    var r = handle && RESIZERS[handle.dataset.resize];
    if (!r) return;
    document.documentElement.style.removeProperty(r.prop);
    try { localStorage.removeItem(widthKey(handle.dataset.resize)); } catch (e) {}
});
