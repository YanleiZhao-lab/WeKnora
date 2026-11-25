#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log models
exec 8>"$HOME_DIR/models.lock"
flock -n 8 || { echo 'Another model installation is running'; exit 1; }
IMAGE="$(compose config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["services"]["ollama"]["image"])')"
CONTAINER=victor-wiki-model-download
if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "Inspect existing $CONTAINER before retrying."
  exit 1
fi
printf 'Waiting for verified Ollama runtime image.\n'
for attempt in $(seq 1 720); do
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then break; fi
  sleep 15
done
docker image inspect "$IMAGE" >/dev/null
cleanup() {
  docker stop --time 30 "$CONTAINER" >/dev/null 2>&1 || true
  docker rm "$CONTAINER" >/dev/null 2>&1 || true
}
compose stop ollama
docker run -d --name "$CONTAINER" --network host -v "$DATA_DIR/models:/root/.ollama" -e OLLAMA_NO_CLOUD=true -e OLLAMA_HOST=127.0.0.1:11435 -e HTTPS_PROXY=http://127.0.0.1:7897 -e HTTP_PROXY=http://127.0.0.1:7897 -e NO_PROXY=localhost,127.0.0.1 "$IMAGE" serve >/dev/null
trap cleanup EXIT
for attempt in $(seq 1 60); do
  if curl -fsS --max-time 2 http://127.0.0.1:11435/api/version >/dev/null 2>&1; then break; fi
  sleep 1
done
pull_model() {
  local model="$1" output="$2"
  printf 'Downloading public model %s\n' "$model"
  curl --fail --silent --show-error --max-time 10800 http://127.0.0.1:11435/api/pull -H 'Content-Type: application/json' --data "{\"name\":\"$model\",\"stream\":false}" > "$output"
  python3 - "$output" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
if result.get('status') != 'success':
    raise RuntimeError(result.get('error', 'Model download did not complete'))
print('Model download verified by Ollama: success')
PY
}
pull_model qwen2.5:3b "$HOME_DIR/logs/qwen25-pull.json" &
CHAT_PID=$!
pull_model bge-m3 "$HOME_DIR/logs/bge-m3-pull.json" &
EMBEDDING_PID=$!
STATUS=0
wait "$CHAT_PID" || STATUS=1
wait "$EMBEDDING_PID" || STATUS=1
[[ "$STATUS" == 0 ]] || exit 1
cleanup
trap - EXIT
compose up -d --no-build --no-deps --wait --wait-timeout 120 ollama
compose exec -T ollama ollama list
printf 'Local model installation complete.\n'
