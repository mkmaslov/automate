#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script generates target locale on Arch Linux or Debian systems.
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

#------------------------------------------------------------------------------
# Script-specific functions
#------------------------------------------------------------------------------

# Show usage instructions and exit
usage() { msg "Usage: ${0##*/} [-l locale]" ; exit 1 ; }

# Enable target locale in locale.gen
enable_locale() {
  local file="/etc/locale.gen"
  [[ -f "$file" ]] || { error "$file not found"; exit 1; }
  if grep -Eq "^[[:space:]]*${LOCALE_GEN_ENTRY}$" "$file"; then
    :
  elif grep -Eq "^[[:space:]]*#[[:space:]]*${LOCALE_GEN_ENTRY}$" "$file"; then
    $SUDO sed -i "s|^[[:space:]]*#[[:space:]]*${LOCALE_GEN_ENTRY}$|${LOCALE_GEN_ENTRY}|" "$file"
  else
    echo "$LOCALE_GEN_ENTRY" | $SUDO tee -a "$file" >/dev/null
  fi
}

#══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
#══════════════════════════════════════════════════════════════════════════════

# Parse CLI arguments, exit if not specified
while getopts "l:" opt; do
  case "$opt" in
    l) LOCALE_SHORT="$OPTARG" ;;
    \*) usage ;;
  esac
done
[[ ${LOCALE_SHORT:-} ]] || usage
LOCALE="${LOCALE_SHORT}.UTF-8"
LOCALE_GEN_ENTRY="${LOCALE} UTF-8"

# Use sudo, if user is not root
[[ $EUID -ne 0 ]] && SUDO=sudo || SUDO=

# Obtain OS data
MSG_STR="Cannot detect OS: /etc/os-release not found"
[[ -r /etc/os-release ]] || { error "${MSG_STR}"; exit 1; }
source /etc/os-release

# Generate locale
case "${ID,,}:${ID_LIKE:-}" in
  arch*:*|*:*arch*)
    enforce_cmds locale-gen
    enable_locale
    $SUDO locale-gen
    echo "LANG=${LOCALE}" | $SUDO tee /etc/locale.conf >/dev/null
    ;;
  debian*:*|ubuntu*:*|linuxmint*:*|pop*:*|*:*debian*)
    enforce_cmds locale-gen || { $SUDO apt update; $SUDO apt install -y locales; }
    enable_locale
    $SUDO locale-gen
    if enforce_cmds update-locale; then
        $SUDO update-locale LANG="${LOCALE}"
    else
        echo "LANG=${LOCALE}" | $SUDO tee /etc/default/locale >/dev/null
    fi
    ;;
  *)
    error "Unsupported distribution: ID=${ID:-unknown} ID_LIKE=${ID_LIKE:-unknown}"
    exit 1
    ;;
esac

success "Locale generated!"

#------------------------------------------------------------------------------