#!/usr/bin/env bash
set -euo pipefail
umask 027
[ "$(id -u)" = 0 ] || { echo 'Запускать от root на сервере.'; exit 1; }
archive=$(realpath "${1:?Укажите архив релиза}")
base=/var/www/sovdelo
here=$(cd "$(dirname "$0")" && pwd)
[ -S /run/php/php8.3-fpm-sovput.sock ] || { echo 'Не найден ожидаемый PHP-FPM СовПути; остановка для проверки сервера.'; exit 1; }
for cmd in php composer python3 psql createdb pg_dump nginx php-fpm8.3 runuser; do command -v "$cmd" >/dev/null || { echo "Не найден $cmd"; exit 1; }; done
php -r 'foreach(["pdo_pgsql","mbstring","xml","ctype","curl","dom","fileinfo","intl"] as $e)if(!extension_loaded($e)){fwrite(STDERR,"Не найден модуль PHP: $e\n");exit(1);}'
if [ -d "$base" ] && [ -n "$(ls -A "$base")" ] && [ ! -f "$base/.managed-sovdelo" ]; then echo 'Каталог СовДела уже занят. Остановка без изменения файлов.'; exit 1; fi
sha=$(python3 "$here/validate-release.py" "$archive")
if [ -L "$base/current" ]; then
 current_sha=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["commit"])' "$base/current/.sovdelo-release.json")
 if [ "$current_sha" != "$sha" ]; then echo 'Уже установлен другой релиз. Сначала настроим резервные копии и обновление с откатом.'; exit 1; fi
fi
if ! id sovdelo >/dev/null 2>&1; then useradd --system --user-group --home-dir /var/lib/sovdelo --create-home --shell /usr/sbin/nologin sovdelo; fi
install -d -m 0755 "$base" "$base/releases" "$base/acme"
touch "$base/.managed-sovdelo"
install -d -o root -g sovdelo -m 0750 "$base/shared"
for path in app/private app/public framework/cache/data framework/sessions framework/views logs; do install -d -o sovdelo -g sovdelo -m 0770 "$base/shared/storage/$path"; done
chown sovdelo:sovdelo "$base/shared/storage" "$base/shared/storage/app" "$base/shared/storage/framework" "$base/shared/storage/framework/cache"
chmod 0770 "$base/shared/storage" "$base/shared/storage/app" "$base/shared/storage/framework" "$base/shared/storage/framework/cache"
if [ ! -e "$base/shared/.env" ]; then
 python3 - "$base/shared/.env" <<'PY'
import secrets,base64,pathlib,sys
p=pathlib.Path(sys.argv[1]);key=base64.b64encode(secrets.token_bytes(32)).decode();password=secrets.token_hex(32)
p.write_text('''APP_NAME="СовДело"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://xn--b1aedylep.xn--p1ai
APP_LOCALE=ru
APP_FALLBACK_LOCALE=en
LOG_CHANNEL=stack
LOG_LEVEL=warning
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=sovdelo
DB_USERNAME=sovdelo
SESSION_DRIVER=database
SESSION_LIFETIME=10080
SESSION_ENCRYPT=true
SESSION_SECURE_COOKIE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=lax
SESSION_DOMAIN=null
SESSION_COOKIE=sovdelo_session
CACHE_STORE=database
CACHE_PREFIX=sovdelo_
QUEUE_CONNECTION=database
FILESYSTEM_DISK=local
MAIL_MAILER=log
MAIL_FROM_ADDRESS=noreply@xn--b1aedylep.xn--p1ai
MAIL_FROM_NAME="СовДело"
'''+f'APP_KEY=base64:{key}\nDB_PASSWORD={password}\n')
p.chmod(0o640)
PY
fi
chown root:sovdelo "$base/shared/.env"
password=$(python3 - "$base/shared/.env" <<'PY'
import sys,re,pathlib
s=pathlib.Path(sys.argv[1]).read_text();m=re.search(r'^DB_PASSWORD=([0-9a-f]{64})$',s,re.M)
if not m:raise SystemExit('Ожидался пароль, созданный установщиком. Проверьте существующий .env.')
print(m[1])
PY
)
role=$(runuser -u postgres -- psql -X -Atq -c "SELECT 1 FROM pg_roles WHERE rolname='sovdelo'")
if [ "$role" != 1 ]; then
 printf "CREATE ROLE sovdelo LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '%s';\n" "$password" | runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 >/dev/null
fi
owner=$(runuser -u postgres -- psql -X -Atq -c "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='sovdelo'")
if [ -z "$owner" ]; then runuser -u postgres -- createdb -O sovdelo sovdelo; elif [ "$owner" != sovdelo ]; then echo 'База sovdelo принадлежит другой роли; остановка.'; exit 1; fi
PGPASSWORD="$password" psql -X -h 127.0.0.1 -U sovdelo -d sovdelo -Atq -c 'SELECT 1' >/dev/null
unset password
release="$base/releases/$(date -u +%Y%m%d%H%M%S)-${sha:0:12}"
mkdir "$release"
chown sovdelo:sovdelo "$release"
cat "$archive" | runuser -u sovdelo -- tar -xz -C "$release" --no-same-owner --no-same-permissions
[ -f "$release/public/build/manifest.json" ] && [ -f "$release/composer.lock" ] || { echo 'Нет сборки или composer.lock'; exit 1; }
rm -rf "$release/storage"
ln -s "$base/shared/storage" "$release/storage"
ln -s "$base/shared/.env" "$release/.env"
install -d -o sovdelo -g sovdelo -m 0770 "$release/bootstrap/cache"
runuser -u sovdelo -- env HOME=/var/lib/sovdelo COMPOSER_HOME=/var/lib/sovdelo/.composer composer install --working-dir="$release" --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader
# Only the dedicated config files may be installed/updated.
for target in /etc/php/8.3/fpm/pool.d/sovdelo.conf /etc/nginx/sites-available/sovdelo; do
 if [ -e "$target" ] && ! grep -q 'Managed by SovDelo' "$target"; then echo "Уже существует неуправляемый файл $target; остановка."; exit 1; fi
done
install -m 0644 "$here/php-fpm.conf" /etc/php/8.3/fpm/pool.d/sovdelo.conf
if [ ! -e /etc/nginx/sites-available/sovdelo ]; then install -m 0644 "$here/nginx-http.conf" /etc/nginx/sites-available/sovdelo; fi
ln -sfn /etc/nginx/sites-available/sovdelo /etc/nginx/sites-enabled/sovdelo
php-fpm8.3 -t
nginx -t
for unit in sovdelo-queue sovdelo-scheduler; do
 if systemctl is-active --quiet "$unit"; then systemctl stop "$unit"; fi
 install -m 0644 "$here/$unit.service" "/etc/systemd/system/$unit.service"
done
cd "$release"
runuser -u sovdelo -- php artisan down
# Never reset the database. If migrations fail, leave maintenance enabled for diagnosis.
runuser -u sovdelo -- php artisan migrate --force
runuser -u sovdelo -- php artisan config:cache
runuser -u sovdelo -- php artisan view:cache
# Runtime folders stay writable, deployed source is root-owned.
find "$release" -type d -exec chmod 0755 {} +
find "$release" -type d -exec chown root:sovdelo {} +
find "$release" -type f -exec chown root:sovdelo {} +
find "$release" -type f -exec chmod 0640 {} +
find "$release/public" -type f -exec chmod 0644 {} +
chown -R sovdelo:sovdelo "$release/bootstrap/cache"
chmod 0770 "$release/bootstrap/cache"
ln -sfn "$release" "$base/current.next"
mv -Tf "$base/current.next" "$base/current"
systemctl daemon-reload
systemctl reload php8.3-fpm
systemctl reload nginx
runuser -u sovdelo -- php artisan up
systemctl enable --now sovdelo-queue sovdelo-scheduler
printf 'Релиз активирован: %s\nДалее выполните finish-https.sh.\n' "$sha"
