#!/usr/bin/env bash
set -euo pipefail
umask 077
[ "$(id -u)" = 0 ] || exit 1
base=/var/www/sovdelo
[ -L "$base/current" ] && [ -f "$base/.managed-sovdelo" ] || { echo 'Нет установки СовДела'; exit 1; }
exec 9>/run/lock/sovdelo-deploy.lock
flock -n 9 || { echo 'Идёт деплой/резервное копирование; повторить позже.'; exit 1; }
[ ! -e "$base/deploying" ] || { echo 'Сайт уже в режиме обслуживания. Нужна проверка администратора.'; exit 1; }
password=$(python3 - "$base/shared/.env" <<'PY'
import pathlib,re,sys
m=re.search(r'^DB_PASSWORD=([0-9a-f]{64})$',pathlib.Path(sys.argv[1]).read_text(),re.M)
if not m:raise SystemExit('Неожиданный формат пароля БД')
print(m[1])
PY
)
export PGPASSWORD="$password"
unset password
size=$(psql -X -h 127.0.0.1 -U sovdelo -d sovdelo -Atq -c 'SELECT pg_database_size(current_database())')
files=$(du -sb "$base/shared/storage/app" | cut -f1)
free=$(df -B1 --output=avail /var/backups/sovdelo | tail -1 | tr -d ' ')
[ "$free" -gt "$((2*(size+files)+1073741824))" ] || { echo 'Недостаточно места для копии'; exit 1; }
queue=0;scheduler=0;blocked=0
if systemctl is-active --quiet sovdelo-queue; then queue=1; fi
if systemctl is-active --quiet sovdelo-scheduler; then scheduler=1; fi
resume(){
 result=$?
 trap - EXIT
 if [ "$blocked" = 1 ]; then
  if [ "$queue" = 1 ]; then systemctl start sovdelo-queue || result=1; fi
  if [ "$scheduler" = 1 ]; then systemctl start sovdelo-scheduler || result=1; fi
  rm -f "$base/deploying" || result=1
 fi
 exit "$result"
}
trap resume EXIT
touch "$base/deploying";blocked=1
systemctl stop sovdelo-queue sovdelo-scheduler
pkill -QUIT -u sovdelo -f '^php-fpm: pool sovdelo$' || true
for i in $(seq 1 130); do
 if ! pgrep -u sovdelo -f '^php-fpm: pool sovdelo$' >/dev/null; then break; fi
 if [ "$i" = 130 ]; then echo 'PHP-запросы не завершились'; exit 1; fi
 sleep 1
done
backup="/var/backups/sovdelo/$(date -u +%Y%m%d%H%M%S)-daily-$$"
mkdir -m 0700 "$backup"
pg_dump -h 127.0.0.1 -U sovdelo -d sovdelo --format=custom --no-owner --no-privileges --file="$backup/database.dump"
pg_restore --list "$backup/database.dump" >/dev/null
cp "$base/shared/.env" "$backup/.env"
tar -czf "$backup/files.tar.gz" -C "$base/shared/storage" app
readlink -f "$base/current" > "$backup/previous-release.txt"
cp "$base/current/.sovdelo-release.json" "$backup/release.json"
(cd "$backup" && sha256sum database.dump files.tar.gz .env > SHA256SUMS)
unset PGPASSWORD
printf 'BACKUP %s\n' "$backup"
