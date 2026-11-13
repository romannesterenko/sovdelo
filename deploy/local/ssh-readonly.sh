#!/usr/bin/env bash
set -euo pipefail
key=${SOVDELO_BACKUP_KEY:-$HOME/.ssh/sovdelo_backup}
exec ssh -T -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o PreferredAuthentications=publickey -o StrictHostKeyChecking=yes -o ConnectTimeout=20 "$@"
