#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "${VICTOR_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd -P)"
HOME_DIR="${VICTOR_HOME:-/home/lenovo/victor_wiki}"
ENV_FILE="$HOME_DIR/secrets/deployment.env"
DATA_DIR=/data1/victor_wiki
compose() {
  docker compose --progress plain --project-directory "$ROOT" --env-file "$ENV_FILE" -f "$ROOT/docker-compose.yml" -f "$ROOT/deploy/victor/compose.override.yml" "$@"
}
start_log() {
  mkdir -p "$HOME_DIR/logs"
  exec > >(tee -a "$HOME_DIR/logs/$1.log") 2>&1
}
