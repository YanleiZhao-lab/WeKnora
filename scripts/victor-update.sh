#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log update
ACTIVE_ROOT="$ROOT"
exec 9>"$HOME_DIR/update.lock"
flock -n 9 || exit 0
UPSTREAM=https://github.com/Tencent/WeKnora.git
LATEST="$(curl --fail --silent --show-error --proxy http://127.0.0.1:7897 --connect-timeout 15 --max-time 60 https://api.github.com/repos/Tencent/WeKnora/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
[[ "$LATEST" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Unexpected stable version'; exit 1; }
CURRENT="v$(tr -d '\r\n' < "$ROOT/VERSION")"
if [[ "$LATEST" == "$CURRENT" ]]; then
  if [[ -z "$(git -C "$ROOT" status --porcelain)" ]]; then
    git -C "$ROOT" push origin HEAD:personal/victor-wiki
  fi
  printf '%s: already running %s\n' "$(date -Is)" "$CURRENT"
  exit 0
fi
if [[ "$(printf '%s\n' "$CURRENT" "$LATEST" | sort -V | tail -n 1)" != "$LATEST" ]]; then
  echo "Latest release $LATEST is older than installed $CURRENT; no downgrade."
  exit 0
fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo 'Current source contains local changes; update stopped.'
  exit 1
fi
VICTOR_ROOT="$ACTIVE_ROOT" bash "$ACTIVE_ROOT/scripts/victor-smoke.sh"
CANDIDATE="$HOME_DIR/releases/$LATEST"
if [[ -e "$CANDIDATE" ]]; then
  echo "Candidate already exists; inspect $CANDIDATE before retry."
  exit 1
fi
git -C "$ROOT" -c http.proxy=http://127.0.0.1:7897 fetch "$UPSTREAM" "refs/tags/$LATEST:refs/tags/$LATEST"
git -C "$ROOT" worktree add -b "release/$LATEST" "$CANDIDATE" HEAD
if ! git -C "$CANDIDATE" merge --no-edit "$LATEST"; then
  echo "Merge needs review in $CANDIDATE; running version preserved."
  exit 1
fi
ln -s "$ENV_FILE" "$CANDIDATE/.env"
ROOT="$CANDIDATE"
export VICTOR_ROOT="$CANDIDATE"
export WEKNORA_VERSION="$LATEST"
export VICTOR_IMAGE_TAG="${LATEST#v}-$(git -C "$CANDIDATE" rev-parse --short HEAD)"
NEW_DB_IMAGE="$(compose config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["postgres"]["image"])')"
OLD_DB_IMAGE="$(docker inspect WeKnora-postgres --format '{{.Config.Image}}')"
if [[ "$NEW_DB_IMAGE" != "$OLD_DB_IMAGE" ]]; then
  echo 'PostgreSQL image changed; manual migration review required.'
  exit 1
fi
NEW_GRAPH_IMAGE="$(compose config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["neo4j"]["image"])')"
OLD_GRAPH_IMAGE="$(docker inspect WeKnora-neo4j --format '{{.Config.Image}}')"
if [[ "$NEW_GRAPH_IMAGE" != "$OLD_GRAPH_IMAGE" ]]; then
  echo 'Neo4j image changed; manual migration review required.'
  exit 1
fi
bash "$CANDIDATE/scripts/victor-build.sh"
bash "$CANDIDATE/scripts/victor-pull.sh"
if [[ "${1:-}" == '--check-only' ]]; then
  echo "Candidate build passed: $CANDIDATE"
  exit 0
fi
export VICTOR_BACKUP_DIR="$DATA_DIR/backups/pre-$LATEST-$(date +%Y%m%d-%H%M%S)"
VICTOR_ROOT="$ACTIVE_ROOT" bash "$ACTIVE_ROOT/scripts/victor-compose.sh" stop frontend app neo4j redis
if ! VICTOR_BACKUP_ALREADY_STOPPED=1 VICTOR_ROOT="$ACTIVE_ROOT" bash "$ACTIVE_ROOT/scripts/victor-backup.sh"; then
  env -u WEKNORA_VERSION -u VICTOR_IMAGE_TAG VICTOR_ROOT="$ACTIVE_ROOT" bash "$ACTIVE_ROOT/scripts/victor-compose.sh" up -d --no-build redis neo4j app frontend
  exit 1
fi
if compose up -d --no-build --wait --wait-timeout 300 && bash "$CANDIDATE/scripts/victor-smoke.sh"; then
  python3 - "$ENV_FILE" "$LATEST" "$VICTOR_IMAGE_TAG" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
lines = path.read_text().splitlines()
lines = [('WEKNORA_VERSION=' + sys.argv[2]) if line.startswith('WEKNORA_VERSION=') else ('VICTOR_IMAGE_TAG=' + sys.argv[3]) if line.startswith('VICTOR_IMAGE_TAG=') else line for line in lines]
temporary = path.with_suffix('.env.new')
temporary.write_text('\n'.join(lines) + '\n')
temporary.chmod(0o600)
temporary.replace(path)
PY
  ln -sfn "$CANDIDATE" "$HOME_DIR/current"
  git -C "$CANDIDATE" push origin HEAD:personal/victor-wiki
  echo "Upgrade complete: $LATEST; backup $VICTOR_BACKUP_DIR"
else
  echo 'Upgrade failed; restoring the pre-upgrade database and configuration.'
  VICTOR_ROOT="$ACTIVE_ROOT" bash "$ACTIVE_ROOT/scripts/victor-restore.sh" "$VICTOR_BACKUP_DIR"
  echo "Previous version restored; inspect $CANDIDATE and update.log."
  exit 1
fi
