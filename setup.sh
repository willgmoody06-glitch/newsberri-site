#!/usr/bin/env bash
# NewsBerri marketing-site setup — news-trader-v1 droplet (Ubuntu 24.04)
# Run as root:  wget -qO- https://raw.githubusercontent.com/fortunatebusinessman-ops/newsberri-site/main/setup.sh | bash
# Safe to re-run (idempotent). Installs nginx, deploys the 4 public pages,
# serves newsberri.com + www. Does NOT touch anything else on the box.
set -euo pipefail

RAW="https://raw.githubusercontent.com/fortunatebusinessman-ops/newsberri-site/main"
DOCROOT="/var/www/newsberri.com"
PAGES=(index.html how-it-works.html pricing.html demo.html)

echo ">>> 1/5 checking web ports are free (or already ours)..."
if ss -tlnp | grep -E ':80 |:443 ' | grep -qv nginx; then
  echo "!!! something other than nginx is on port 80/443 — stopping, nothing changed."
  ss -tlnp | grep -E ':80 |:443 '
  exit 1
fi

echo ">>> 2/5 installing nginx (if missing)..."
if ! command -v nginx >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq nginx
fi

echo ">>> 3/5 downloading the site pages..."
mkdir -p "$DOCROOT"
for f in "${PAGES[@]}"; do
  curl -fsSL "$RAW/$f" -o "$DOCROOT/$f.tmp"
  # sanity: a real page, not an error blob
  grep -q "</html>" "$DOCROOT/$f.tmp" || { echo "!!! $f download looks wrong — stopping."; exit 1; }
  mv "$DOCROOT/$f.tmp" "$DOCROOT/$f"
  echo "    ok: $f"
done

echo ">>> 4/5 writing nginx config..."
cat > /etc/nginx/sites-available/newsberri.com <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name newsberri.com www.newsberri.com;

    root /var/www/newsberri.com;
    index index.html;
    try_files $uri $uri.html $uri/ =404;

    location ~* \.html$ { add_header Cache-Control "no-cache"; }
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    server_tokens off;
}
CONF
ln -sf /etc/nginx/sites-available/newsberri.com /etc/nginx/sites-enabled/newsberri.com

echo ">>> 5/5 testing config and starting nginx..."
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo ""
if curl -fsS -H "Host: newsberri.com" http://127.0.0.1/ | grep -q "NewsBerri"; then
  echo "=================================================="
  echo "  OK: SITE DEPLOYED AND SERVING ON THIS DROPLET"
  echo "  next: point DNS at this box, then run certbot"
  echo "=================================================="
else
  echo "!!! nginx is up but the test request didn't return the site — tell Claude."
fi
