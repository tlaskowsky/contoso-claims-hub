#!/usr/bin/env bash
# Build ready-to-deploy packages into ./packages (instructor; needs Node 22).
#   ./scripts/build-packages.sh             # build
#   ./scripts/build-packages.sh --release   # build and publish as a GitHub release (needs gh)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$REPO_ROOT/packages"
mkdir -p "$PKG_DIR"
step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

# API: compiled code + production dependencies
step "Building api.zip"
pushd "$REPO_ROOT/src/api" >/dev/null
npm install --no-audit --no-fund && npm run build
STAGE=$(mktemp -d)
cp -r dist package.json "$STAGE/"; [[ -f package-lock.json ]] && cp package-lock.json "$STAGE/"
(cd "$STAGE" && npm install --omit=dev --no-audit --no-fund >/dev/null && rm -f "$PKG_DIR/api.zip" && zip -qr "$PKG_DIR/api.zip" .)
rm -rf "$STAGE"
popd >/dev/null

# Function apps: host.json + compiled code + production dependencies
for app in functions-validation functions-processing; do
  step "Building $app.zip"
  pushd "$REPO_ROOT/src/$app" >/dev/null
  npm install --no-audit --no-fund && npm run build
  STAGE=$(mktemp -d)
  cp -r dist host.json package.json "$STAGE/"; [[ -f package-lock.json ]] && cp package-lock.json "$STAGE/"
  (cd "$STAGE" && npm install --omit=dev --no-audit --no-fund >/dev/null && find . -name "*.js.map" -delete && rm -f "$PKG_DIR/$app.zip" && zip -qr "$PKG_DIR/$app.zip" .)
  rm -rf "$STAGE"
  popd >/dev/null
done

ls -lh "$PKG_DIR"

if [[ "${1:-}" == "--release" ]]; then
  TAG="packages-$(date -u +%Y%m%d-%H%M)"
  step "Publishing GitHub release $TAG"
  gh release create "$TAG" "$PKG_DIR"/*.zip --title "Application packages $TAG" \
    --notes "Pre-built Claims Intake API and Function app packages used by scripts/deploy-apps.sh." --latest
fi
