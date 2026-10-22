#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script downloads Debian disk image and injects deployment scripts.
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

enforce_cmds xorriso curl openssl
USAGE='-h <hostname> -u <username> -p <ssh-public-key-path>'
VM_HOSTNAME='' VM_USER='' SSH_KEY_FILE=''

while getopts ':h:u:p:' OPTION; do
  case "$OPTION" in
    h) VM_HOSTNAME="$OPTARG" ;;
    u) VM_USER="$OPTARG" ;;
    p) SSH_KEY_FILE="$OPTARG" ;;
    *) usage ;;
  esac
done
shift "$((OPTIND - 1))"
[[ $# -eq 0 ]] || usage
require_args -h "$VM_HOSTNAME" -u "$VM_USER" -p "$SSH_KEY_FILE"

[[ "$VM_HOSTNAME" =~ ^[a-z][a-z0-9-]*$ ]] || terminate 'Invalid hostname'
[[ "$VM_USER" =~ ^[a-z_][a-z0-9_-]*$ && "$VM_USER" != root ]] || terminate 'Invalid username'

SSH_PUBLIC_KEY="$(cat -- "$SSH_KEY_FILE")"
read -r KEY_TYPE KEY_DATA _ <<< "$SSH_PUBLIC_KEY"
[[ "$KEY_TYPE" == ssh-ed25519 && "$KEY_DATA" =~ ^[a-zA-Z0-9+/=]+$ ]] ||
  terminate 'Expected an ssh-ed25519 public key'

msg 'Set root password:'
ROOT_HASH="$(openssl passwd -6)"
msg "Set password for $VM_USER:"
USER_HASH="$(openssl passwd -6)"

cd "$(dirname "$0")"

URL_ISO="https://cdimage.debian.org/debian-cd/current/arm64/iso-cd"
PATH_TMP="$(mktemp -d)"
trap 'rm -rf "$PATH_TMP"' EXIT

sed \
  -e "s|HOSTNAME|$VM_HOSTNAME|g" \
  -e "s|USERNAME|$VM_USER|g" \
  -e "s|REPLACE_WITH_ROOT_PASSWORD_HASH|$ROOT_HASH|g" \
  -e "s|REPLACE_WITH_USER_PASSWORD_HASH|$USER_HASH|g" \
  -e "s|REPLACE_WITH_PUBLIC_KEY_DATA|$KEY_DATA|g" \
  deploy-debian-VM.cfg > "$PATH_TMP/preseed.cfg"

# Find and download the current netinst ISO.
ISO_NAME="$(curl -fsSL "$URL_ISO/SHA256SUMS" |
    awk '$2 ~ /^debian-[0-9.]+-arm64-netinst\.iso$/ { print $2; exit }')"
[[ -n "$ISO_NAME" ]] || { printf '%s\n' 'No arm64 netinst ISO found' >&2; exit 1; }
printf 'Downloading %s\n' "$ISO_NAME"
curl -fL "$URL_ISO/$ISO_NAME" -o "$PATH_TMP/$ISO_NAME"

# Make the default GRUB entry load preseed.cfg automatically.
xorriso -osirrox on -indev "$PATH_TMP/$ISO_NAME" \
  -extract /boot/grub/grub.cfg "$PATH_TMP/grub.cfg"
awk '
  /^[[:space:]]*linux[[:space:]]/ && /---/ {
    gsub(/[[:space:]]+console=[^[:space:]]+/, "")
    sub(/---/, "auto=true priority=critical preseed/file=/cdrom/preseed.cfg console=tty0 ---")
    found = 1
  }
  { print }
  END {
    if (!found) exit 1
    print "set default=0"
    print "set timeout=3"
  }
' "$PATH_TMP/grub.cfg" > "$PATH_TMP/grub-auto.cfg"

# Inject the preseed, provision script, and updated boot menu.
xorriso \
  -indev "$PATH_TMP/$ISO_NAME" \
  -outdev "$PATH_TMP/debian-auto.iso" \
  -map "$PATH_TMP/preseed.cfg" /preseed.cfg \
  -map deploy-debian-VM-docker.sh /provision.sh \
  -map "$PATH_TMP/grub-auto.cfg" /boot/grub/grub.cfg \
  -boot_image any replay \
  -compliance no_emul_toc \
  -padding included

mv -f "$PATH_TMP/debian-auto.iso" debian-auto.iso

#------------------------------------------------------------------------------