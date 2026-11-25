#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log frontend-image
TAG="${1:?请提供前端镜像标签}"
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
test -f "$ROOT/frontend/dist/index.html"
bash "$ROOT/scripts/victor-pull.sh" "wechatopenai/weknora-ui:v${VERSION#v}"
docker build --build-arg "UPSTREAM_VERSION=v${VERSION#v}" -f "$ROOT/deploy/victor/Dockerfile.frontend" -t "victor-wiki/frontend:$TAG" "$ROOT/frontend/dist"
printf '%s\n' "$TAG" > "$HOME_DIR/candidate-image-tag"
printf 'Frontend image ready: victor-wiki/frontend:%s\n' "$TAG"
