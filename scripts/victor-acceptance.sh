#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log acceptance
exec /home/lenovo/.local/bin/node "$ROOT/deploy/victor/acceptance.mts" "$@"
