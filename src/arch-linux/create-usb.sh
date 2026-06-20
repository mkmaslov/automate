#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# This script creates a bootable USB drive using the latest Arch Linux image.
# -----------------------------------------------------------------------------

# BEGIN_SHARED
# -----------------------------------------------------------------------------
PRE=$'\033[1;31m'
MSG='ERROR: this is a template script, do NOT run this'
POST=$'\033[0m'
printf '%s%s%s\n' "$PRE" "$MSG" "$POST" >&2
return 1 2>/dev/null || exit 1
# -----------------------------------------------------------------------------
# END_SHARED

# Clean up on exit: unmount drives, if mounted
PATH_MOUNT="/mnt/arch-create-usb-cache"
cleanup() {
  local RC=$?
  if [[ -n ${PATH_MOUNT:-} ]]; then
    if mountpoint -q "$PATH_MOUNT"; then
      sudo umount "$PATH_MOUNT" || true
    fi
    [[ -d "$PATH_MOUNT" ]] && sudo rmdir "$PATH_MOUNT" 2>/dev/null || true
  fi
  exit "$RC"
}
trap cleanup EXIT INT TERM

# ═════════════════════════════════════════════════════════════════════════════
# MAIN SCRIPT
# ═════════════════════════════════════════════════════════════════════════════

# -----------------------------------------------------------------------------
# Download and verify disk image
# -----------------------------------------------------------------------------

title "Welcome to Arch Linux USB medium creation tool!"
title "Downloading the latest Arch Linux image and its GPG signature:"

# Download Arch Linux image and its GPG signature
PATH_CACHE="/tmp/arch-create-usb-cache"
PATH_IMAGE="${PATH_CACHE}/arch.iso"
PATH_SIG="${PATH_CACHE}/arch.sig"
# Use download mirror for Austria
# Mirrors for other countries: https://archlinux.org/download/
URL_ISO="https://mirror.easyname.at/archlinux/iso/latest/archlinux-x86_64.iso"
if [[ -f "${PATH_IMAGE}" && -f "${PATH_SIG}" ]]; then
  success "Cached image and signature found. Skipping download."
else
  # Create cache directory, if missing
  mkdir -p -- "${PATH_CACHE}"
  download "${URL_ISO}.sig" "${PATH_SIG}"
  download "${URL_ISO}" "${PATH_IMAGE}"
  success "Downloaded image and its GPG signature."
fi

# Verify image signature
title "Verifying image signature:"
msg "Output below should contain \"Good signature from ...\" line:"
gpg --keyserver-options auto-key-retrieve --verify "${PATH_SIG}" "${PATH_IMAGE}"
msg "The above fingerprint should match this fingerprint:"
msg "(obtained from https://archlinux.org/download/)"
PGP_KEY=$(curl --silent https://archlinux.org/download/ | \
  grep -o "title=\"PGP key search.*\"" | cut -d " " -f 5-14)
echo "Primary key fingerprint: ${PGP_KEY::-1}"
confirm_or_exit "Do you confirm that the GPG signature is correct [y/N]?"
success "Signature confirmed."

# -----------------------------------------------------------------------------
# Write image to disk
# -----------------------------------------------------------------------------

# Prompt for a target drive
TITLE="Select a USB drive (entire block device, not a partition):"
# Obtain information about disk drives
RAW=$(lsblk -dno NAME,SIZE,TRAN,MODEL | awk -v OFS='|' '{
  MODEL = substr($0, index($0, $4),20); print "/dev/" $1, $3, $2, MODEL}')
mapfile -t OPTIONS < <(printf '%s\n' "$RAW" | column -t  -s "|" -o " | ")
# Display options and wait for user response
single_choice CHOICE OPTIONS "$TITLE"
# Display user's choice
DISK="${OPTIONS[$CHOICE]%% *}"
MSG_STR="Proceeding will erase all data on"
MSG_STR+="${RED} ${DISK}${YELLOW}. Do you agree [y/N]?"
confirm_or_exit "${MSG_STR}"
success "Proceeding with ${DISK}."

title "Writing data to USB drives requires superuser privileges:"
# Unmount disk partitions and clean up the filesystem
unmount_disk_partitions "$DISK"
sudo wipefs --all -- "$DISK" >/dev/null
# Write image into the selected USB disk
status "Writing Arch Linux image to the USB drive: "
fail "DO NOT REMOVE THE DRIVE!"
sudo dd bs=4M if="${PATH_IMAGE}" \
  of="${DISK}" conv=fsync oflag=direct status=progress
# Update partition table
msg "Updating information about disk partitions, please wait."
sudo sync ; sudo partprobe "$DISK" ; sudo udevadm settle
success "Image written to ${DISK}."

# Create a FAT32 partition that spans the entire free space on the drive
msg "Creating data partition:"
PART_NUM="$(get_next_free_partition_number "$DISK")"
printf 'n\np\n%s\n\n\nw\n' "$PART_NUM" | sudo fdisk "$DISK" >/dev/null 2>&1
msg "Updating information about disk partitions, please wait."
sudo sync ; sudo partprobe "$DISK" ; sudo udevadm settle
PATH_PART="$(get_path_partition "$DISK" "$PART_NUM")"
sudo mkfs.vfat -F32 "${PATH_PART}" >/dev/null 2>&1
success "Data partition ${PATH_PART} created."

# Mount the partition and download Arch Linux installation script
title "Downloading Arch Linux installation script:"
sudo mkdir -p "${PATH_MOUNT}"
sudo mount "${PATH_PART}" "${PATH_MOUNT}"
URL_SCRIPT="https://git.ista.ac.at/mmaslov/scripts/-/raw/main/archinstall/install.sh"
download "${URL_SCRIPT}" "${PATH_CACHE}/install.sh"
sudo mv "${PATH_CACHE}/install.sh" "${PATH_MOUNT}/install.sh" >/dev/null 2>&1
sudo umount "${PATH_MOUNT}"
sudo rmdir "${PATH_MOUNT}"

# Print out further instructions
success "USB installation medium created."
MSG_STR="Arch Linux installation script (install.sh) "
MSG_STR+="is placed into the root folder of the ${PATH_PART} partition.\n"
MSG_STR+="You could use the same partition to store "
MSG_STR+="\"authorized_keys\" file for an SSH server."
msg "${MSG_STR}"

# Prompt whether to remove the cache directory (yes, by default)
ask RESPONSE "Do you want to remove the cache directory [Y/n]?"
if [[ $RESPONSE =~ ^(no|n|N|NO|No)$ ]]; then
  success "Finished. ${PATH_CACHE} is preserved."
  exit 0
else
  rm -rf "${PATH_CACHE}"
  success "Finished. ${PATH_CACHE} is removed."
  exit 0
fi

# -----------------------------------------------------------------------------