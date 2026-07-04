#!/usr/bin/env bash
# ============================================================
# InfraStack installer — run on a fresh Ubuntu VPS
#   git clone <repo> && cd infra-stack && ./install.sh
# Installs Docker (+rollout plugin), creates shared networks,
# prepares .env, then brings up the core stack.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"

echo "=============================================="
echo " InfraStack v$(cat VERSION) — installer"
echo "=============================================="

# ── 1. Docker ────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  echo "[1/6] Installing Docker…"
  curl -fsSL https://get.docker.com | sh
  sudo systemctl enable --now docker
else
  echo "[1/6] Docker already installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin missing. Install docker-compose-plugin first." >&2
  exit 1
fi

# ── 2. docker-rollout plugin (zero-downtime deploy) ──
if docker rollout --help >/dev/null 2>&1; then
  echo "[2/6] docker-rollout already installed"
else
  echo "[2/6] Installing docker-rollout plugin (zero-downtime deploy)…"
  mkdir -p "$HOME/.docker/cli-plugins"
  curl -fsSL https://raw.githubusercontent.com/wowu/docker-rollout/main/docker-rollout \
    -o "$HOME/.docker/cli-plugins/docker-rollout"
  chmod +x "$HOME/.docker/cli-plugins/docker-rollout"
fi

# ── 3. Shared networks ───────────────────────────────
echo "[3/6] Creating shared networks (proxy, backend)…"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
docker network inspect backend >/dev/null 2>&1 || docker network create backend

# ── 4. Environment file ──────────────────────────────
if [ ! -f .env ]; then
  echo "[4/6] Creating .env from .env.example — EDIT IT before continuing."
  cp .env.example .env
  echo ""
  echo "  >>> nano .env   (set BASE_DOMAIN, ACME_EMAIL, passwords) <<<"
  echo ""
  read -rp "Press Enter after editing .env to continue…"
else
  echo "[4/6] .env already exists — keeping it."
fi

# ── 5. Traefik ACME storage ──────────────────────────
echo "[5/6] Preparing Traefik certificate storage…"
touch services/traefik/acme.json
chmod 600 services/traefik/acme.json

# ── 6. Core stack ────────────────────────────────────
echo "[6/6] Starting core stack (Traefik + Portainer)…"
docker compose --env-file .env -f docker/docker-compose.core.yml up -d

echo ""
echo "✅ Core stack running."
echo "Next steps:"
echo "  docker compose --env-file .env -f docker/docker-compose.database.yml up -d"
echo "  docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d"
echo "  ./scripts/create-project.sh <name> <laravel|nextjs|n8n|ai-worker>"
