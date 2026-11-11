#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo 'Запускать от root.'; exit 1; }
base=/var/www/sovdelo
here=$(cd "$(dirname "$0")" && pwd)
[ -L "$base/current" ] && [ -f "$base/.managed-sovdelo" ] || { echo 'Сначала установить релиз.'; exit 1; }
if ! command -v certbot >/dev/null; then apt-get update; apt-get install -y certbot; fi
certbot certonly --webroot -w "$base/acme" -d xn--b1aedylep.xn--p1ai --cert-name xn--b1aedylep.xn--p1ai --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring
old=$(mktemp)
cp /etc/nginx/sites-available/sovdelo "$old"
trap 'rm -f "$old"' EXIT
install -m 0644 "$here/nginx-https.conf" /etc/nginx/sites-available/sovdelo
if ! nginx -t; then cp "$old" /etc/nginx/sites-available/sovdelo; exit 1; fi
systemctl reload nginx
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/sovdelo-reload-nginx <<'HOOK'
#!/bin/sh
nginx -t && systemctl reload nginx
HOOK
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/sovdelo-reload-nginx
if systemctl cat certbot.timer >/dev/null 2>&1; then systemctl enable --now certbot.timer; fi
curl --fail --silent --show-error --resolve xn--b1aedylep.xn--p1ai:443:127.0.0.1 https://xn--b1aedylep.xn--p1ai/up >/dev/null
systemctl --no-pager --full status sovdelo-queue sovdelo-scheduler
printf '\nОткрывайте https://совдело.рф\n'
