#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for file in setup.sh test.sh scripts/*.sh; do bash -n "$file"; done
if git rev-parse --show-toplevel >/dev/null 2>&1; then bash scripts/check-git.sh; fi
bash test.sh
npm ci --no-audit --no-fund
npm run test:frontend
npm run build
echo 'Проверки завершены успешно.'
