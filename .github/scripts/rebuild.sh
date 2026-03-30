#!/usr/bin/env bash
set -euo pipefail

# Rebuild script for facebook/relay
# Runs on existing source tree (no clone). Installs deps and builds.
# Expected to run from the docusaurus root (website/) of the staging repo.

REPO_URL="https://github.com/facebook/relay"
BRANCH="main"
NODE_VERSION="20"

# Setup NVM
export NVM_DIR="${HOME}/.nvm"
if [ ! -f "${NVM_DIR}/nvm.sh" ]; then
  echo "Installing nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
source "${NVM_DIR}/nvm.sh"

# Install and use Node 20
nvm install ${NODE_VERSION}
nvm use ${NODE_VERSION}

echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"

# Monorepo dependency: the webpack-alias.js plugin looks for the relay compiler
# config schema at ../../compiler/crates/relay-compiler/relay-compiler-config-schema.json
# relative to website/plugins/. In the staging repo (which only has website/ files),
# this file is missing. Clone the source repo to get it.
SCHEMA_FILE="../compiler/crates/relay-compiler/relay-compiler-config-schema.json"
if [ ! -f "$SCHEMA_FILE" ]; then
    echo "[INFO] Fetching monorepo compiler schema from source..."
    DEPS_DIR="/tmp/relay-source-deps-$$"
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$DEPS_DIR"
    mkdir -p "../compiler/crates/relay-compiler"
    cp "$DEPS_DIR/compiler/crates/relay-compiler/relay-compiler-config-schema.json" "$SCHEMA_FILE"
    rm -rf "$DEPS_DIR"
    echo "[INFO] Schema file copied."
fi

# Enable corepack and install dependencies
corepack enable
yarn install

# Build the Docusaurus site
rm -rf build/ && yarn build

echo "[DONE] Build complete."
