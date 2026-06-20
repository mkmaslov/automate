#------------------------------------------------------------------------------
# Custom prompt
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
  HOST_NAME="\h|"
else
  HOST_NAME=""
fi
COLOR_RESET="\[\e[0m\]"
FG_BLACK="\[\e[30m\]"
FG_YELLOW="\[\e[93m\]"
FG_GREEN="\[\e[92m\]"
BG_TRANSPARENT="\[\e[49m\]"
BG_YELLOW="\[\e[103m\]"
BG_GREEN="\[\e[102m\]"
PS1_USER="${FG_BLACK}${BG_YELLOW} \u [${HOST_NAME}\A] ${FG_YELLOW}${BG_GREEN}"
PS1_DIR="${FG_BLACK}${BG_GREEN}\w ${FG_GREEN}${BG_TRANSPARENT}${COLOR_RESET} "
export PS1="${PS1_USER} ${PS1_DIR}"
#------------------------------------------------------------------------------
# Set shortcuts for default CLI tools
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
#------------------------------------------------------------------------------