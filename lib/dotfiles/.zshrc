#!/bin/zsh
#------------------------------------------------------------------------------
# Enable colors
autoload -Uz colors && colors
# Set command history settings
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
# Set custom prompt
FG_BLACK="{000}"
BG_RED="{009}" 
BG_GREEN="{010}"
BG_BLUE="{012}"
BG_MAGENTA="{013}"  
FG_USER=${FG_BLACK}
FG_DIR=${FG_BLACK}
BG_DIR=${BG_GREEN}
# Color based on user type
is_privileged() {
  [[ "$EUID" -eq 0 ]] && return 0
  local G=" $(id -Gn 2>/dev/null) "
  [[ "$G" == *" admin "* || "$G" == *" sudo "* || "$G" == *" wheel "* ]]
}
HOST_NAME=""
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
  BG_USER=${BG_MAGENTA}
  HOST_NAME="%m|"
else
  BG_USER=${BG_BLUE}
fi
if is_privileged; then
  BG_USER=${BG_RED}
fi
PS1_USER="%F${FG_USER}%K${BG_USER} %n [${HOST_NAME}%T] %F${BG_USER}%K${BG_DIR}"
PS1_DIR="%F${FG_DIR}%K${BG_DIR}%4~ %F${BG_DIR}%K{reset_color}%F{reset_color} "
export PS1="${PS1_USER} ${PS1_DIR}"
# Turn off all beeps
unsetopt BEEP
# Pass tty to GPG
if [[ -t 0 ]]; then
  export GPG_TTY=$(tty)
fi
# Make neovim default for sudoedit
export SUDO_EDITOR=nvim
#------------------------------------------------------------------------------
# Set shortcuts for default CLI tools
alias sudo='sudo '
if [[ "$OSTYPE" == linux* ]]; then
  alias ls='ls -lA --color=auto --group-directories-first'
elif [[ "$OSTYPE" == darwin* ]]; then
  # On MacOS, check for coreutils version of ls first
  if command -v gls >/dev/null 2>&1; then
    alias ls='gls -lA --color=auto --group-directories-first'
  else
    alias ls='ls -lAG'
  fi
fi
alias grep='grep --color=auto'
if command -v bat >/dev/null 2>&1; then
  alias bat='bat --style=plain --paging=never'
fi
if command -v batcat >/dev/null 2>&1; then
  alias bat='batcat --style=plain --paging=never'
fi
#------------------------------------------------------------------------------
# Load zsh modules
if [[ "$OSTYPE" == linux* ]]; then
  PATH_ZSH_PLUGINS="${HOME}/.local/share/zsh/plugins"
elif [[ "$OSTYPE" == darwin* ]]; then
  PATH_ZSH_PLUGINS="${HOME}/.zsh/plugins"
fi
[[ -r "${PATH_ZSH_PLUGINS}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
  source "${PATH_ZSH_PLUGINS}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -r "${PATH_ZSH_PLUGINS}/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
  source "${PATH_ZSH_PLUGINS}/zsh-autosuggestions/zsh-autosuggestions.zsh"
# -----------------------------------------------------------------------------
# Disable macOS Terminal session saving
if [[ "$OSTYPE" == darwin* ]]; then
  export SHELL_SESSIONS_DISABLE=1
fi
# -----------------------------------------------------------------------------

# LINUX SPECIFIC:

# Enable Wayland in Firefox
#if [[ "$OSTYPE" == linux* ]]; then
#    export MOZ_ENABLE_WAYLAND=1
#fi

# -----------------------------------------------------------------------------

# Add Tex to path
#export PATH="${PATH}:${HOME}/.texlive/bin/x86_64-linux"

# -----------------------------------------------------------------------------

# 1 Global Python defaults
#export PYTHON_VENV_PATH="${HOME}/.python_venv"
#export PIP_CACHE_DIR="${PYTHON_VENV_PATH}/pip-cache"
#export PYTHONPYCACHEPREFIX="${PYTHON_VENV_PATH}/pycache"

# 2 Global Jupyter defaults
#export PYDEVD_DISABLE_FILE_VALIDATION=1
#export JUPYTER_CONFIG_DIR="${PYTHON_VENV_PATH}/etc/jupyter"
#export JUPYTER_DATA_DIR="${PYTHON_VENV_PATH}/share/jupyter"
#export JUPYTER_RUNTIME_DIR="${PYTHON_VENV_PATH}/share/jupyter/runtime"
#export IPYTHONDIR="${PYTHON_VENV_PATH}/etc/ipython"

# 3 CLI aliases
#export PYTHON_VENV_BIN="/bin"
#alias venv-jupyter="${PYTHON_VENV_PATH}/bin/jupyter"
#alias venv-pip="${PYTHON_VENV_PATH}/bin/pip"
#alias venv-python="${PYTHON_VENV_PATH}/bin/python"
#alias venv-yt-dlp="${PYTHON_VENV_PATH}/bin/yt-dlp"

# -----------------------------------------------------------------------------
