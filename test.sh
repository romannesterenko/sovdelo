#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for command in php docker; do
 command -v "$command" >/dev/null || { echo "Не найден $command"; exit 1; }
done
[ -f vendor/autoload.php ] || { echo 'Сначала выполните composer install'; exit 1; }
# This script is for local development only; use exactly the isolated Compose project.
[ "${APP_ENV:-local}" != production ] || { echo 'Тесты запрещены в production'; exit 1; }
docker compose -p sovdelo exec -T postgres sh -eu -c '
 test "$POSTGRES_DB" = sovdelo || { echo "Ожидалась база sovdelo"; exit 1; }
 if ! psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '\''sovdelo_testing'\''" | grep -qx 1; then
  createdb -U "$POSTGRES_USER" sovdelo_testing
 fi
'
# Ignore .env DB_URL and cached production/development configuration.
APP_ENV=testing APP_CONFIG_CACHE=bootstrap/cache/sovdelo-testing-config.php \
 DB_URL= DB_CONNECTION=pgsql DB_HOST=127.0.0.1 DB_PORT=5433 \
 DB_DATABASE=sovdelo_testing CACHE_STORE=array SESSION_DRIVER=array QUEUE_CONNECTION=sync \
 php artisan test --filter=WorkspaceTest
