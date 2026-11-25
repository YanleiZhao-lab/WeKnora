#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log startup
compose config --quiet
compose up -d --no-build --wait --wait-timeout 300
curl --fail --silent --show-error --max-time 30 http://127.0.0.1:8091/health
printf '\nvictor_wiki: http://192.168.30.2:8090\n'
