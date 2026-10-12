#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script creates new non-admin user on MacOS.
#------------------------------------------------------------------------------

# BEGIN_SHARED
#------------------------------------------------------------------------------
# This is a placeholder replaced with "shared.sh" when bundling.
# The script fails if the template is run directly.
printf '\e[1;31mERROR: this is a template script, do NOT run this\e[0m\n' >&2
return 1 2>/dev/null || exit 1
#------------------------------------------------------------------------------
# END_SHARED

#------------------------------------------------------------------------------
# Script-specific functions
#------------------------------------------------------------------------------

# Show usage instructions and exit
usage() { msg "Usage: ${0##*/} USERNAME \"Full Name\"" ; exit 1 ; }

#══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
#══════════════════════════════════════════════════════════════════════════════

USER="${1:-}"
FULLNAME="${2:-}"
SHELL="/bin/zsh"
PATH_HOME="/Users/$USER"
# Group ID = 20 (staff)
GROUP_ID="20"

[[ $EUID -eq 0 ]] || { error "Run with sudo." ; exit 1 ; }
[[ -n "$USER" && -n "$FULLNAME" ]] || { usage ; }
[[ "$USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || { error "Bad username: $USER" ; exit 1 ; }
# Verify if user with this username already exists
if dscl . -read "/Users/$USER" >/dev/null 2>&1; then
  error "User already exists: $USER" ; exit 0
fi

# Get UID
TARGET_UID="$(
  dscl . -list /Users UniqueID | awk '$2 >= 501 { print $2 }' | sort -n | tail -1
)"
TARGET_UID="${TARGET_UID:-500}"
TARGET_UID="$((TARGET_UID + 1))"

# Create user and set its password
dscl . -create "/Users/$USER"
dscl . -create "/Users/$USER" UserShell "$SHELL"
dscl . -create "/Users/$USER" RealName "$FULLNAME"
dscl . -create "/Users/$USER" UniqueID "$TARGET_UID"
dscl . -create "/Users/$USER" PrimaryGroupID "$GROUP_ID"
dscl . -create "/Users/$USER" NFSHomeDirectory "$PATH_HOME"
dscl . -create "/Users/$USER" IsHidden 1
echo "Set password for $USER:"
dscl . -passwd "/Users/$USER"

# Create home directory
createhomedir -c -u "$USER" >/dev/null
chown -R "$USER":staff "$PATH_HOME"

# Remove user from the admin group
dseditgroup -o edit -d "$USER" -t user admin >/dev/null 2>&1 || true

success "Created hidden non-admin CLI user: $USER"
id "$USER"
dseditgroup -o checkmember -m "$USER" admin

#------------------------------------------------------------------------------