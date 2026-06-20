#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script configures vim and neovim.
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

# Verify that required packages are installed
enforce_cmds tmux git

# Obtain information about the user
USERNAME="$(id -un)"
GROUP_NAME="$(id -gn "${USERNAME}")"
PATH_HOME="$(eval echo "~${USERNAME}")"

# Paths
PATH_TMUX_CONF="${PATH_HOME}/.tmux.conf"
PATH_TPM="${PATH_HOME}/.tmux/plugins/tpm"

# Download tmux config
URL_TMUX_CONF="${URL_REPO}/lib/dotfiles/.tmux.conf"
download "${URL_TMUX_CONF}" "${PATH_TMUX_CONF}"
chown "${USERNAME}:${GROUP_NAME}" "${PATH_TMUX_CONF}"

# Install TPM
fetch_git "https://github.com/tmux-plugins/tpm" "${PATH_TPM}"
chown -R "${USERNAME}:${GROUP_NAME}" "${PATH_HOME}/.tmux"

# Install and update plugins
"${PATH_TPM}/bin/install_plugins"
"${PATH_TPM}/bin/update_plugins" all

success "Configured tmux for user: ${USERNAME}"
msg "Start tmux, then press Prefix + I to install plugins."

#------------------------------------------------------------------------------