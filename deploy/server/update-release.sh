#!/usr/bin/env bash
set -euo pipefail
umask 077
[ "$(id -u)" = 0 ] || exit 1
archive=${1:?}
sha=${2:?}
number=${3:?}
base=/var/www/sovdelo
lib=/usr/local/lib/sovdelo
state=/var/lib/sovdelo-deploy
[ -L "$base/current" ] && [ -f "$base/.managed-sovdelo" ] || { echo 'Initial installation is required.'; exit 1; }
actual=$(python3 "$lib/validate-release.py" "$archive")
[ "$actual" = "$sha" ] || { echo 'Archive commit mismatch'; exit 1; }
python3 - "$state/last-success.json" "$number" "$sha" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1])
if p.exists():
 old=json.loads(p.read_text())
 if int(sys.argv[2])<old['number'] or (int(sys.argv[2])==old['number'] and old['sha']!=sys.argv[3]):raise SystemExit('Stale or conflicting GitHub run')
PY
old=$(readlink -f "$base/current")
release="$base/releases/$(date -u +%Y%m%d%H%M%S)-${sha:0:12}-$number"
mkdir "$release"
chown sovdelo:sovdelo "$release"
cat "$archive" | runuser -u sovdelo -- tar -xz -C "$release" --no-same-owner --no-same-permissions
rm -rf "$release/storage"
ln -s "$base/shared/storage" "$release/storage"
ln -s "$base/shared/.env" "$release/.env"
install -d -o sovdelo -g sovdelo -m 0770 "$release/bootstrap/cache"
runuser -u sovdelo -- env HOME=/var/lib/sovdelo COMPOSER_HOME=/var/lib/sovdelo/.composer composer install --working-dir="$release" --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader
[ "$(realpath "$release/public")" = "$release/public" ] && [ "$(realpath "$release/bootstrap/cache")" = "$release/bootstrap/cache" ] || { echo 'Unexpected runtime symlink'; exit 1; }
# Prepare dependencies before blocking the website.
password=$(python3 - "$base/shared/.env" <<'PY'
import pathlib,re,sys
m=re.search(r'^DB_PASSWORD=([0-9a-f]{64})$',pathlib.Path(sys.argv[1]).read_text(),re.M)
if not m:raise SystemExit('Unexpected database password format')
print(m[1])
PY
)
export PGPASSWORD="$password"
unset password
size=$(psql -X -h 127.0.0.1 -U sovdelo -d sovdelo -Atq -c "SELECT pg_database_size(current_database())")
files=$(du -sb "$base/shared/storage/app" | cut -f1)
free=$(df -B1 --output=avail /var/backups/sovdelo | tail -1 | tr -d ' ')
[ "$free" -gt "$((2*(size+files)+1073741824))" ] || { echo 'Insufficient free space for backup'; exit 1; }
blocked=0
failure(){
 result=$?
 if [ "$result" != 0 ] && [ "$blocked" = 1 ]; then
  echo "Deployment failed. Maintenance remains enabled. Previous release: $old" >&2
  echo "Inspect Laravel log and /var/backups/sovdelo. Do not reset the database." >&2
 fi
 exit "$result"
}
trap failure EXIT
# Nginx blocks mutating app requests; /up remains available for health checks.
touch "$base/deploying"
blocked=1
systemctl stop sovdelo-queue sovdelo-scheduler
# Drain only this account's FPM children. Nginx now prevents new app requests.
pkill -QUIT -u sovdelo -f '^php-fpm: pool sovdelo$' || true
for i in $(seq 1 130); do
 if ! pgrep -u sovdelo -f '^php-fpm: pool sovdelo$' >/dev/null; then break; fi
 if [ "$i" = 130 ]; then echo 'PHP requests did not drain'; exit 1; fi
 sleep 1
done
backup="/var/backups/sovdelo/$(date -u +%Y%m%d%H%M%S)-$number"
mkdir -m 0700 "$backup"
pg_dump -h 127.0.0.1 -U sovdelo -d sovdelo --format=custom --no-owner --no-privileges --file="$backup/database.dump"
pg_restore --list "$backup/database.dump" >/dev/null
cp "$base/shared/.env" "$backup/.env"
tar -czf "$backup/files.tar.gz" -C "$base/shared/storage" app
printf '%s\n' "$old" > "$backup/previous-release.txt"
(cd "$backup" && sha256sum database.dump files.tar.gz .env > SHA256SUMS)
unset PGPASSWORD
cd "$release"
runuser -u sovdelo -- php artisan migrate --force
runuser -u sovdelo -- php artisan config:cache
runuser -u sovdelo -- php artisan view:cache
find "$release" -type d -exec chmod 0755 {} +
find "$release" -type d -exec chown root:sovdelo {} +
find "$release" -type f -exec chown root:sovdelo {} +
find "$release" -type f -exec chmod 0640 {} +
find "$release/public" -type f -exec chmod 0644 {} +
chown -R sovdelo:sovdelo "$release/bootstrap/cache"
chmod 0770 "$release/bootstrap/cache"
ln -sfn "$release" "$base/current.next"
mv -Tf "$base/current.next" "$base/current"
runuser -u sovdelo -- php artisan up
curl --fail --silent --show-error --retry 3 --retry-delay 2 --max-time 20 --resolve xn--b1aedylep.xn--p1ai:443:127.0.0.1 https://xn--b1aedylep.xn--p1ai/up >/dev/null
# Verify the configured database before reopening application requests.
runuser -u sovdelo -- php artisan migrate:status --no-ansi >/dev/null
systemctl start sovdelo-queue sovdelo-scheduler
systemctl is-active --quiet sovdelo-queue sovdelo-scheduler
python3 - "$state/last-success.json" "$number" "$sha" "$old" "$release" "$backup" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);temp=p.with_suffix('.tmp');temp.write_text(json.dumps({'number':int(sys.argv[2]),'sha':sys.argv[3],'previous':sys.argv[4],'current':sys.argv[5],'backup':sys.argv[6]}));temp.replace(p)
PY
rm -f "$base/deploying"
blocked=0
printf 'DEPLOYED %s\nBACKUP %s\n' "$sha" "$backup"
