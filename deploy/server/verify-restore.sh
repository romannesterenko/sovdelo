#!/usr/bin/env bash
set -euo pipefail
umask 077
[ "$(id -u)" = 0 ] || exit 1
cd /tmp
backup=$(python3 - <<'PY'
from pathlib import Path
paths=sorted(p for p in Path('/var/backups/sovdelo').iterdir() if p.is_dir() and not p.is_symlink() and (p/'SHA256SUMS').is_file())
if not paths:raise SystemExit('Нет готовой копии')
print(paths[-1])
PY
)
# Match only known files before reading checksums; never execute a manifest.
python3 - "$backup" <<'PY'
import sys
sys.path.insert(0,'/usr/local/lib/sovdelo')
import importlib.util,pathlib
spec=importlib.util.spec_from_file_location('backup_verify','/usr/local/lib/sovdelo/verify-backups.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
assert module.verify(pathlib.Path(sys.argv[1]),True)=='verified'
PY
database="sovdelo_restore_check_$(date -u +%Y%m%d%H%M%S)_$$"
created=0
role_created=0
cleanup(){
 result=$?;trap - EXIT
 unset PGPASSWORD
 if [ "$created" = 1 ]; then runuser -u postgres -- dropdb --if-exists "$database" || result=1;fi
 if [ "$role_created" = 1 ]; then runuser -u postgres -- dropuser --if-exists "$database" || result=1;fi
 exit "$result"
}
trap cleanup EXIT
password=$(python3 -c 'import secrets;print(secrets.token_hex(32))')
printf "CREATE ROLE \"%s\" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '%s';\n" "$database" "$password" | runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 >/dev/null
role_created=1
runuser -u postgres -- createdb --template=template0 --owner="$database" "$database"
created=1
export PGPASSWORD="$password"
unset password
pg_restore -h 127.0.0.1 -U "$database" --exit-on-error --single-transaction --no-owner --no-privileges --dbname="$database" "$backup/database.dump"
psql -X -h 127.0.0.1 -U "$database" -v ON_ERROR_STOP=1 -d "$database" -c 'SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM tasks) AS tasks;'
printf 'RESTORE VERIFIED: %s\n' "$backup"
