// Kagi-esque vim-navigable frontend for the multi-category search wrapper.
// Talks to the wrapper API via /api/... (proxied same-origin by nginx).

const PREFERRED_ORDER = [
  "study", "research-bd", "research-intl", "physics", "math",
  "biology", "chemistry", "c-lua", "cpp", "programming",
];

const el = (sel) => document.querySelector(sel);
const qInput = el("#q");
const resultsEl = el("#results");
const tabsEl = el("#tabs");
const metaEl = el("#result-meta");
const emptyStateEl = el("#empty-state");
const helpOverlay = el("#help-overlay");

let categories = [];       // ordered list of {key, description}
let activeCategory = null;
let results = [];          // current result set
let selected = -1;         // selected result index
let lastKeyG = 0;           // for 'gg' detection

async function loadCategories() {
  const res = await fetch("/api/categories");
  const data = await res.json();
  const keys = Object.keys(data);
  const ordered = PREFERRED_ORDER.filter((k) => keys.includes(k))
    .concat(keys.filter((k) => !PREFERRED_ORDER.includes(k)).sort());
  categories = ordered.map((k) => ({ key: k, description: data[k].description }));
  activeCategory = categories[0]?.key || null;
  renderTabs();
}

function renderTabs() {
  tabsEl.innerHTML = "";
  categories.forEach((c, i) => {
    const div = document.createElement("div");
    div.className = "tab" + (c.key === activeCategory ? " active" : "");
    div.title = c.description || "";
    const shortcut = i === 9 ? "0" : String(i + 1);
    div.innerHTML = `<span class="idx">${shortcut}</span>${c.key}`;
    div.addEventListener("click", () => switchCategory(c.key));
    tabsEl.appendChild(div);
  });
}

function switchCategory(key) {
  activeCategory = key;
  renderTabs();
  if (qInput.value.trim()) runSearch();
}

function cycleCategory(delta) {
  const idx = categories.findIndex((c) => c.key === activeCategory);
  const next = (idx + delta + categories.length) % categories.length;
  switchCategory(categories[next].key);
}

function jumpCategoryByPosition(pos) {
  // pos: 1-9 -> index 0-8, 0 -> index 9
  const idx = pos === 0 ? 9 : pos - 1;
  if (categories[idx]) switchCategory(categories[idx].key);
}

async function runSearch() {
  const q = qInput.value.trim();
  if (!q || !activeCategory) return;
  metaEl.textContent = "searching...";
  resultsEl.innerHTML = '<div class="loading">searching...</div>';
  emptyStateEl.classList.add("hidden");
  selected = -1;

  try {
    const res = await fetch(`/api/search/${encodeURIComponent(activeCategory)}?q=${encodeURIComponent(q)}`);
    const data = await res.json();
    if (data.error) {
      resultsEl.innerHTML = `<div class="error">${escapeHtml(data.error)}</div>`;
      metaEl.textContent = "";
      return;
    }
    results = data.results || [];
    metaEl.textContent = `${data.result_count} results` +
      (data.dropped_blacklisted ? ` \u00b7 ${data.dropped_blacklisted} blacklisted hidden` : "");
    renderResults();
    if (results.length > 0) select(0);
  } catch (e) {
    resultsEl.innerHTML = `<div class="error">request failed: ${escapeHtml(String(e))}</div>`;
    metaEl.textContent = "";
  }
}

function renderResults() {
  if (results.length === 0) {
    resultsEl.innerHTML = '<div class="no-results">no results</div>';
    return;
  }
  resultsEl.innerHTML = "";
  results.forEach((r, i) => {
    const div = document.createElement("div");
    div.className = "result";
    div.dataset.index = i;
    const content = r.content || "";
    const isLong = content.length > 220;
    div.innerHTML = `
      <span class="idx">${i + 1}</span>
      <a class="title" href="${escapeAttr(r.url)}" target="_blank" rel="noopener">${escapeHtml(r.title || r.url)}</a>
      <span class="url">${escapeHtml(r.url)}</span>
      <p class="snippet">${escapeHtml(content)}</p>
      ${isLong ? '<button type="button" class="snippet-toggle">show more</button>' : ""}
      ${r.engine ? `<span class="engine">${escapeHtml(r.engine)}</span>` : ""}
    `;
    div.addEventListener("click", (e) => {
      if (e.target.classList.contains("snippet-toggle")) {
        const snippetEl = div.querySelector(".snippet");
        const expanded = snippetEl.classList.toggle("expanded");
        e.target.textContent = expanded ? "show less" : "show more";
        return;
      }
      if (e.target.tagName !== "A") openResult(i, false);
    });
    div.addEventListener("mouseenter", () => select(i, false));
    resultsEl.appendChild(div);
  });
}

function select(i, scroll = true) {
  if (i < 0 || i >= results.length) return;
  selected = i;
  document.querySelectorAll(".result").forEach((el2) => el2.classList.remove("selected"));
  const node = resultsEl.querySelector(`.result[data-index="${i}"]`);
  if (node) {
    node.classList.add("selected");
    if (scroll) node.scrollIntoView({ block: "center", behavior: "smooth" });
  }
}

function openResult(i, newTab) {
  const r = results[i];
  if (!r) return;
  if (newTab) {
    window.open(r.url, "_blank", "noopener");
  } else {
    window.location.href = r.url;
  }
}

function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}
function escapeAttr(s) { return escapeHtml(s); }

function toggleHelp(force) {
  const show = force !== undefined ? force : helpOverlay.classList.contains("hidden");
  helpOverlay.classList.toggle("hidden", !show);
}

// ---- keyboard handling ----

el("#search-form").addEventListener("submit", (e) => {
  e.preventDefault();
  runSearch();
  qInput.blur();
});

el("#help-btn").addEventListener("click", () => toggleHelp());
helpOverlay.addEventListener("click", (e) => {
  if (e.target === helpOverlay) toggleHelp(false);
});

document.addEventListener("keydown", (e) => {
  const inInput = document.activeElement === qInput;

  if (inInput) {
    if (e.key === "Escape") qInput.blur();
    return; // let the input handle everything else natively
  }

  if (!helpOverlay.classList.contains("hidden")) {
    if (e.key === "Escape" || e.key === "?") toggleHelp(false);
    return;
  }

  switch (e.key) {
    case "/":
      e.preventDefault();
      qInput.focus();
      break;
    case "?":
      toggleHelp(true);
      break;
    case "j":
    case "ArrowDown":
      e.preventDefault();
      select(Math.min(selected + 1, results.length - 1));
      break;
    case "k":
    case "ArrowUp":
      e.preventDefault();
      select(Math.max(selected - 1, 0));
      break;
    case "g": {
      const now = Date.now();
      if (now - lastKeyG < 500) {
        select(0);
        lastKeyG = 0;
      } else {
        lastKeyG = now;
      }
      break;
    }
    case "G":
      select(results.length - 1);
      break;
    case "Enter":
    case "o":
      if (selected >= 0) openResult(selected, e.shiftKey);
      break;
    case "O":
      if (selected >= 0) openResult(selected, true);
      break;
    case "[":
      cycleCategory(-1);
      break;
    case "]":
      cycleCategory(1);
      break;
    default:
      if (e.ctrlKey && /^[0-9]$/.test(e.key)) {
        e.preventDefault();
        jumpCategoryByPosition(parseInt(e.key, 10));
      } else if (/^[1-9]$/.test(e.key) && !e.ctrlKey) {
        const idx = parseInt(e.key, 10) - 1;
        if (idx < results.length) select(idx);
      }
  }
});

// ---- init ----
(async function init() {
  await loadCategories();
  emptyStateEl.classList.remove("hidden");
  qInput.focus();
})();
