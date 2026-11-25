#!/usr/bin/env bash
set -euo pipefail
export PATH="/home/lenovo/.local/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HOME_DIR="${VICTOR_HOME:-/home/lenovo/victor_wiki}"
mkdir -p "$HOME_DIR/logs"
exec > >(tee -a "$HOME_DIR/logs/build.log") 2>&1
cd "$ROOT"
VERSION="$(cat VERSION | tr -d '\n\r')"
REVISION="$(git rev-parse --short HEAD)"
TAG="${VICTOR_IMAGE_TAG:-${VERSION}-${REVISION}}"
cd frontend
npm ci --registry=https://registry.npmjs.org --https-proxy=http://127.0.0.1:7897 --proxy=http://127.0.0.1:7897 --no-audit --no-fund
VITE_IS_DOCKER=true VITE_FRONTEND_COMMIT="$REVISION" NODE_OPTIONS=--max-old-space-size=4096 npm run build
cd "$ROOT"
bash "$ROOT/scripts/victor-pack-frontend.sh" "$TAG"
