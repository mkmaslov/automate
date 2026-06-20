#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script installs nvim in ${INSTALL_DIR} and creates symlink in ${BIN_DIR}.
#------------------------------------------------------------------------------

# BEGIN_SHARED
#------------------------------------------------------------------------------
PRE=$'\033[1;31m'
MSG='ERROR: this is a template script, do NOT run this'
POST=$'\033[0m'
printf '%s%s%s\n' "$PRE" "$MSG" "$POST" >&2
return 1 2>/dev/null || exit 1
#------------------------------------------------------------------------------
# END_SHARED

#══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
#══════════════════════════════════════════════════════════════════════════════

# Create directories
PATH_INSTALL="${HOME}/.local/opt"
DIR_BIN=".local/bin"
PATH_BIN="${HOME}/${DIR_BIN}"
PATH_TEMP="${HOME}/.TEMP_NVIM_INSTALL"
mkdir -p "${PATH_INSTALL}" "${PATH_BIN}" "${PATH_TEMP}"

# Download tarball
PKG_NAME="nvim-linux-x86_64"
URL="https://github.com/neovim/neovim/releases/latest/download/${PKG_NAME}.tar.gz"
download "${URL}" "${PATH_TEMP}/${PKG_NAME}.tar.gz"

# Extract tarball
tar xzf "${PATH_TEMP}/${PKG_NAME}.tar.gz" -C "${PATH_INSTALL}"

# Create a symlink
ln -sf "${PATH_INSTALL}/${PKG_NAME}/bin/nvim" "${PATH_BIN}/nvim"

# Add nvim to PATH
NVIM_BLOCK="$(cat <<EOF
export PATH="\${HOME}/$DIR_BIN:\${PATH}"
EOF
)"
export PATH="${HOME}/${DIR_BIN}:${PATH}"
append_block "# Add nvim to PATH" "$NVIM_BLOCK" "${HOME}/.zshrc"
append_block "# Add nvim to PATH" "$NVIM_BLOCK" "${HOME}/.bashrc"

# Configure nvim
URL="${URL_REPO}/dist/linux/configure-nvim.sh"
download "${URL}" "${PATH_TEMP}/configure-nvim.sh"
chmod +x "${PATH_TEMP}/configure-nvim.sh"
"${PATH_TEMP}/configure-nvim.sh"

# Remove temporary directory
rm -rf "${PATH_TEMP}"

#------------------------------------------------------------------------------