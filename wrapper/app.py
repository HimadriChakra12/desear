"""
Tiny gateway in front of SearXNG.

Each "category" (study, physics, math, cpp, ...) has its own YAML file
in /config/categories/*.yml describing:
  - which searxng engines/categories to use
  - which sites to softly prefer (boosted via OR site: groups)
  - which domains to hard-blacklist from the results

Usage:
  GET /categories                  -> list available categories
  GET /search/<category>?q=...     -> run a filtered search
  GET /health                      -> liveness check
"""

import os
import glob
import json
import time
import fnmatch
from datetime import datetime, timezone

import requests
import yaml
from flask import Flask, request, jsonify

SEARXNG_URL = os.environ.get("SEARXNG_URL", "http://searxng:8080")
CATEGORIES_DIR = os.environ.get("CATEGORIES_DIR", "/config/categories")
DATA_DIR = os.environ.get("DATA_DIR", "/data")

os.makedirs(DATA_DIR, exist_ok=True)
LOG_PATH = os.path.join(DATA_DIR, "query_log.jsonl")

app = Flask(__name__)

_cache = {"mtime": {}, "configs": {}}


def load_categories():
    """(Re)load category YAML files, only re-parsing files that changed."""
    for path in glob.glob(os.path.join(CATEGORIES_DIR, "*.yml")):
        mtime = os.path.getmtime(path)
        if _cache["mtime"].get(path) == mtime:
            continue
        with open(path, "r") as f:
            cfg = yaml.safe_load(f)
        key = cfg.get("name") or os.path.splitext(os.path.basename(path))[0]
        _cache["configs"][key] = cfg
        _cache["mtime"][path] = mtime
    return _cache["configs"]


def host_matches(host, pattern):
    host = (host or "").lower()
    pattern = pattern.lower()
    if pattern.startswith("*."):
        suffix = pattern[1:]  # ".example.com"
        return host.endswith(suffix) or host == pattern[2:]
    return host == pattern or fnmatch.fnmatch(host, pattern)


def is_blacklisted(url, blacklist):
    from urllib.parse import urlparse
    try:
        host = urlparse(url).netloc
    except Exception:
        return False
    return any(host_matches(host, pat) for pat in blacklist)


def build_query(base_query, prefer_sites):
    if not prefer_sites:
        return base_query
    # Soft-bias toward preferred sites using an OR group of site: filters.
    # This nudges ranking without excluding everything else.
    or_group = " OR ".join(f"site:{s}" for s in prefer_sites)
    return f"{base_query} ({or_group})"


def log_query(category, q, kept, dropped):
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "category": category,
        "query": q,
        "results_kept": kept,
        "results_dropped": dropped,
    }
    try:
        with open(LOG_PATH, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/categories")
def categories():
    cfgs = load_categories()
    return jsonify({
        name: {
            "description": c.get("description", ""),
            "engines": c.get("engines", []),
            "searx_categories": c.get("searx_categories", []),
            "blacklist_count": len(c.get("blacklist", [])),
        }
        for name, c in cfgs.items()
    })


@app.route("/search/<category>")
def search(category):
    q = request.args.get("q", "").strip()
    if not q:
        return jsonify({"error": "missing ?q="}), 400

    cfgs = load_categories()
    cfg = cfgs.get(category)
    if not cfg:
        return jsonify({
            "error": f"unknown category '{category}'",
            "available": list(cfgs.keys()),
        }), 404

    engines = cfg.get("engines") or []
    searx_categories = cfg.get("searx_categories") or []
    prefer_sites = cfg.get("prefer_sites") or cfg.get("boost_sites") or []
    blacklist = cfg.get("blacklist") or []

    full_query = build_query(q, prefer_sites)

    params = {
        "q": full_query,
        "format": "json",
    }
    if engines:
        params["engines"] = ",".join(engines)
    if searx_categories:
        params["categories"] = ",".join(searx_categories)

    try:
        r = requests.get(f"{SEARXNG_URL}/search", params=params, timeout=20)
        r.raise_for_status()
        raw = r.json()
    except requests.RequestException as e:
        return jsonify({"error": f"searxng request failed: {e}"}), 502

    results = raw.get("results", [])
    kept, dropped = [], 0
    for item in results:
        url = item.get("url", "")
        if is_blacklisted(url, blacklist):
            dropped += 1
            continue
        kept.append({
            "title": item.get("title"),
            "url": url,
            "content": item.get("content"),
            "engine": item.get("engine"),
        })

    log_query(category, q, len(kept), dropped)

    return jsonify({
        "category": category,
        "query": q,
        "effective_query": full_query,
        "result_count": len(kept),
        "dropped_blacklisted": dropped,
        "results": kept,
    })


if __name__ == "__main__":
    load_categories()
    app.run(host="0.0.0.0", port=9090)
