#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script configures zsh shell.
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
enforce_cmds zsh git

# Obtain information about the user
USERNAME="$(id -un)"
GROUP_NAME="$(id -gn "${USERNAME}")"
PATH_HOME="$(eval echo "~${USERNAME}")"

# Works on Linux and MacOS
if [[ "${OSTYPE}" == darwin* ]]; then
    PATH_PLUGINS="${HOME}/.zsh/plugins"
else
    PATH_PLUGINS="${PATH_HOME}/.local/share/zsh/plugins"
fi
PATH_ZSHRC="${PATH_HOME}/.zshrc"
PATH_BASHRC="${PATH_HOME}/.bashrc"

# Create plugins folder
install -d -m 0755 -o "${USERNAME}" -g "${GROUP_NAME}" "${PATH_PLUGINS}"

# Download plugins
URL_PLUGIN_SUGGESTIONS="https://github.com/zsh-users/zsh-autosuggestions.git"
URL_PLUGIN_SYNTAX="https://github.com/zsh-users/zsh-syntax-highlighting.git"
fetch_git "${URL_PLUGIN_SUGGESTIONS}" "${PATH_PLUGINS}/zsh-autosuggestions"
fetch_git "${URL_PLUGIN_SYNTAX}" "${PATH_PLUGINS}/zsh-syntax-highlighting"

# Download dotfiles
URL_ZSHRC="${URL_REPO}/lib/dotfiles/.zshrc"
URL_BASHRC="${URL_REPO}/lib/dotfiles/.bashrc"
download "${URL_ZSHRC}" "${PATH_ZSHRC}"
download "${URL_BASHRC}" "${PATH_BASHRC}"
chown "${USERNAME}:${GROUP_NAME}" "${PATH_ZSHRC}" "${PATH_BASHRC}"

success "Configured zsh for user: ${USERNAME}"

# -----------------------------------------------------------------------------