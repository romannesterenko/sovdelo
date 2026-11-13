#!/usr/bin/env bash
set -euo pipefail
umask 077
if [[ ! ${SSH_ORIGINAL_COMMAND:-} =~ ^deploy\ ([a-f0-9]{40})\ ([1-9][0-9]{0,8})$ ]]; then echo 'Only: deploy COMMIT RUN_NUMBER' >&2; exit 64; fi
sha=${BASH_REMATCH[1]}
number=${BASH_REMATCH[2]}
exec 9>/run/lock/sovdelo-deploy.lock
flock -n 9 || { echo 'Another deployment is running.' >&2; exit 75; }
archive=$(mktemp /var/lib/sovdelo-deploy/incoming/release.XXXXXX.tar.gz)
trap 'rm -f "$archive"' EXIT
timeout 180 python3 /usr/local/lib/sovdelo/receive-release.py "$archive"
bash /usr/local/lib/sovdelo/update-release.sh "$archive" "$sha" "$number"
