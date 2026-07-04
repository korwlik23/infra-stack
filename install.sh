#!/usr/bin/env bash
# ============================================================
# InfraStack installer — run on a fresh Ubuntu VPS
#   git clone <repo> && cd infra-stack && ./install.sh
# Installs Docker, creates the shared proxy network, prepares
# .env, then brings up the core stack (Traefik + Portainer).
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"

echo "=============================================="
echo " InfraStack v$(cat VERSION) — installer"
echo "=============================================="

# ── 1. Docker ────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  echo "[1/5] Installing Docker…"
  curl -fsSL https://get.docker.com | sh
  sudo systemctl enable --now docker
else
  echo "[1/5] Docker already installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin missing. Install docker-compose-plugin first." >&2
  exit 1
fi

# ── 2. Shared networks ───────────────────────────────
echo "[2/5] Creating shared networks (proxy, backend)…"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
docker network inspect backend >/dev/null 2>&1 || docker network create backend

# ── 3. Environment file ──────────────────────────────
if [ ! -f .env ]; then
  echo "[3/5] Creating .env from .env.example — EDIT IT before continuing."
  cp .env.example .env
  echo ""
  echo "  >>> nano .env   (set BASE_DOMAIN, ACME_EMAIL, passwords) <<<"
  echo ""
  read -rp "Press Enter after editing .env to continue…"
else
  echo "[3/5] .env already exists — keeping it."
fi

# ── 4. Traefik ACME storage ──────────────────────────
echo "[4/5] Preparing Traefik certificate storage…"
touch services/traefik/acme.json
chmod 600 services/traefik/acme.json

# ── 5. Core stack ────────────────────────────────────
echo "[5/5] Starting core stack (Traefik + Portainer)…"
docker compose --env-file .env -f docker/docker-compose.core.yml up -d

echo ""
echo "✅ Core stack running."
echo "Next steps:"
echo "  docker compose --env-file .env -f docker/docker-compose.database.yml up -d"
echo "  docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d"
echo "  ./scripts/create-project.sh <name> <laravel|nextjs|n8n>"
