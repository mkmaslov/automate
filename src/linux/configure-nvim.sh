#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script configures vim and neovim.
#------------------------------------------------------------------------------

# BEGIN_SHARED
#------------------------------------------------------------------------------
# This is a placeholder replaced with "shared.sh" when bundling.
# The script fails if the template is run directly.
printf '\e[1;31mERROR: this is a template script, do NOT run this\e[0m\n' >&2
return 1 2>/dev/null || exit 1
#------------------------------------------------------------------------------
# END_SHARED

#══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
#══════════════════════════════════════════════════════════════════════════════

# Verify that required packages are installed
enforce_cmds vim nvim git

# Obtain information about the user
USERNAME="$(id -un)"
GROUP_NAME="$(id -gn "${USERNAME}")"
PATH_HOME="$(eval echo "~${USERNAME}")"

# Paths
PATH_CONFIG_NVIM="${PATH_HOME}/.config/nvim"
PATH_INIT_LUA="${PATH_CONFIG_NVIM}/init.lua"
PATH_VIMRC="${PATH_HOME}/.vimrc"

# Create Neovim config folder
install -d -m 0755 -o "${USERNAME}" -g "${GROUP_NAME}" "${PATH_CONFIG_NVIM}"

# Download dotfiles
URL_VIMRC="${URL_REPO}/lib/dotfiles/.vimrc"
URL_INIT_LUA="${URL_REPO}/lib/nvim/init.lua"
download "${URL_VIMRC}" "${PATH_VIMRC}"
download "${URL_INIT_LUA}" "${PATH_INIT_LUA}"
chown "${USERNAME}:${GROUP_NAME}" "${PATH_VIMRC}" "${PATH_INIT_LUA}"

# Install plugins
nvim --headless "+Lazy! sync" +qa

success "Configured Vim and Neovim for user: ${USERNAME}"

#------------------------------------------------------------------------------