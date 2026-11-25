#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
umask 077
BACKUP_DIR="${VICTOR_BACKUP_DIR:-$DATA_DIR/backups/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$BACKUP_DIR"
set -a
source "$ENV_FILE"
set +a
if [[ "${VICTOR_BACKUP_ALREADY_STOPPED:-0}" != 1 ]]; then
  compose stop frontend app neo4j redis
  trap 'compose start redis neo4j app frontend' EXIT
fi
compose exec -T postgres pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$BACKUP_DIR/database.dump"
cp "$ENV_FILE" "$BACKUP_DIR/deployment.env"
git -C "$ROOT" rev-parse HEAD > "$BACKUP_DIR/source-commit"
compose config --images > "$BACKUP_DIR/images.txt"
for store in files neo4j redis; do
  docker run --rm --network none -v "$DATA_DIR/$store:/source:ro" --entrypoint tar redis:7.0-alpine -C /source -cf - . > "$BACKUP_DIR/$store.tar"
done
tar -C "$HOME_DIR" --exclude=secrets/deployment.env -cf "$BACKUP_DIR/secrets.tar" secrets
printf '%s\n' "$BACKUP_DIR"
