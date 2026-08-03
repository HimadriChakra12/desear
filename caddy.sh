#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS="desear.him.com"

command -v caddy &>/dev/null || sudo pacman -S --noconfirm caddy

grep -q "desear.him.com" /etc/hosts || \
    echo "127.0.0.1 $HOSTS" | sudo tee -a /etc/hosts >/dev/null

sudo mkdir -p /etc/caddy/sites
sudo cp "$DIR/Caddyfile" /etc/caddy/sites/desear.caddy
grep -q "sites/\*.caddy" /etc/caddy/Caddyfile 2>/dev/null || \
    echo "import /etc/caddy/sites/*.caddy" | sudo tee /etc/caddy/Caddyfile >/dev/null

sudo caddy validate --config /etc/caddy/Caddyfile
systemctl is-active --quiet caddy \
    && sudo caddy reload --config /etc/caddy/Caddyfile \
    || sudo systemctl enable --now caddy
sudo caddy trust

sudo systemctl status caddy --no-pager
