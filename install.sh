#!/usr/bin/env bash
# matte.hx installation script.
#
# Copies the plug-in into ~/.steel/cogs/matte.hx/ - the same location Steel's
# forge package manager uses - so (require "matte.hx/matte.scm") resolves the
# same way whether it was installed via forge or this script. Pure Scheme; no
# dylib.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error()   { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info()    { echo -e "${YELLOW}→ $1${NC}"; }

# Run from the repository root.
[ -f "cog.scm" ] || error "cog.scm not found. Run this from the matte.hx repository root."

DEST="$HOME/.steel/cogs/matte.hx"

info "Installing into $DEST..."
mkdir -p "$DEST/src"
cp cog.scm matte.scm "$DEST/"
cp src/*.scm "$DEST/src/"
success "Installed matte.hx"

echo ""
info "Add (require \"matte.hx/matte.scm\") to ~/.config/helix/init.scm"
