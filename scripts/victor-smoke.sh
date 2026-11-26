#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
curl --fail --silent --show-error --max-time 20 http://127.0.0.1:8091/health
curl --fail --silent --show-error --max-time 20 http://127.0.0.1:8090/ > /dev/null
compose exec -T ollama ollama list | grep -F 'qwen2.5:3b'
compose exec -T ollama ollama list | grep -F 'bge-m3'

bash "$ROOT/scripts/victor-acceptance.sh"

bash "$ROOT/scripts/victor-assistant-acceptance.sh"
