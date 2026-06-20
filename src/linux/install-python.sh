#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# Install Python into a virtual environment at ~/.python_venv
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

msg "Installing Python..."

# Verify that required packages are installed
enforce_cmds python3

# Obtain information about the user
USERNAME="$(id -un)"
GROUP_NAME="$(id -gn "${USERNAME}")"
PATH_HOME="$(eval echo "~${USERNAME}")"

# Set up a virtual environment for Python
PATH_VENV="${PATH_HOME}/.python_venv"
PIP="${PATH_VENV}/bin/pip"
mkdir -p "${PATH_VENV}/pip-cache"
mkdir -p "${PATH_VENV}/pycache"
cat > "${PATH_VENV}/pip.conf" <<-EOF
  [global]
  cache-dir=${PATH_VENV}/pip-cache
  require-virtualenv=true
EOF
python3 -m venv ${PATH_VENV}

# Update pip
${PIP} install --upgrade pip --require-virtualenv

# Add shortcuts to .zshrc
VENV_BLOCK="$(cat <<EOF
export PYTHON_VENV_PATH="\${HOME}/.python_venv"
export PIP_CACHE_DIR="\${PYTHON_VENV_PATH}/pip-cache"
export PYTHONPYCACHEPREFIX="\${PYTHON_VENV_PATH}/pycache"
EOF
)"
append_block "# Global Python defaults" "$VENV_BLOCK" "${PATH_HOME}/.zshrc"
VENV_BLOCK="$(cat <<EOF
export PYTHON_VENV_BIN="/bin"
alias venv-pip="\${PYTHON_VENV_PATH}/bin/pip"
alias venv-python="\${PYTHON_VENV_PATH}/bin/python"
EOF
)"
append_block "# Python CLI aliases" "$VENV_BLOCK" "${PATH_HOME}/.zshrc"

success "Successfully installed Python!"

#------------------------------------------------------------------------------