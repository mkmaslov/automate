#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# Install yt-dlp into a virtual environment at ~/.python_venv
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

msg "Installing yt-dlp..."

# Obtain information about the user
USERNAME="$(id -un)"
GROUP_NAME="$(id -gn "${USERNAME}")"
PATH_HOME="$(eval echo "~${USERNAME}")"

# Verify that Python virtual environment exists
PATH_VENV="${PATH_HOME}/.python_venv"
PIP="${PATH_VENV}/bin/pip"
[ -d "$PATH_VENV" ] || { error "${PATH_VENV} does not exist"; exit 1; }

# Install yt-dlp
${PIP} install yt-dlp
${PIP} install -U "yt-dlp[default]"

# Add shortcuts to .zshrc
VENV_BLOCK="$(cat <<EOF
alias yt-dlp="${PATH_VENV}/bin/yt-dlp"
EOF
)"
append_block "# Alias for yt-dlp" "$VENV_BLOCK" "${PATH_HOME}/.zshrc"

success "Successfully installed yt-dlp!"

#------------------------------------------------------------------------------