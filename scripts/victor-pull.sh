#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log pull
if [[ $# -gt 0 ]]; then
  IMAGES=("$@")
else
  mapfile -t IMAGES < <(compose config --images | grep -v '^victor-wiki/' | sort -u)
fi
for image in "${IMAGES[@]}"; do
  repository="${image%:*}"
  tag="${image##*:}"
  [[ "$repository" == */* ]] || repository="library/$repository"
  digest="$(curl --fail --silent --show-error --proxy http://127.0.0.1:7897 --connect-timeout 15 --max-time 60 "https://hub.docker.com/v2/repositories/$repository/tags/$tag" | python3 -c 'import json,sys; data=json.load(sys.stdin); matches=[x["digest"] for x in data["images"] if x.get("architecture")=="amd64" and x.get("os")=="linux"]; assert len(matches)==1; print(matches[0])')"
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || exit 1
  reference="docker.m.daocloud.io/$repository@$digest"
  printf 'Official linux/amd64 image %s: %s\n' "$image" "$digest"
  docker pull "$reference"
  docker tag "$reference" "$image"
done
