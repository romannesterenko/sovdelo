#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for command in php composer node npm; do
 command -v "$command" >/dev/null || { echo "Не найден $command"; exit 1; }
done
php -r 'if(PHP_VERSION_ID<80300){fwrite(STDERR,"Нужен PHP 8.3+\n");exit(1);} foreach(["intl","mbstring","pdo_pgsql","dom","curl","zip"] as $ext){if(!extension_loaded($ext)){fwrite(STDERR,"Нет PHP расширения: $ext\n");exit(1);}}'
node -e 'const [a,b]=process.versions.node.split(".").map(Number);if(a<22||(a===22&&b<12))process.exit(1)'
if [ ! -f .env ]; then
 cp .env.example .env
 php -r '$p=".env";$s=file_get_contents($p);$s=preg_replace("/^DB_PASSWORD=.*$/m","DB_PASSWORD=".bin2hex(random_bytes(24)),$s);file_put_contents($p,$s);'
 chmod 600 .env
fi
composer install --no-interaction --prefer-dist
if php -r 'exit(preg_match("/^APP_KEY=.+$/m",file_get_contents(".env"))?1:0);'; then php artisan key:generate; fi
if [ "${1:-}" = "--docker" ]; then docker compose up -d --wait; fi
php artisan migrate
npm ci
npm run build
echo 'Готово. Запуск: composer run dev | http://localhost:8010'
