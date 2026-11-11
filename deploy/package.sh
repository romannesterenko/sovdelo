#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:?Укажите путь итогового tar.gz}
output=$(realpath -m "$output")
command -v git >/dev/null
command -v npm >/dev/null
bash scripts/check-git.sh
git diff --quiet || { echo 'Сначала сохраните изменения в Git.'; exit 1; }
git diff --cached --quiet || { echo 'Сначала сделайте коммит.'; exit 1; }
if [ -n "$(git ls-files --others --exclude-standard)" ]; then echo 'Есть неотслеживаемые файлы: проверьте git status перед упаковкой.'; exit 1; fi
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
git archive HEAD | tar -x -C "$stage"
sha=$(git rev-parse HEAD)
(cd "$stage" && npm ci && npm run test:frontend && npm run build)
python3 - "$stage" "$sha" <<'PY'
import json,sys,pathlib,datetime
p=pathlib.Path(sys.argv[1]);assert (p/'public/build/manifest.json').is_file()
(p/'.sovdelo-release.json').write_text(json.dumps({'commit':sys.argv[2],'built_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
# Only source + generated assets. No development dependencies or runtime data.
import shutil
for name in ['node_modules','vendor','public/hot']:
 q=p/name
 if q.is_dir():shutil.rmtree(q)
 elif q.exists():q.unlink()
for directory in ['storage','bootstrap/cache']:
 q=p/directory
 if q.exists():shutil.rmtree(q)
 q.mkdir(parents=True)
for q in p.rglob('*'):
 if q.is_file() and (q.name=='.env' or (q.name.startswith('.env.') and q.name!='.env.example')):raise SystemExit('Запрещён файл окружения в архиве')
PY
mkdir -p "$(dirname "$output")"
tar -czf "$output" -C "$stage" .
printf 'Релиз %s\n%s\n' "$sha" "$output"
