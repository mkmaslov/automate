#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script mounts/unmounts Veracrypt containers on MacOS.
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
usage() { msg "Usage: ${0##*/} [--mount | --unmount | --create-drive]" ; exit 1 ; }

# Get Veracrypt disk label: source or mapped
get_vc_disk() {
  local mode="$1" source_disk="${2:-}"
  sudo veracrypt --text --list |
    awk -v mode="$mode" -v src="$source_disk" '
      /^/ {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^\/dev\/disk[0-9]+$/ &&
            (mode == "source" || (mode == "mapped" && $i != src))) {
            print $i
            exit
          }
      }
    '
}

# Rename Veracrypt volume if assigned /Volume/Untitled by default
rename_vc_volume() {
  if [ -d "$PATH_VOLUME_DEFAULT" ] && [ ! -e "$PATH_VOLUME_TARGET" ]; then
    sudo diskutil rename "$PATH_VOLUME_DEFAULT" "$NAME_VOLUME" >/dev/null
  fi
}

# Mount a drive: in Veracrypt, then in diskutil
vc_mount() {
  title "Mounting Veracrypt drive..."
  enforce_cmds sudo diskutil veracrypt awk
  local source_disk
  choose_disk_macos source_disk
  mkdir -p "${PATH_VC_MOUNT}"
  sudo veracrypt --text --mount "${source_disk}" "${PATH_VC_MOUNT}" \
    --filesystem=none --pim=0 --keyfiles="" --protect-hidden=no
  local mapped_disk
  mapped_disk="$(get_vc_disk mapped "$source_disk")"
  [ -n "$mapped_disk" ] || { error "Could not detect VeraCrypt mapped disk"; exit 1; }
  msg "VeraCrypt source disk: $source_disk"
  msg "VeraCrypt mapped disk: $mapped_disk"
  sudo diskutil mount "$mapped_disk"
  rename_vc_volume
  success "Veracrypt volume mounted successfully at: ${PATH_VOLUME_TARGET}"
}

# Unmount the drive
vc_unmount() {
  title "Unmounting Veracrypt drive..."
  enforce_cmds sudo diskutil veracrypt awk
  local source_disk
  source_disk="$(get_vc_disk source)"
  [ -n "$source_disk" ] || { error "Could not detect VeraCrypt source disk"; exit 1; }
  local mapped_disk
  mapped_disk="$(get_vc_disk mapped "$source_disk")"
  [ -n "$mapped_disk" ] || { error "Could not detect VeraCrypt mapped disk"; exit 1; }
  msg "Unmounting mapped disk: $mapped_disk"
  sudo diskutil unmount "$mapped_disk" || true
  msg "Dismounting VeraCrypt source disk: $source_disk"
  sudo veracrypt --text --dismount "$source_disk"
  success 'Unmounted successfully.'
}

# Create a full-disk Veracrypt container with exFAT on selected drive
vc_create_drive() {
  title "Creating full-disk Veracrypt container..."
  enforce_cmds sudo diskutil veracrypt
  local source_disk confirm
  choose_disk_macos source_disk
  MSG_STR="Proceeding will erase all data on"
  MSG_STR+="${RED} ${source_disk}${YELLOW}. Do you agree [y/N]?"
  ask RESPONSE "${MSG_STR}"
  if [[ $RESPONSE =~ ^(yes|y|Y|YES|Yes)$ ]]; then
    success "Proceeding with ${source_disk}."
    local raw_disk="${source_disk/disk/rdisk}"
    sudo diskutil unmountDisk force "$source_disk" || true
    sudo veracrypt --text --create "$raw_disk" --quick \
      --volume-type=normal --encryption=AES --hash=SHA-512 \
      --filesystem=exFAT --pim=0 --keyfiles="" --random-source=/dev/urandom
    success "Created full-disk Veracrypt container on: $source_disk."
  else
    error "canceling operation."
  fi
}


#══════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
#══════════════════════════════════════════════════════════════════════════════

# Since Veracrypt is used with '--filesystem=none',
# PATH_VC_MOUNT is only required for bookkeeping
PATH_VC_MOUNT="${HOME}/Documents/Veracrypt"
NAME_VOLUME="Veracrypt"
PATH_VOLUME_DEFAULT="/Volumes/Untitled"
PATH_VOLUME_TARGET="/Volumes/${NAME_VOLUME}"

case "${1:-}" in
    --mount) vc_mount ;;
    --unmount) vc_unmount ;;
    --create-drive) vc_create_drive ;;
    -h|--help|"") usage ;;
    *) error "Unknown argument: $1"; usage; ;;
esac

#------------------------------------------------------------------------------