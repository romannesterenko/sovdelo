#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v git >/dev/null || { echo 'Установите git'; exit 1; }
root=$(pwd -P)
if git rev-parse --show-toplevel >/dev/null 2>&1; then
 current=$(git rev-parse --show-toplevel)
 [ "$current" = "$root" ] || { echo 'Папка находится внутри другого Git-репозитория. Создание остановлено.'; exit 1; }
else
 git init -b main
fi
# Do not stage, commit, alter identity, or change remote automatically.
for path in .env .env.production vendor/autoload.php node_modules/test backups/test.dump public/hot public/build/manifest.json; do
 git check-ignore -q --no-index "$path" || { echo "Не настроено исключение: $path"; exit 1; }
done
bash scripts/check-git.sh
echo 'Git готов. Следующие команды сохранят текущие исходники:'
echo 'git add .'
echo 'bash scripts/check-git.sh'
echo 'git commit -m "СовДело: основа и проверки"'
echo 'Удалённый репозиторий пока не подключён автоматически.'
