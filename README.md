# Personal multi-category search engine

A self-hosted, Docker Compose based search stack: one SearXNG metasearch
backend, fronted by a small wrapper API that applies **per-category
config** (engine selection, preferred sites, blacklists) — so you get
10 independently-tunable "search engines" (study, research-bd,
research-intl, physics, math, biology, chemistry, c-lua, cpp,
programming) without running 10 separate containers.

## Layout

```
.
├── docker-compose.yml
├── config/
│   ├── searxng/settings.yml       # base SearXNG config (secret key, engines on/off)
│   └── categories/*.yml           # one file per search "profile"
├── data/
│   ├── searxng/                   # searxng cache
│   ├── redis/                     # redis persistence (searxng ratelimit/cache)
│   └── wrapper/                   # query_log.jsonl (your own search history)
├── wrapper/                       # Flask gateway app + Dockerfile
└── backups/
    ├── backup.sh                  # tars up config/ + data/
    └── restore.sh                 # restores from a tarball
```

## First-time setup

```bash
make init      # copies settings.yml.example -> settings.yml with a fresh secret_key
make up        # builds + starts the stack (refuses to run without a real secret_key)
make health    # curl /health and /categories
```

`make init` won't overwrite an existing `config/searxng/settings.yml` -
delete it first if you want to regenerate the key.

### Secret key safety check

`make up` and `make restart` both run a `check-secret` step first: if
`config/searxng/settings.yml` is missing, or still contains the
`REPLACE_ME_WITH_RANDOM_SECRET` placeholder, the command **errors out
immediately** instead of starting the stack with an insecure key:

```
ERROR: config/searxng/settings.yml still has the placeholder secret_key.
  Run 'make init' (on a fresh checkout) or manually replace
  'REPLACE_ME_WITH_RANDOM_SECRET' with the output of: openssl rand -hex 32
```

This only applies when you go through `make` — if you run
`docker compose up -d` directly you bypass the check, so prefer `make
up`.

## Makefile reference

| Target | What it does |
|---|---|
| `make init` | generate `config/searxng/settings.yml` with a fresh secret |
| `make up` | check secret, build, start everything in the background |
| `make down` | stop everything |
| `make build` | rebuild just the wrapper image |
| `make restart` | check secret, restart all services |
| `make logs` | follow logs for all services |
| `make ps` | show container status |
| `make health` | hit `/health` and `/categories` on the wrapper |
| `make backup` | run `backups/backup.sh` |
| `make restore FILE=backups/backup-....tar.gz` | run `backups/restore.sh` |
| `make clean` | `docker compose down --remove-orphans` |

## Using it

```bash
curl "http://localhost:9090/search/cpp?q=how+to+use+std::variant"
curl "http://localhost:9090/search/research-bd?q=flood+forecasting+models"
curl "http://localhost:9090/search/physics?q=quantum+tunneling+intro"
```

Each response includes `result_count`, `dropped_blacklisted` (so you can
see the blacklist actually doing something), and the filtered `results`
array.

## Editing a category's blacklist / engines

Just edit the relevant file in `config/categories/`, e.g.
`config/categories/math.yml`, and save. The wrapper hot-reloads changed
category files automatically (checked on every request via mtime) — no
restart needed. If you edit `config/searxng/settings.yml` (base engine
list, secret key, etc.) you do need to restart the `searxng` container:

```bash
docker compose restart searxng
```

## Adding an 11th category

Copy any file in `config/categories/` to a new name, e.g.
`config/categories/electronics.yml`, edit `name:`, `engines:`,
`prefer_sites:`, `blacklist:` — it shows up automatically at
`/search/electronics` on the next request.

## Backups

Everything that matters (your configs + your query history + redis
cache) lives under `config/` and `data/`. To back it up:

```bash
./backups/backup.sh
```

This writes a timestamped `backups/backup-YYYYMMDD-HHMMSS.tar.gz` and
keeps the last 14. Copy that file wherever you actually want durable
storage (another disk, a remote host, etc.) — the script only creates
the local archive.

To restore:

```bash
./backups/restore.sh backups/backup-20260802-120000.tar.gz
```

This stops the stack, extracts the archive over `config/` and `data/`,
and leaves you to run `docker compose up -d` again.

### Cron example (nightly backup at 3am)

```
0 3 * * * cd /path/to/searxng-multi && ./backups/backup.sh >> backups/backup.log 2>&1
```

## Notes / things you'll likely want to tweak

- `prefer_sites` in each category YAML does a **soft bias** (appends an
  OR group of `site:` filters to the query) rather than a hard
  restriction — so you still get broader results, just nudged toward
  sources you trust. If you want hard restriction instead, change
  `build_query()` in `wrapper/app.py` to join with `AND` semantics or
  drop non-matching results entirely.
- `blacklist` supports exact hostnames and `*.example.com` wildcards.
- The wrapper has no auth since it's meant for local/LAN use. If you
  expose port 9090 beyond localhost, put it behind a reverse proxy
  with basic auth or a firewall rule.
- SearXNG itself isn't published to the host (`ports:` commented out in
  compose) — only the wrapper is. Uncomment if you want to hit SearXNG
  directly for debugging engine issues.
