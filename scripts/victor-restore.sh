#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log restore
BACKUP="$(realpath "${1:?请指定备份目录}")"
case "$BACKUP" in
  "$DATA_DIR/backups/"*) ;;
  *) echo 'Backup must be inside the configured backup directory'; exit 1 ;;
esac
for file in database.dump deployment.env source-commit files.tar neo4j.tar redis.tar secrets.tar; do
  test -s "$BACKUP/$file"
done
test "$(git -C "$ROOT" rev-parse HEAD)" = "$(cat "$BACKUP/source-commit")" || { echo 'Set VICTOR_ROOT to the source worktree recorded by this backup'; exit 1; }
for store in files neo4j redis; do tar -tf "$BACKUP/$store.tar" >/dev/null; done
tar -tf "$BACKUP/secrets.tar" >/dev/null
compose exec -T postgres pg_restore --list < "$BACKUP/database.dump" >/dev/null
compose stop frontend app neo4j redis
set -a
source "$BACKUP/deployment.env"
set +a
compose exec -T postgres pg_restore --clean --if-exists --no-owner -U "$DB_USER" -d "$DB_NAME" < "$BACKUP/database.dump"
for store in files neo4j redis; do
  docker run --rm --network none -i -v "$DATA_DIR/$store:/restore" --entrypoint sh redis:7.0-alpine -c 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /restore -xf -' < "$BACKUP/$store.tar"
done
tar -C "$HOME_DIR" -xf "$BACKUP/secrets.tar"
install -m 600 "$BACKUP/deployment.env" "$ENV_FILE"
compose up -d --no-build --wait --wait-timeout 300
ln -sfn "$ROOT" "$HOME_DIR/current"
printf 'Restored source %s from %s\n' "$(git -C "$ROOT" rev-parse --short HEAD)" "$BACKUP"
