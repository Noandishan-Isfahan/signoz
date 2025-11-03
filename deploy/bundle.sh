#!/usr/bin/env bash
set -Eeuo pipefail

# Creates: dist/deploy-version-<tag>/{deploy/docker-compose.yaml, images/imagelist.txt}

# --- locate repo root & compose
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
COMPOSE="deploy/docker/docker-compose.yaml"
COMPOSE_TLS="deploy/docker/docker-compose.tls.yaml"
[[ -f "$COMPOSE" ]] || { echo "ERROR: $COMPOSE not found"; exit 1; }
[[ -f "$COMPOSE_TLS" ]] || { echo "ERROR: $COMPOSE_TLS not found"; exit 1; }
# --- get unique image list (no pulling)
mapfile -t IMAGES < <(docker compose -f "$COMPOSE" -f "$COMPOSE_TLS" config --images | sort -u)
(( ${#IMAGES[@]} > 0 )) || { echo "ERROR: no images resolved from compose"; exit 2; }


VERSION_TAG=$(docker compose -f $COMPOSE config --images|grep "signoz/signoz:"|cut -d ":" -f 2)

PKG_DIR="dist/deploy-version-${VERSION_TAG}"
rm -rf "dist/deploy-version-${VERSION_TAG}" || true
mkdir -p "${PKG_DIR}/images"
mkdir -p "${PKG_DIR}/docker"

echo "📦 Packaging SigNoz version: $VERSION_TAG"
echo "Output dir: $PKG_DIR"

# --- optionally copy .env
read -p "Do you want to copy .env to the package? [y/N]: " COPY_ENV
if [[ "$COPY_ENV" =~ ^[Yy]$ ]]; then
    cp deploy/docker/.env "$PKG_DIR/docker" 2>/dev/null || echo ".env not found, skipped."
fi

# # --- save images to zstd
for img in "${IMAGES[@]}"; do
    safe_name=$(echo "$img" | sed 's#[/:]#_#g').zst
    echo "Saving $img → images/$safe_name"
    docker save "$img" | zstd -T0 -15 -v -o "${PKG_DIR}/images/$safe_name"
done

cp deploy/image_load.sh "${PKG_DIR}/images/"
chmod +x "${PKG_DIR}/images/image_load.sh"
cp -r deploy/common "${PKG_DIR}/"

cp deploy/docker/otel-collector-config.yaml "${PKG_DIR}/docker/"
cp deploy/docker/docker-compose.yaml "${PKG_DIR}/docker/docker-compose.yaml"
cp deploy/docker/docker-compose.tls.yaml "${PKG_DIR}/docker/docker-compose.tls.yaml"
cp deploy/docker/nginx.conf "${PKG_DIR}/docker/nginx.conf"

read -p "Do you want to include certs? [y/N]: " COPY_CERTS
if [[ "$COPY_CERTS" =~ ^[Yy]$ ]]; then
    # Remove certs folder from the copied package if user said no
    cp -r deploy/certs $PKG_DIR/certs
fi

ARCHIVE_NAME="dist/${VERSION_TAG}.tar"
tar -cf $ARCHIVE_NAME -C $PKG_DIR .
echo "Deploy package created: $(readlink -f $ARCHIVE_NAME)"
echo "You can now transfer it to your production server"