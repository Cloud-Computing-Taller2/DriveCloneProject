#!/usr/bin/env bash
# Starts a Cloudflare Tunnel connector against the Compose nginx service.
# TUNNEL_TOKEN is read from the environment or from .env; it is never committed.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${TUNNEL_TOKEN:-}" ]]; then
  echo "TUNNEL_TOKEN is empty; set it in .env (see docs/demo.md)" >&2
  exit 1
fi

exec docker run --rm \
  --network driveclone_default \
  --env TUNNEL_TOKEN \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
