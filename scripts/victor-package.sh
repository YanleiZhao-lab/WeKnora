#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log package
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
OUT="$DATA_DIR/artifacts/$VERSION-$(git -C "$ROOT" rev-parse --short HEAD)"
mkdir -p "$OUT"
git -C "$ROOT" archive --format=tar.gz -o "$OUT/source.tar.gz" HEAD
git -C "$ROOT" rev-parse HEAD > "$OUT/source-commit"
mapfile -t IMAGES < <(compose config --images | sort -u)
docker image save "${IMAGES[@]}" | gzip -1 > "$OUT/images.tar.gz"
tar -C "$DATA_DIR/models" -cf - models | gzip -1 > "$OUT/models.tar.gz"
cp "$ROOT/docs/victor_wiki.md" "$OUT/README.md"
printf 'Offline package: %s\n' "$OUT"
