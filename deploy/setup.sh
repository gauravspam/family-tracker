#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# Family Tracker — fresh Ubuntu provisioning script
# Run as: sudo bash deploy/setup.sh
# ------------------------------------------------------------------

INSTALL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Installing Family Tracker prerequisites ==="

# ------- Docker (latest stable) -------
if ! command -v docker &>/dev/null; then
  echo ">>> Installing Docker..."
  curl -fsSL https://get.docker.com | bash
  sudo usermod -aG docker "$USER"
else
  echo ">>> Docker already installed: $(docker --version)"
fi

# ------- Docker Compose plugin -------
if ! docker compose version &>/dev/null; then
  echo ">>> Installing Docker Compose plugin..."
  sudo apt-get update && sudo apt-get install -y docker-compose-plugin
fi
echo ">>> Docker Compose: $(docker compose version)"

# ------- Go 1.25.8 (exact version from go.mod) -------
if ! command -v go &>/dev/null || [[ "$(go version)" != *go1.25.8* ]]; then
  echo ">>> Installing Go 1.25.8..."
  curl -fsSL https://go.dev/dl/go1.25.8.linux-amd64.tar.gz -o /tmp/go1.25.8.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf /tmp/go1.25.8.tar.gz
  rm /tmp/go1.25.8.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh
  export PATH="$PATH:/usr/local/go/bin"
else
  echo ">>> Go already installed: $(go version)"
fi

echo ""
echo "=== All prerequisites installed ==="
echo ""
echo "Next steps:"
echo "  1. Copy .env.relay.example -> .env.relay and fill in secrets"
echo "  2a. Run everything with Docker Compose:"
echo "        docker compose -f deploy/docker/docker-compose.yml up -d --build"
echo ""
echo "  2b. Or run the Go relay natively (Postgres & Traccar still in Docker):"
echo "        docker compose -f deploy/docker/docker-compose.yml up -d postgres traccar"
echo "        cd services/notify_relay"
echo "        go run ./cmd/server"
echo ""
