#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import pathlib,subprocess
paths=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
bad=[]
for name in filter(None,paths):
 parts=pathlib.PurePosixPath(name).parts
 if any(((x=='.env' or x.startswith('.env.')) and x!='.env.example') or x in {'auth.json','id_ed25519','id_rsa'} or x.endswith(('.pem','.key','.dump','.sql','.sqlite','.sqlite3')) for x in parts) or parts[0] in {'vendor','node_modules','backups'}:
  bad.append(name)
if bad:
 print('Git содержит файлы данных/секретов. Уберите их из индекса без удаления локальных файлов:')
 for n in bad:print(n)
 raise SystemExit(1)
print('Проверка имён файлов Git пройдена. Содержимое секретов не сканируется.')
PY
